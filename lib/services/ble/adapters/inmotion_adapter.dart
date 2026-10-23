import 'dart:typed_data';

import '../../../models/wheel_capabilities.dart';
import '../../../models/wheel_identity.dart';
import '../wheel_command.dart';
import 'wheel_adapter.dart';

/// Adaptador InMotion, protocolo **V2**: telemetría y comandos de
/// control verificados (luz, velocidad máxima, bloqueo, calibración,
/// apagado en dos etapas…).
///
/// Transporte: Nordic UART (servicio `6e400001`, RX `…0002`,
/// TX `…0003`); la detección llega por la huella GATT de ese
/// transporte y el olfateo de la primera trama (`AA AA`).
///
/// A diferencia de las demás marcas, esta rueda **no emite en
/// continuo**: solo responde cuando se le pregunta. Por eso el
/// adaptador declara [pollRequests] y [pollInterval]: el
/// controlador repite las peticiones de solo lectura mientras
/// dure la conexión (tipo de vehículo, serie y versiones al
/// inicio; batería, totales y tiempo real en cada ronda).
///
/// Tramas: cabecera `AA AA`, y el resto del cuerpo viaja con
/// escape — un byte `A5` delante de cada `AA` o `A5` literal —.
/// El cuerpo ya sin escapes es `[flags][len][comando][datos…]`
/// y al final va 1 byte de suma: el XOR de todo lo anterior
/// (la cabecera incluida da igual: `AA ^ AA = 0`). El comando
/// llega con el bit alto puesto y se lee enmascarado con `0x7F`;
/// `len` cuenta comando + datos, así que los datos miden
/// `len - 1` bytes y la trama completa `len + 5`.
///
/// Mensajes que se interpretan:
/// - `flags 0x11`, comando MainInfo (`0x02`): identidad. El
///   subcomando `0x01` trae serie/tipo del vehículo (el modelo
///   sale de `serie * 10 + tipo`), el `0x02` el número de serie
///   (16 caracteres ASCII) y el `0x06` las versiones de las tres
///   placas, con el formato «Main:x.y.z Drv:x.y.z BLE:x.y.z».
///   En la V11, la versión de la placa principal decide la
///   variante del layout de tiempo real: principal < 1.4 →
///   protocolo 1; 1.4 o posterior → protocolo 2.
/// - `flags 0x14`, comando TotalStats (`0x11`): el odómetro es
///   un u32 little-endian al inicio, en decenas de metro (×10).
/// - `flags 0x14`, comando BatteryRealTimeInfo (`0x05`): voltaje
///   y temperatura de cada pack y voltaje/corriente de carga.
/// - `flags 0x14`, comando RealTimeInfo (`0x04`): la telemetría
///   en vivo, con **un layout distinto por familia de modelo**:
///   V11 (dos variantes según la placa), V12 (HS/HT/Pro), V13,
///   y una familia nueva compartida por V14, V11Y, V9 y V12S.
///   Casi todo viaja en centésimas (÷100) little-endian; las
///   temperaturas de un byte viajan desplazadas (valor − 176).
///   La distancia del viaje es un u16 en decenas de metro,
///   salvo en la V13, donde es un u32 en metros con las dos
///   mitades de 16 bits intercambiadas.
///
/// Las tramas de ajustes (`0x20`) se reconocen pero no se
/// interpretan en esta fase (la referencia las vuelca en
/// preferencias de la app, no en telemetría), y las de
/// diagnóstico no aportan datos. El protocolo clásico de
/// InMotion (transporte `ffe0`, CAN sobre BLE) queda **fuera**:
/// esta fase cubre solo el V2, que es el de las ruedas actuales.
///
/// Los comandos de control de este protocolo NO se construyen
/// aquí: existen en la referencia (luces, sonidos, calibración y
/// hasta un apagado en dos etapas), pero quedan fuera de esta
/// fase; cuando se implementen, saldrán únicamente por la
/// compuerta de seguridad (safety_gate.dart).
class InMotionAdapter extends BaseWheelAdapter {
  // Flags y comandos del protocolo.
  static const int _flagInitial = 0x11;
  static const int _flagDefault = 0x14;
  static const int _cmdMainInfo = 0x02;
  static const int _cmdDiagnostic = 0x03;
  static const int _cmdRealTimeInfo = 0x04;
  static const int _cmdBatteryRealTimeInfo = 0x05;
  static const int _cmdTotalStats = 0x11;
  static const int _cmdSettings = 0x20;

  final _InMotionUnpacker _unpacker = _InMotionUnpacker();

  _InMotionModel _model = _InMotionModel.unknown;

  /// Variante del layout de tiempo real de la V11: 0 = aún no
  /// conocida, 1 = placa principal anterior a 1.4, 2 = 1.4+.
  /// Solo la fija la trama de versiones, y solo para la V11.
  int _protoVer = 0;

  // Datos extra que el modelo compartido no tiene (última trama).
  double? _torqueNm;
  double? _pitchDeg;
  double? _rollDeg;
  double? _motorPowerW;
  int? _remainMileageM;
  double? _dynamicSpeedLimitKmh;
  double? _dynamicCurrentLimitA;
  int? _motorTempC;
  int? _batteryTempC;
  int? _boardTempC;
  int? _cpuTempC;
  int? _imuTempC;
  int? _lampTempC;
  bool? _charging;
  bool? _lifted;
  bool? _lightOn;
  double? _pack1VoltageV;
  int? _pack1Temp;
  double? _pack2VoltageV;
  int? _pack2Temp;
  double? _chargeVoltageV;
  double? _chargeCurrentA;

  /// Par motor de la última trama de tiempo real, en N·m.
  double? get torqueNm => _torqueNm;

  /// Ángulo de pitch (inclinación adelante/atrás), en grados.
  double? get pitchDeg => _pitchDeg;

  /// Ángulo de roll (inclinación lateral), en grados.
  double? get rollDeg => _rollDeg;

  /// Potencia del motor de la última trama, en W (la del pack
  /// es la que va en el snapshot compartido).
  double? get motorPowerW => _motorPowerW;

  /// Autonomía restante estimada por la rueda, en metros.
  int? get remainMileageM => _remainMileageM;

  /// Límite dinámico de velocidad que aplica la rueda, en km/h.
  double? get dynamicSpeedLimitKmh => _dynamicSpeedLimitKmh;

  /// Límite dinámico de corriente que aplica la rueda, en A.
  double? get dynamicCurrentLimitA => _dynamicCurrentLimitA;

  /// Temperaturas extra de la última trama, en °C.
  int? get motorTempC => _motorTempC;
  int? get batteryTempC => _batteryTempC;
  int? get boardTempC => _boardTempC;
  int? get cpuTempC => _cpuTempC;
  int? get imuTempC => _imuTempC;
  int? get lampTempC => _lampTempC;

  /// ¿La rueda reporta estar cargando / levantada / con la luz
  /// encendida en la última trama de tiempo real?
  bool? get charging => _charging;
  bool? get lifted => _lifted;
  bool? get lightOn => _lightOn;

  /// Datos por pack de la última trama de baterías: voltaje en
  /// V y temperatura tal como la reporta la rueda.
  double? get pack1VoltageV => _pack1VoltageV;
  int? get pack1Temp => _pack1Temp;
  double? get pack2VoltageV => _pack2VoltageV;
  int? get pack2Temp => _pack2Temp;

  /// Voltaje y corriente de carga reportados, en V y A.
  double? get chargeVoltageV => _chargeVoltageV;
  double? get chargeCurrentA => _chargeCurrentA;

  /// Variante del protocolo de la V11 (0, 1 o 2; ver [_protoVer]).
  int get protocolVersion => _protoVer;

  /// Nombre del modelo ya identificado, o null si aún no llega
  /// la trama de tipo de vehículo (o no se reconoce).
  String? get modelName => _model.displayName;

  @override
  WheelBrand get brand => WheelBrand.inmotionV2;

  @override
  WheelCapabilities get capabilities => const WheelCapabilities(
        telemetry: true,
        lights: true,
        beep: true,
        tiltBack: true,
        speedAlarms: true,
        calibration: true,
        motorLock: true,
        powerOff: true,
        transportMode: true,
      );

  @override
  List<Uint8List> initialRequests() => <Uint8List>[
        getCarTypeRequest(),
        getSerialNumberRequest(),
        getVersionsRequest(),
        getBatteryDataRequest(),
        getStatisticsRequest(),
        getRealTimeDataRequest(),
      ];

  @override
  List<Uint8List> pollRequests() => <Uint8List>[
        getBatteryDataRequest(),
        getStatisticsRequest(),
        getRealTimeDataRequest(),
      ];

  @override
  Duration? get pollInterval => const Duration(milliseconds: 300);

  // ---------------------------------------------------------------------------
  // Construcción de peticiones (SOLO LECTURA: identidad y datos).

  /// Arma una trama de petición: `AA AA` + cuerpo con escapes +
  /// XOR. El cuerpo es `[flags][len = datos + 1][comando][datos]`
  /// y la suma se calcula sobre el cuerpo sin escapar (incluir
  /// la cabecera daría lo mismo: `AA ^ AA = 0`).
  static Uint8List buildMessage({
    required int flags,
    required int command,
    List<int> data = const <int>[],
  }) {
    final body = <int>[flags, data.length + 1, command, ...data];
    var check = 0;
    for (final b in body) {
      check ^= b & 0xFF;
    }
    final out = <int>[0xAA, 0xAA];
    for (final b in body) {
      if (b == 0xAA || b == 0xA5) out.add(0xA5);
      out.add(b & 0xFF);
    }
    out.add(check);
    return Uint8List.fromList(out);
  }

  /// Pide el tipo de vehículo (de ahí sale el modelo).
  static Uint8List getCarTypeRequest() => buildMessage(
      flags: _flagInitial, command: _cmdMainInfo, data: const [0x01]);

  /// Pide el número de serie.
  static Uint8List getSerialNumberRequest() => buildMessage(
      flags: _flagInitial, command: _cmdMainInfo, data: const [0x02]);

  /// Pide las versiones de firmware de las tres placas.
  static Uint8List getVersionsRequest() => buildMessage(
      flags: _flagInitial, command: _cmdMainInfo, data: const [0x06]);

  /// Pide los datos en vivo de los packs de batería.
  static Uint8List getBatteryDataRequest() =>
      buildMessage(flags: _flagDefault, command: _cmdBatteryRealTimeInfo);

  /// Pide las estadísticas totales (odómetro…).
  static Uint8List getStatisticsRequest() =>
      buildMessage(flags: _flagDefault, command: _cmdTotalStats);

  /// Pide una trama de telemetría en tiempo real.
  static Uint8List getRealTimeDataRequest() =>
      buildMessage(flags: _flagDefault, command: _cmdRealTimeInfo);

  // ---------------------------------------------------------------------------
  // Decodificación.

  @override
  bool decode(Uint8List data) {
    var liveData = false;
    for (final byte in data) {
      final frame = _unpacker.addByte(byte & 0xFF);
      if (frame != null && _handleFrame(frame)) {
        liveData = true;
      }
    }
    return liveData;
  }

  /// Procesa una trama completa (cabecera + cuerpo + suma).
  /// Devuelve true solo si era telemetría en vivo (RealTimeInfo).
  bool _handleFrame(Uint8List frame) {
    // Verificación: XOR de todo menos el último byte = último byte.
    var check = 0;
    for (var i = 0; i < frame.length - 1; i++) {
      check ^= frame[i];
    }
    if (frame.length < 5 || check != frame[frame.length - 1]) {
      return false;
    }
    final flags = frame[2];
    final len = frame[3];
    final command = frame[4] & 0x7F;
    // Los datos miden len - 1 y terminan donde termina el cuerpo
    // (la trama mide len + 5 con la suma; sin ella, len + 4).
    if (len < 1 || frame.length < len + 4) return false;
    final data = Uint8List.sublistView(frame, 5, len + 4);

    if (flags == _flagInitial) {
      if (command == _cmdMainInfo) _parseMainData(data, len);
      // El otro comando con estas flags es la primera etapa del
      // apagado en dos pasos: es un comando de control y en esta
      // fase no se envía ni se responde.
      return false;
    }
    if (flags != _flagDefault) return false;
    return switch (command) {
      _cmdSettings => false, // Reconocidos; no se interpretan aún.
      _cmdDiagnostic => false, // Sin datos de telemetría.
      _cmdBatteryRealTimeInfo => _parseBatteryRealTimeInfo(data),
      _cmdTotalStats => _parseTotalStats(data),
      _cmdRealTimeInfo => _parseRealTimeInfo(data),
      _ => false,
    };
  }

  /// Identidad: tipo de vehículo, serie y versiones.
  void _parseMainData(Uint8List d, int len) {
    if (d.isEmpty) return;
    if (d[0] == 0x01 && len >= 6) {
      // Tipo de vehículo: el modelo sale de serie * 10 + tipo.
      if (d.length < 7) return;
      _model = _InMotionModel.findById(d[2], d[3]);
      final name = _model.displayName;
      if (name != null) {
        updateIdentity(identity.copyWith(
          brand: WheelBrand.inmotionV2,
          model: name,
        ));
      }
    } else if (d[0] == 0x02 && len >= 17) {
      // Número de serie: 16 caracteres ASCII desde el byte 1.
      if (d.length < 17) return;
      final serial = String.fromCharCodes(d.sublist(1, 17));
      updateIdentity(identity.copyWith(
        brand: WheelBrand.inmotionV2,
        serial: serial,
      ));
    } else if (d[0] == 0x06 && len >= 24) {
      // Versiones: cada placa es «mayor.menor.parche» con el
      // parche como u16 LE y los otros dos como bytes sueltos.
      if (d.length < 24) return;
      String version(int majorOff, int minorOff, int patchOff) =>
          '${d[majorOff]}.${d[minorOff]}.${_u16(d, patchOff)}';
      final driver = version(5, 4, 2);
      final main = version(14, 13, 11);
      final ble = version(23, 22, 20);
      _protoVer = 0;
      if (_model == _InMotionModel.v11) {
        // Placa principal anterior a 1.4 → layout antiguo.
        _protoVer = (d[14] < 2 && d[13] < 4) ? 1 : 2;
      }
      updateIdentity(identity.copyWith(
        brand: WheelBrand.inmotionV2,
        firmware: 'Main:$main Drv:$driver BLE:$ble',
      ));
    }
  }

  /// Odómetro total: u32 LE al inicio, en decenas de metro.
  bool _parseTotalStats(Uint8List d) {
    if (d.length < 20) return false;
    final totalM = _u32le(d, 0) * 10;
    updateTelemetry(telemetry.copyWith(totalDistanceM: totalM));
    return false;
  }

  /// Datos por pack: voltaje/temperatura de cada pack y la
  /// carga. La referencia los calcula sin publicarlos en su
  /// snapshot; aquí quedan como getters del adaptador.
  bool _parseBatteryRealTimeInfo(Uint8List d) {
    if (d.length < 20) return false;
    _pack1VoltageV = _u16(d, 0) / 100.0;
    _pack1Temp = d[4];
    _pack2VoltageV = _u16(d, 8) / 100.0;
    _pack2Temp = d[12];
    _chargeVoltageV = _u16(d, 16) / 100.0;
    _chargeCurrentA = _u16(d, 18) / 100.0;
    return false;
  }

  /// Despacha la trama de tiempo real al layout de la familia.
  /// Sin modelo conocido se usa el layout clásico de la V11,
  /// como hace la referencia.
  bool _parseRealTimeInfo(Uint8List d) {
    return switch (_model) {
      _InMotionModel.v12hs ||
      _InMotionModel.v12ht ||
      _InMotionModel.v12pro =>
        _parseRealTimeV12(d),
      _InMotionModel.v13 || _InMotionModel.v13pro => _parseRealTimeV13(d),
      _InMotionModel.v14g ||
      _InMotionModel.v14s ||
      _InMotionModel.v11y ||
      _InMotionModel.v9 ||
      _InMotionModel.v12s =>
        _parseRealTimeNewFamily(d),
      _ => _protoVer < 2 ? _parseRealTimeV11(d) : _parseRealTimeV11Board14(d),
    };
  }

  /// Publica el snapshot: lo común de todas las familias, con el
  /// modelo ya identificado si se conoce.
  void _publish({
    required double speedKmh,
    required double voltageV,
    required double currentA,
    required double powerW,
    required int batteryPct,
    required double tempC,
    required double temp2C,
    required double pwmPct,
    required int distanceM,
  }) {
    var next = telemetry.copyWith(
      speedKmh: speedKmh,
      voltageV: voltageV,
      currentA: currentA,
      powerW: powerW,
      batteryPct: batteryPct,
      tempC: tempC,
      temp2C: temp2C,
      pwmPct: pwmPct,
      distanceM: distanceM,
    );
    final name = _model.displayName;
    if (name != null) next = next.copyWith(model: name);
    updateTelemetry(next);
  }

  /// Layout V11 con placa principal anterior a 1.4 (y el que se
  /// usa mientras no se conoce el modelo).
  bool _parseRealTimeV11(Uint8List d) {
    if (d.length < 40) return false;
    _torqueNm = _s16(d, 6) / 100.0;
    _motorPowerW = _s16(d, 10).toDouble();
    _remainMileageM = _u16(d, 14) * 10;
    _pitchDeg = _s16(d, 22) / 100.0;
    _rollDeg = _s16(d, 26) / 100.0;
    _dynamicSpeedLimitKmh = _u16(d, 28) / 100.0;
    _dynamicCurrentLimitA = _u16(d, 30) / 100.0;
    _motorTempC = _temp(d, 18);
    _batteryTempC = _temp(d, 19);
    _boardTempC = _temp(d, 20);
    _lampTempC = _temp(d, 21);
    _cpuTempC = _temp(d, 34);
    _imuTempC = _temp(d, 35);
    // Estado: en las tramas cortas solapa con el PWM (así lo lee
    // la referencia); en las largas va dos bytes más adelante.
    final i = d.length < 49 ? 36 : 38;
    _charging = ((d[i] >> 7) & 0x01) == 1;
    _lifted = ((d[i + 1] >> 2) & 0x01) == 1;
    _lightOn = (d[i + 1] & 0x01) == 1;
    _publish(
      speedKmh: _s16(d, 4) / 100.0,
      voltageV: _u16(d, 0) / 100.0,
      currentA: _s16(d, 2) / 100.0,
      powerW: _s16(d, 8).toDouble(),
      batteryPct: d[16] & 0x7F,
      tempC: _temp(d, 17).toDouble(),
      temp2C: _temp(d, 20).toDouble(),
      pwmPct: _u16(d, 36) / 100.0,
      distanceM: _u16(d, 12) * 10,
    );
    return true;
  }

  /// Layout V11 con placa principal 1.4 o posterior: cambian los
  /// offsets de casi todo (entra el PWM al principio y la
  /// batería pasa a ser un u16 en centésimas de porcentaje).
  bool _parseRealTimeV11Board14(Uint8List d) {
    if (d.length < 58) return false;
    _torqueNm = _s16(d, 6) / 100.0;
    _motorPowerW = _s16(d, 12).toDouble();
    _remainMileageM = _u16(d, 30) * 10;
    _pitchDeg = _s16(d, 16) / 100.0;
    _rollDeg = _s16(d, 20) / 100.0;
    _dynamicSpeedLimitKmh = _u16(d, 34) / 100.0;
    _dynamicCurrentLimitA = _u16(d, 36) / 100.0;
    _motorTempC = _temp(d, 43);
    _batteryTempC = _temp(d, 44);
    _boardTempC = _temp(d, 45);
    _cpuTempC = _temp(d, 46);
    _imuTempC = _temp(d, 47);
    _lampTempC = _temp(d, 48);
    _charging = ((d[56] >> 7) & 0x01) == 1;
    _lifted = ((d[57] >> 2) & 0x01) == 1;
    _lightOn = (d[57] & 0x01) == 1;
    _publish(
      speedKmh: _s16(d, 4) / 100.0,
      voltageV: _u16(d, 0) / 100.0,
      currentA: _s16(d, 2) / 100.0,
      powerW: _s16(d, 10).toDouble(),
      batteryPct: (_u16(d, 28) / 100.0).round(),
      tempC: _temp(d, 42).toDouble(),
      temp2C: _temp(d, 45).toDouble(),
      pwmPct: _s16(d, 8) / 100.0,
      distanceM: _u16(d, 26) * 10,
    );
    return true;
  }

  /// Layout V12 (HS, HT y Pro comparten layout).
  bool _parseRealTimeV12(Uint8List d) {
    if (d.length < 56) return false;
    _torqueNm = _s16(d, 6) / 100.0;
    _motorPowerW = _s16(d, 12).toDouble();
    _remainMileageM = _u16(d, 26) * 10;
    _pitchDeg = _s16(d, 16) / 100.0;
    _rollDeg = _s16(d, 20) / 100.0;
    _dynamicSpeedLimitKmh = _u16(d, 30) / 100.0;
    _dynamicCurrentLimitA = _u16(d, 32) / 100.0;
    _motorTempC = _temp(d, 41);
    _batteryTempC = _temp(d, 42);
    _boardTempC = _temp(d, 43);
    _cpuTempC = _temp(d, 44);
    _imuTempC = _temp(d, 45);
    _lampTempC = _temp(d, 46);
    _charging = ((d[54] >> 7) & 0x01) == 1;
    _lifted = ((d[55] >> 2) & 0x01) == 1;
    _lightOn = (d[55] & 0x01) == 1;
    _publish(
      speedKmh: _s16(d, 4) / 100.0,
      voltageV: _u16(d, 0) / 100.0,
      currentA: _s16(d, 2) / 100.0,
      powerW: _s16(d, 10).toDouble(),
      batteryPct: (_u16(d, 24) / 100.0).round(),
      tempC: _temp(d, 40).toDouble(),
      temp2C: _temp(d, 41).toDouble(),
      pwmPct: _s16(d, 8) / 100.0,
      distanceM: _u16(d, 22) * 10,
    );
    return true;
  }

  /// Layout V13: varios offsets difieren de la familia nueva
  /// (la velocidad va en el 8, el pitch en el 6, el par en el
  /// 18) y la distancia del viaje es un u32 en metros con las
  /// mitades de 16 bits intercambiadas. La batería es la media
  /// de los dos packs.
  bool _parseRealTimeV13(Uint8List d) {
    if (d.length < 77) return false;
    _torqueNm = _s16(d, 18) / 100.0;
    _motorPowerW = _s16(d, 22).toDouble();
    _remainMileageM = null;
    _pitchDeg = _s16(d, 6) / 100.0;
    _rollDeg = _s16(d, 24) / 100.0;
    _dynamicSpeedLimitKmh = _u16(d, 40) / 100.0;
    _dynamicCurrentLimitA = _u16(d, 50) / 100.0;
    _motorTempC = _temp(d, 59);
    _batteryTempC = _temp(d, 60);
    _boardTempC = _temp(d, 61);
    _cpuTempC = _temp(d, 62);
    _imuTempC = _temp(d, 63);
    _lampTempC = _temp(d, 64);
    _charging = ((d[74] >> 7) & 0x01) == 1;
    _lifted = ((d[75] >> 2) & 0x01) == 1;
    _lightOn = ((d[76] >> 1) & 0x01) == 1;
    _publish(
      speedKmh: _s16(d, 8) / 100.0,
      voltageV: _u16(d, 0) / 100.0,
      currentA: _s16(d, 2) / 100.0,
      powerW: _s16(d, 16).toDouble(),
      batteryPct: ((_u16(d, 34) + _u16(d, 36)) / 200.0).round(),
      tempC: _temp(d, 58).toDouble(),
      temp2C: _temp(d, 59).toDouble(),
      pwmPct: _s16(d, 14) / 100.0,
      distanceM: _u32revLe(d, 10),
    );
    return true;
  }

  /// Layout de la familia nueva: V14 (50GB y 50S), V11Y, V9 y
  /// V12S comparten offsets. La batería es la media de los dos
  /// packs y la distancia del viaje un u16 en decenas de metro.
  bool _parseRealTimeNewFamily(Uint8List d) {
    if (d.length < 77) return false;
    _torqueNm = _s16(d, 12) / 100.0;
    _motorPowerW = _s16(d, 18).toDouble();
    _remainMileageM = null;
    _pitchDeg = _s16(d, 20) / 100.0;
    _rollDeg = _s16(d, 22) / 100.0;
    _dynamicSpeedLimitKmh = _u16(d, 40) / 100.0;
    _dynamicCurrentLimitA = _u16(d, 50) / 100.0;
    _motorTempC = _temp(d, 59);
    _batteryTempC = _temp(d, 60);
    _boardTempC = _temp(d, 61);
    _cpuTempC = _temp(d, 62);
    _imuTempC = _temp(d, 63);
    _lampTempC = _temp(d, 64);
    _charging = ((d[74] >> 7) & 0x01) == 1;
    _lifted = ((d[75] >> 2) & 0x01) == 1;
    _lightOn = ((d[76] >> 1) & 0x01) == 1;
    _publish(
      speedKmh: _s16(d, 8) / 100.0,
      voltageV: _u16(d, 0) / 100.0,
      currentA: _s16(d, 2) / 100.0,
      powerW: _s16(d, 16).toDouble(),
      batteryPct: ((_u16(d, 34) + _u16(d, 36)) / 200.0).round(),
      tempC: _temp(d, 58).toDouble(),
      temp2C: _temp(d, 59).toDouble(),
      pwmPct: _s16(d, 14) / 100.0,
      distanceM: _u16(d, 28) * 10,
    );
    return true;
  }

  // ---------------------------------------------------------------------------
  // Lecturas little-endian con guarda de longitud (fuera de rango
  // devuelven 0, como las utilidades de la referencia).

  static int _u16(List<int> b, int off) {
    if (b.length < off + 2) return 0;
    return (b[off] & 0xFF) | ((b[off + 1] & 0xFF) << 8);
  }

  static int _s16(List<int> b, int off) {
    final v = _u16(b, off);
    return v >= 0x8000 ? v - 0x10000 : v;
  }

  static int _u32le(List<int> b, int off) {
    if (b.length < off + 4) return 0;
    return (b[off] & 0xFF) |
        ((b[off + 1] & 0xFF) << 8) |
        ((b[off + 2] & 0xFF) << 16) |
        ((b[off + 3] & 0xFF) << 24);
  }

  /// u32 con las mitades de 16 bits intercambiadas respecto a
  /// little-endian: así viaja la distancia del viaje en la V13.
  static int _u32revLe(List<int> b, int off) {
    if (b.length < off + 4) return 0;
    return ((b[off + 1] & 0xFF) << 24) |
        ((b[off] & 0xFF) << 16) |
        ((b[off + 3] & 0xFF) << 8) |
        (b[off + 2] & 0xFF);
  }

  /// Temperatura de un byte: viaja desplazada en 176.
  static int _temp(List<int> b, int off) {
    if (b.length < off + 1) return 0;
    return (b[off] & 0xFF) - 176;
  }

  // ---------------------------------------------------------------------------
  // Comandos de control (comando Control 0x60 salvo el apagado;
  // datos verificados byte a byte contra la referencia abierta del
  // protocolo V2). Ninguna trama sale de aquí directamente: pasan
  // por la compuerta de seguridad vía el controlador.

  static const int _cmdControl = 0x60;

  bool get _isV12Family =>
      _model == _InMotionModel.v12hs ||
      _model == _InMotionModel.v12ht ||
      _model == _InMotionModel.v12pro;

  bool get _isV14Family =>
      _model == _InMotionModel.v14g || _model == _InMotionModel.v14s;

  /// Entero ×100 en little-endian (así viajan las velocidades).
  static List<int> _le100(int v) {
    final x = (v * 100) & 0xFFFF;
    return [x & 0xFF, (x >> 8) & 0xFF];
  }

  Uint8List _control(List<int> data) => buildMessage(
        flags: _flagDefault,
        command: _cmdControl,
        data: data,
      );

  @override
  List<CommandStep>? buildCommand(WheelCommandRequest request) {
    switch (request) {
      case LightRequest(:final state):
        if (state == LightState.strobe) return null;
        final on = state == LightState.on ? 1 : 0;
        if (_isV12Family) {
          // Familia V12: [0x50, bajas, altas]; encender = bajas.
          return [CommandStep(_control([0x50, on, 0]))];
        }
        // V11 con placa antigua (protoVer < 2) usa el código 0x40.
        final code =
            (_model == _InMotionModel.v11 && _protoVer < 2) ? 0x40 : 0x50;
        return [CommandStep(_control([code, on]))];
      case BeepRequest():
        return [CommandStep(_control(const [0x51, 0x02, 0x64]))];
      case TiltBackRequest(:final kmh):
        final v = _le100(kmh.clamp(0, 200));
        if (_isV14Family) {
          // V14: la trama lleva también la velocidad de alarma (0 =
          // sin cambio de alarma conocido; así lo manda la referencia
          // cuando solo se ajusta la máxima).
          return [CommandStep(_control([0x21, v[0], v[1], 0, 0]))];
        }
        return [CommandStep(_control([0x21, v[0], v[1]]))];
      case SpeedAlarmsRequest(:final speedsKmh, :final tiltBackKmh):
        if (_isV12Family && speedsKmh.length == 2) {
          final a = _le100(speedsKmh[0]);
          final b = _le100(speedsKmh[1]);
          return [CommandStep(_control([0x3E, a[0], a[1], b[0], b[1]]))];
        }
        if (_isV14Family && speedsKmh.length == 1 && tiltBackKmh != null) {
          final v = _le100(tiltBackKmh);
          final a = _le100(speedsKmh[0]);
          return [CommandStep(_control([0x21, v[0], v[1], a[0], a[1]]))];
        }
        return null;
      case MotorLockRequest(:final lock):
        return [CommandStep(_control([0x31, lock ? 1 : 0]))];
      case TransportModeRequest(:final on):
        return [CommandStep(_control([0x32, on ? 1 : 0]))];
      case CalibrationRequest():
        return [CommandStep(_control(const [0x42, 0x01, 0x00, 0x01]))];
      case PowerOffRequest():
        // Apagado en dos etapas (comando Diagnóstico): la referencia
        // manda la segunda al recibir el diagnóstico de la rueda;
        // aquí va tras una espera prudente sobre el mismo canal.
        return [
          CommandStep(buildMessage(
            flags: _flagInitial,
            command: _cmdDiagnostic,
            data: const [0x81, 0x00],
          )),
          CommandStep(
            buildMessage(
              flags: _flagInitial,
              command: _cmdDiagnostic,
              data: const [0x82],
            ),
            delayBefore: const Duration(milliseconds: 600),
          ),
        ];
      default:
        return null;
    }
  }
}

/// Modelos del protocolo V2. El identificador es
/// `serie * 10 + tipo`, tal como llega en la trama de tipo de
/// vehículo; el nombre es el comercial.
enum _InMotionModel {
  v11(61, 'Inmotion V11'),
  v11y(62, 'Inmotion V11y'),
  v12hs(71, 'Inmotion V12 HS'),
  v12ht(72, 'Inmotion V12 HT'),
  v12pro(73, 'Inmotion V12 PRO'),
  v13(81, 'Inmotion V13'),
  v13pro(82, 'Inmotion V13 PRO'),
  v14g(91, 'Inmotion V14 50GB'),
  v14s(92, 'Inmotion V14 50S'),
  v12s(111, 'Inmotion V12S'),
  v9(121, 'Inmotion V9'),
  unknown(0, null);

  const _InMotionModel(this.id, this.displayName);

  final int id;

  /// Nombre comercial; null = no publicar como modelo.
  final String? displayName;

  static _InMotionModel findById(int series, int type) {
    final id = series * 10 + type;
    for (final m in values) {
      if (m.id == id) return m;
    }
    return unknown;
  }
}

enum _UnpackState { unknown, flagSearch, lenSearch, collecting, done }

/// Desempaquetador con estado de las tramas V2, réplica fiel del
/// de la referencia, con sus particularidades:
///
/// - El byte `A5` es escape: si el anterior no era también `A5`,
///   se traga sin escribirlo (el siguiente byte es el literal).
///   Un `A5` tras otro `A5` sí se escribe (es el literal).
/// - La cabecera se detectan dos `AA` seguidos en el flujo ya
///   sin escapes; después van flags, `len` y la recolección
///   hasta juntar `len + 5` bytes.
/// - Durante la recolección, `oldc` solo se actualiza al cerrar
///   la trama: así lo hace la referencia y así pasan sus
///   vectores reales con escapes; no «corregirlo».
class _InMotionUnpacker {
  List<int> _buffer = <int>[];
  int _oldc = 0;
  int _len = 0;
  _UnpackState _state = _UnpackState.unknown;

  /// Procesa un byte. Devuelve la trama completa (con suma) si
  /// este byte la cierra; null en cualquier otro caso.
  Uint8List? addByte(int c) {
    if (c != 0xA5 || _oldc == 0xA5) {
      switch (_state) {
        case _UnpackState.collecting:
          _buffer.add(c);
          if (_buffer.length == _len + 5) {
            _state = _UnpackState.done;
            _oldc = 0;
            return Uint8List.fromList(_buffer);
          }
        case _UnpackState.lenSearch:
          _buffer.add(c);
          _len = c & 0xFF;
          _state = _UnpackState.collecting;
          _oldc = c;
        case _UnpackState.flagSearch:
          _buffer.add(c);
          _state = _UnpackState.lenSearch;
          _oldc = c;
        case _UnpackState.unknown || _UnpackState.done:
          if (c == 0xAA && _oldc == 0xAA) {
            _buffer = <int>[0xAA, 0xAA];
            _state = _UnpackState.flagSearch;
          }
          _oldc = c;
      }
    } else {
      _oldc = c;
    }
    return null;
  }
}
