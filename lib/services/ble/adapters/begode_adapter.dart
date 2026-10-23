import 'dart:typed_data';

import '../../../models/wheel_capabilities.dart';
import '../../../models/wheel_identity.dart';
import '../wheel_command.dart';
import 'wheel_adapter.dart';

/// Adaptador Begode (Gotway): telemetría y comandos de control.
///
/// Protocolo: flujo continuo sin polling sobre el transporte serie
/// compartido (`ffe0/ffe1`). Tramas binarias de **24 bytes** con
/// cabecera `55 AA`, cola `5A 5A 5A 5A` y tipo en el byte 18, **sin
/// checksum**: como las notificaciones BLE parten las tramas en
/// trozos arbitrarios, un desempaquetador con estado resincroniza
/// buscando la cabecera, valida la cola y reensambla incluso los
/// paquetes «basura» `55 AA 5A…` documentados del protocolo. Al
/// conectar, la rueda también emite líneas de texto ASCII con su
/// modelo (`NAME …`) y su firmware (`GW…` Begode, `JN…` Extreme
/// Bull, `CF…`/`BF…` firmwares personalizados).
///
/// Tramas implementadas:
/// - `0x00` (A, en vivo): voltaje, velocidad, distancia del viaje,
///   corriente de fase, temperatura del IMU y PWM de salida.
/// - `0x04` (B): distancia total y ajustes actuales (modo de
///   pedales, alarmas, tilt-back, LED, luz y banderas de alerta).
/// - `0x01`: voltaje real de batería del SmartBMS (sustituye al de
///   la trama A cuando la rueda lo reporta), límite de PWM y
///   corriente del BMS.
/// - `0x02`/`0x03`: SmartBMS 1/2 — de momento solo se cuenta el
///   número de celdas detectadas.
/// - `0x07`: corriente real de batería, temperatura del motor y
///   PWM real.
///
/// El voltaje de la trama A viene referido a un pack de 67.2 V:
/// para packs mayores hay que reescalarlo (ver
/// [scalerForVoltageIndex]); el % de batería se calcula por curva
/// sobre el voltaje **sin** reescalar, igual que en la
/// implementación de referencia del protocolo.
///
/// Los comandos de control de Begode NO se construyen aquí: cuando
/// se implementen, saldrán únicamente por la compuerta de seguridad
/// (safety_gate.dart). Apagar y bloquear el motor quedan fuera en
/// cualquier caso: no están verificados en el protocolo abierto.
class BegodeAdapter extends BaseWheelAdapter {
  BegodeAdapter({
    double voltageScaler = 1.0,
    bool autoVoltage = true,
  })  : _voltageScaler = voltageScaler,
        _autoVoltage = autoVoltage;

  /// Tipos de trama: byte 18.
  static const int typeLive = 0x00;
  static const int typeBmsInfo = 0x01;
  static const int typeSmartBms1 = 0x02;
  static const int typeSmartBms2 = 0x03;
  static const int typeSettings = 0x04;
  static const int typeRealCurrent = 0x07;
  static const int typeCustomFirmwareConfig = 0xFF;

  /// Factor de reescalado del voltaje según el pack elegido.
  final double _voltageScaler;

  /// Si es true (configuración verificada de referencia), cuando la
  /// rueda reporta su voltaje real por la trama `0x01` ese valor
  /// manda y la trama A deja de actualizar el voltaje.
  final bool _autoVoltage;

  final _BegodeUnpacker _unpacker = _BegodeUnpacker();

  String? _model;
  String? _firmware;
  String? _firmwareFamily;

  bool _trueVoltage = false;
  bool _trueCurrent = false;
  bool _truePwm = false;

  double _phaseCurrentA = 0;
  double _topSpeedKmh = 0;
  int? _pwmLimit;
  double? _bmsCurrentA;
  int _detectedCells = 0;

  int? _pedalMode;
  int? _speedAlarmMode;
  int? _rollAngleMode;
  bool? _inMiles;
  int? _autoOffSeconds;
  int? _tiltBackSpeedKmh;
  int? _ledMode;
  int? _lightMode;
  int? _alertFlags;

  /// Corriente de fase de la última trama A, en amperios.
  double get phaseCurrentA => _phaseCurrentA;

  /// Velocidad máxima (en valor absoluto) vista en las tramas A.
  double get topSpeedKmh => _topSpeedKmh;

  /// Familia del firmware anunciada al conectar: «Begode»,
  /// «ExtremeBull», «Freestyl3r» o «SmirnoV»; null si aún no llega.
  String? get firmwareFamily => _firmwareFamily;

  /// Límite de PWM reportado por la trama `0x01`, si ya llegó.
  int? get pwmLimit => _pwmLimit;

  /// Corriente del SmartBMS reportada por la trama `0x01`, en A.
  double? get bmsCurrentA => _bmsCurrentA;

  /// Celdas contadas en las tramas SmartBMS (`0x02`/`0x03`).
  int get detectedCells => _detectedCells;

  /// Modo de pedales de la trama B (bits 13–14 de ajustes): 0–3.
  int? get pedalMode => _pedalMode;

  /// Modo de alarmas de velocidad de la trama B (bits 10–11).
  int? get speedAlarmMode => _speedAlarmMode;

  /// Modo de ángulo de corte (roll) de la trama B (bits 7–8).
  int? get rollAngleMode => _rollAngleMode;

  /// La rueda está configurada en millas (bit 0 de ajustes).
  bool? get inMiles => _inMiles;

  /// Segundos de apagado automático de la trama B.
  int? get autoOffSeconds => _autoOffSeconds;

  /// Velocidad de tilt-back configurada, km/h (la trama B reporta
  /// 100 o más cuando está desactivada: se normaliza a 0).
  int? get tiltBackSpeedKmh => _tiltBackSpeedKmh;

  /// Modo LED de la trama B.
  int? get ledMode => _ledMode;

  /// Modo de luz de la trama B: 0 apagada, 1 encendida, 2 estrobo.
  int? get lightMode => _lightMode;

  /// Banderas de alerta crudas de la trama B (byte 14): bit0 alta
  /// potencia, bit1/bit2 alarmas de velocidad 2/1, bit3 bajo
  /// voltaje, bit4 sobrevoltaje, bit5 sobretemperatura, bit6 error
  /// de sensores Hall, bit7 modo transporte.
  int? get alertFlags => _alertFlags;

  @override
  WheelBrand get brand => WheelBrand.begode;

  @override
  WheelCapabilities get capabilities => const WheelCapabilities(
        telemetry: true,
        lights: true,
        beep: true,
        led: true,
        volume: true,
        pedalMode: true,
        speedAlarms: true,
        tiltBack: true,
        calibration: true,
      );

  @override
  List<Uint8List> initialRequests() => [
        // Peticiones de identidad del protocolo: «V» pide la versión
        // de firmware y «N» el nombre/modelo. Son bytes de SOLO
        // LECTURA verificados en la implementación de referencia;
        // no forman parte de la tabla de comandos de control ASCII
        // del protocolo, así que no pasan por la compuerta.
        Uint8List.fromList([0x56]), // 'V'
        Uint8List.fromList([0x4E]), // 'N'
      ];

  @override
  bool decode(Uint8List data) {
    var newDataFound = false;

    // Texto de arranque (nombre/firmware): solo se busca mientras
    // falte alguno de los dos datos, como hace la referencia.
    if (_model == null || _firmware == null) {
      _sniffStartupText(data);
    }

    for (final byte in data) {
      if (_unpacker.addByte(byte)) {
        final result = _processFrame(_unpacker.buffer);
        if (result != null) newDataFound = result;
      }
    }
    return newDataFound;
  }

  /// Líneas ASCII que la rueda emite al conectar: `NAME <modelo>`
  /// y el firmware con prefijo `GW` (Begode), `JN` (Extreme Bull),
  /// `CF` (Freestyl3r) o `BF` (SmirnoV). También llega una línea
  /// `MPU…` con el tipo de IMU, que no se usa.
  void _sniffStartupText(Uint8List data) {
    final text = String.fromCharCodes(data.map((b) => b & 0xFF)).trim();
    if (text.startsWith('NAME')) {
      // Tras «NAME» viene el modelo (a veces pegado con «:»); la
      // línea puede llegar partida entre notificaciones.
      if (text.length <= 5) return;
      final model = text.substring(5).trim();
      if (model.isEmpty) return;
      _model = model;
      _publishIdentity();
    } else if (text.startsWith('GW')) {
      _setFirmware(text, 'Begode');
    } else if (text.startsWith('JN')) {
      _setFirmware(text, 'ExtremeBull');
    } else if (text.startsWith('CF')) {
      _setFirmware(text, 'Freestyl3r');
    } else if (text.startsWith('BF')) {
      _setFirmware(text, 'SmirnoV');
    }
  }

  void _setFirmware(String text, String family) {
    final version = text.substring(2).trim();
    if (version.isEmpty) return;
    _firmware = version;
    _firmwareFamily = family;
    _publishIdentity();
  }

  void _publishIdentity() {
    updateIdentity(identity.copyWith(
      brand: WheelBrand.begode,
      model: _model,
      firmware: _firmware,
    ));
    if (_model != null) {
      updateTelemetry(telemetry.copyWith(model: _model));
    }
  }

  /// Procesa una trama completa de 24 bytes ya reensamblada.
  ///
  /// Devuelve el valor que debe tomar el resultado de [decode]
  /// («llegó telemetría en vivo») o null si este tipo de trama no
  /// lo altera, replicando la semántica de la referencia: la trama
  /// A cuenta como dato en vivo salvo que el voltaje real (`0x01`)
  /// o la corriente real (`0x07`) ya estén tomando el relevo.
  bool? _processFrame(Uint8List frame) {
    switch (frame[18]) {
      case typeLive:
        return _decodeLive(frame);
      case typeBmsInfo:
        return _decodeBmsInfo(frame);
      case typeSmartBms1 || typeSmartBms2:
        _decodeSmartBms(frame);
        return null;
      case typeSettings:
        _decodeSettings(frame);
        return null;
      case typeRealCurrent:
        return _decodeRealCurrent(frame);
      default:
        // 0xFF (configuración de firmware personalizado) y tipos
        // desconocidos: informativos, sin telemetría que publicar.
        return null;
    }
  }

  bool _decodeLive(Uint8List frame) {
    final voltageRaw = _getU16BE(frame, 2);
    final speedRaw = _getS16BE(frame, 4);
    // Ojo: la distancia del viaje NO es el campo de 32 bits de los
    // bytes 6–9; la referencia la lee como u16 en el offset 8.
    final tripDistanceM = _getU16BE(frame, 8);
    final phaseCurrentRaw = _getS16BE(frame, 10);
    final tempRaw = _getS16BE(frame, 12);
    final pwmRaw = _getS16BE(frame, 14);

    final speedKmh = (speedRaw * 3.6).round() / 100.0;
    _phaseCurrentA = phaseCurrentRaw / 100.0;
    if (speedKmh.abs() > _topSpeedKmh) _topSpeedKmh = speedKmh.abs();

    // El % de batería se calcula sobre el voltaje SIN reescalar.
    final batteryPct = batteryLevelFor(voltageRaw);

    double? voltageV;
    if (!(_trueVoltage && _autoVoltage)) {
      voltageV = (voltageRaw * _voltageScaler).round() / 100.0;
    }
    final effectiveVoltageV = voltageV ?? telemetry.voltageV;

    updateTelemetry(telemetry.copyWith(
      speedKmh: speedKmh,
      voltageV: voltageV,
      currentA: _phaseCurrentA,
      powerW: effectiveVoltageV * _phaseCurrentA,
      batteryPct: batteryPct,
      // Temperatura del IMU (MPU6050): (raw / 340 + 36.53) °C.
      tempC: tempRaw / 340.0 + 36.53,
      pwmPct: _truePwm ? null : pwmRaw / 10.0,
      distanceM: tripDistanceM,
    ));

    return !((_trueVoltage && _autoVoltage) || _trueCurrent);
  }

  bool _decodeBmsInfo(Uint8List frame) {
    // El resultado se evalúa ANTES de marcar el voltaje real.
    final result = !_trueCurrent && _trueVoltage && _autoVoltage;
    _trueVoltage = true;

    _pwmLimit = _getU16BE(frame, 2);
    if (_autoVoltage) {
      // Voltaje real del pack: llega en décimas de centivoltio
      // (la referencia lo multiplica por 10 y lo guarda en cV).
      final voltageV = _getU16BE(frame, 6) / 10.0;
      updateTelemetry(telemetry.copyWith(
        voltageV: voltageV,
        powerW: voltageV * telemetry.currentA,
      ));
    }
    _bmsCurrentA = _getS16BE(frame, 8) / 10.0;
    return result;
  }

  void _decodeSmartBms(Uint8List frame) {
    // Solo se cuentan las celdas con voltaje distinto de cero; el
    // resto de datos del SmartBMS (temperaturas, mitades de pack)
    // aún no se expone en el modelo de telemetría.
    final packet = frame[19] & 0xFF;
    for (var i = 0; i < 8; i++) {
      final cellIndex = i + packet * 8;
      final cellV = _getU16BE(frame, (i + 1) * 2) / 1000.0;
      if (cellV != 0 && cellIndex + 1 > _detectedCells) {
        _detectedCells = cellIndex + 1;
      }
    }
  }

  void _decodeSettings(Uint8List frame) {
    updateTelemetry(telemetry.copyWith(totalDistanceM: _getS32BE(frame, 2)));

    final settings = _getU16BE(frame, 6);
    _pedalMode = (settings >> 13) & 0x03;
    _speedAlarmMode = (settings >> 10) & 0x03;
    _rollAngleMode = (settings >> 7) & 0x03;
    _inMiles = (settings & 0x01) == 1;
    _autoOffSeconds = _getU16BE(frame, 8);
    final tiltBack = _getU16BE(frame, 10);
    _tiltBackSpeedKmh = tiltBack >= 100 ? 0 : tiltBack;
    _ledMode = frame[13] & 0xFF;
    _alertFlags = frame[14] & 0xFF;
    _lightMode = frame[15] & 0x03;
  }

  bool _decodeRealCurrent(Uint8List frame) {
    // El resultado se evalúa ANTES de marcar la corriente real.
    final result = _trueCurrent;
    _trueCurrent = true;

    // La corriente real de batería llega con el signo invertido.
    final batteryCurrentA = -_getS16BE(frame, 2) / 100.0;
    // Temperatura del motor: el crudo ya viene en °C enteros (la
    // referencia lo multiplica por 100 al guardarlo en centésimas).
    final motorTempC = _getS16BE(frame, 6).toDouble();
    final pwmRaw = _getS16BE(frame, 8);
    if (pwmRaw.abs() > 0) _truePwm = true;

    updateTelemetry(telemetry.copyWith(
      currentA: batteryCurrentA,
      powerW: telemetry.voltageV * batteryCurrentA,
      temp2C: motorTempC,
      // Con la convención de signos de la referencia, el PWM real
      // se publica negado respecto al crudo.
      pwmPct: _truePwm ? -pwmRaw.toDouble() : null,
    ));
    return result;
  }

  /// % de batería por la curva estándar del protocolo sobre el
  /// voltaje crudo (referido a 67.2 V, en centivoltios).
  static int batteryLevelFor(int voltageCv) {
    if (voltageCv <= 5290) return 0;
    if (voltageCv >= 6580) return 100;
    return (voltageCv - 5290) ~/ 13;
  }

  /// Factor de reescalado del voltaje por clase de pack (índice de
  /// voltaje de la referencia): 0→67.2 V, 1→84 V, 2→100.8 V,
  /// 3→116 V, 4→134.4 V, 5→168 V, 6→151.2 V.
  static double scalerForVoltageIndex(int index) => switch (index) {
        1 => 1.25,
        2 => 1.5,
        3 => 1.7380952380952381,
        4 => 2.0,
        5 => 2.5,
        6 => 2.25,
        _ => 1.0,
      };

  /// Número de celdas por clase de pack (mismo índice que
  /// [scalerForVoltageIndex]).
  static int cellsForVoltageIndex(int index) => switch (index) {
        0 => 16,
        1 => 20,
        2 => 24,
        3 => 32,
        4 => 32,
        5 => 40,
        6 => 36,
        _ => 24,
      };

  static int _getU16BE(Uint8List data, int offset) =>
      ((data[offset] & 0xFF) << 8) | (data[offset + 1] & 0xFF);

  static int _getS16BE(Uint8List data, int offset) {
    final v = _getU16BE(data, offset);
    return v >= 0x8000 ? v - 0x10000 : v;
  }

  static int _getS32BE(Uint8List data, int offset) =>
      ByteData.sublistView(data).getInt32(offset, Endian.big);

  // ---------------------------------------------------------------------------
  // Comandos de control: bytes ASCII sueltos (el protocolo «de
  // juguete» de Gotway). La referencia manda el byte del comando y,
  // en la mayoría de comandos, un «b» de cierre 100 ms después.
  // Como cualquier byte suelto puede leerse como comando, estas
  // tramas SOLO pueden salir por la compuerta de seguridad.
  // Apagar y bloquear NO están verificados en la referencia para
  // Begode: no se ofrecen.

  static List<int> _ascii(String s) => s.codeUnits;

  /// Comando simple: el byte ahora y «b» a los 100 ms.
  static List<CommandStep> _simple(String command) => [
        CommandStep(_ascii(command)),
        CommandStep(_ascii('b'),
            delayBefore: const Duration(milliseconds: 100)),
      ];

  @override
  List<CommandStep>? buildCommand(WheelCommandRequest request) {
    switch (request) {
      case LightRequest(:final state):
        return _simple(switch (state) {
          LightState.off => 'E',
          LightState.on => 'Q',
          LightState.strobe => 'T',
        });
      case BeepRequest():
        // El beep de la referencia va directo, sin cierre.
        return [CommandStep(_ascii('b'))];
      case PedalModeRequest(:final mode):
        if (mode < 0 || mode > 2) return null;
        return _simple(const ['h', 'f', 's'][mode]);
      case AlarmModeRequest(:final mode):
        if (mode < 0 || mode > 3) return null;
        return _simple(const ['o', 'u', 'i', 'I'][mode]);
      case CalibrationRequest():
        return [
          CommandStep(_ascii('c')),
          CommandStep(_ascii('y'),
              delayBefore: const Duration(milliseconds: 300)),
        ];
      case TiltBackRequest(:final kmh):
        const step = Duration(milliseconds: 100);
        if (kmh <= 0) {
          // Sin límite: «b», comilla de cierre y doble «b».
          return [
            CommandStep(_ascii('b')),
            CommandStep(_ascii('"'), delayBefore: step),
            CommandStep(_ascii('b'), delayBefore: step),
            CommandStep(_ascii('b'), delayBefore: step),
          ];
        }
        final v = kmh.clamp(0, 99);
        final tens = String.fromCharCode(0x30 + v ~/ 10);
        final units = String.fromCharCode(0x30 + v % 10);
        return [
          CommandStep(_ascii('b')),
          CommandStep(_ascii('W'), delayBefore: step),
          CommandStep(_ascii('Y'), delayBefore: step),
          CommandStep(_ascii(tens), delayBefore: step),
          CommandStep(_ascii(units), delayBefore: step),
          CommandStep(_ascii('b'), delayBefore: step),
          CommandStep(_ascii('b'), delayBefore: step),
        ];
      case LedModeRequest(:final mode):
        const step = Duration(milliseconds: 100);
        final digit = String.fromCharCode(0x30 + (mode % 10));
        return [
          CommandStep(_ascii('W'), delayBefore: step),
          CommandStep(_ascii('M'), delayBefore: step),
          CommandStep(_ascii(digit), delayBefore: step),
          CommandStep(_ascii('b'), delayBefore: step),
        ];
      case VolumeRequest(:final level):
        const step = Duration(milliseconds: 100);
        final digit = String.fromCharCode(0x30 + (level % 10));
        return [
          CommandStep(_ascii('W'), delayBefore: step),
          CommandStep(_ascii('B'), delayBefore: step),
          CommandStep(_ascii(digit), delayBefore: step),
          CommandStep(_ascii('b'), delayBefore: step),
        ];
      default:
        return null;
    }
  }
}

/// Desempaquetador del flujo Begode: máquina de estados que busca
/// la cabecera `55 AA`, acumula hasta 24 bytes validando que la
/// cola sean `5A` y reensambla los paquetes «basura» documentados
/// (`55 AA 5A 55 AA…` y `55 AA 5A 5A 55 AA…`, que en realidad son
/// el arranque de la siguiente trama tras unos bytes espurios).
class _BegodeUnpacker {
  static const int _unknown = 0;
  static const int _collecting = 1;
  static const int _done = 2;

  final List<int> _buffer = [];
  int _state = _unknown;
  int _oldc = -1;

  /// La última trama completa de 24 bytes reensamblada.
  Uint8List get buffer => Uint8List.fromList(_buffer);

  /// Alimenta un byte; devuelve true cuando se completa una trama.
  bool addByte(int c) {
    c &= 0xFF;
    if (_state == _collecting) {
      _buffer.add(c);
      _oldc = c;
      final size = _buffer.length;
      if (size > 20 && size <= 24 && c != 0x5A) {
        // La cola no es 5A: trama inválida, a resincronizar.
        _state = _unknown;
        return false;
      }
      if (size == 24) {
        _state = _done;
        return true;
      }
      if (size == 5 &&
          _buffer[0] == 0x55 &&
          _buffer[1] == 0xAA &&
          _buffer[2] == 0x5A &&
          _buffer[3] == 0x55 &&
          _buffer[4] == 0xAA) {
        _buffer
          ..clear()
          ..addAll([0x55, 0xAA]);
      }
      if (size == 6 &&
          _buffer[0] == 0x55 &&
          _buffer[1] == 0xAA &&
          _buffer[2] == 0x5A &&
          _buffer[3] == 0x5A &&
          _buffer[4] == 0x55 &&
          _buffer[5] == 0xAA) {
        _buffer
          ..clear()
          ..addAll([0x55, 0xAA]);
      }
    } else {
      if (c == 0xAA && _oldc == 0x55) {
        _buffer
          ..clear()
          ..addAll([0x55, 0xAA]);
        _state = _collecting;
      }
      _oldc = c;
    }
    return false;
  }
}
