import 'dart:typed_data';

import '../../../models/wheel_capabilities.dart';
import '../../../models/wheel_identity.dart';
import '../wheel_command.dart';
import 'wheel_adapter.dart';

/// Adaptador Veteran (LeaperKim): telemetría y los pocos comandos
/// verificados de la marca (luz, pedales y beep).
///
/// Incluye los modelos vendidos bajo la línea NOSFET, que comparten
/// este mismo protocolo (se distinguen por la versión de modelo).
///
/// Transporte: flujo continuo sin polling sobre el transporte serie
/// compartido (`ffe0/ffe1`), el mismo que usan otras marcas; la
/// detección se hace por la primera trama (cabecera `DC 5A 5C`).
/// La rueda emite en continuo: no hay peticiones iniciales.
///
/// Trama de telemetría (payload big-endian): cabecera `DC 5A 5C`,
/// el cuarto byte es `len` y la longitud total es `len + 4`.
/// - Voltaje u16@4 en centivoltios; velocidad s16@6 (÷100 = km/h).
/// - Distancia del viaje u32@8 y total u32@12, en metros, con las
///   dos mitades de 16 bits intercambiadas respecto a big-endian.
/// - Corriente de fase s16@16 (÷10 = A); temperatura s16@18
///   (÷100 = °C); segundos de auto-apagado u16@20; modo de carga
///   u16@22; velocidad de alerta u16@24 y de tilt-back u16@26
///   (÷100 = km/h); versión u16@28; modo de pedales u16@30;
///   ángulo de pitch s16@32 (÷100 = °); PWM de salida u16@34
///   (÷100 = %).
/// - La corriente de batería no viene directa: se estima como
///   PWM × corriente de fase, y la potencia como V × A, igual que
///   en la implementación de referencia del protocolo.
/// - Tramas largas (`len > 38`) — o todas, una vez detectado el
///   formato nuevo —: los últimos 4 bytes son un CRC32 estándar
///   big-endian calculado sobre los primeros `len` bytes.
/// - Ruedas recientes (versión de modelo ≥ 5) intercalan paquetes
///   SmartBMS en las tramas largas, rotando en el byte 46.
///
/// El desempaquetador con estado replica las verificaciones de la
/// referencia (bytes que deben ser 0 en los offsets 22, 23 y 30):
/// con flujo BLE partido en trozos arbitrarios y basura entre
/// tramas, son las que permiten resincronizar sin aceptar tramas
/// falsas. Si pasan más de 100 ms entre notificaciones, la
/// referencia reinicia el desempaquetador (una trama a medias ya
/// no es recuperable); aquí el reloj es inyectable para pruebas.
///
/// El % de batería usa la curva estándar de cada familia de
/// voltaje (24, 30, 36 o 42 celdas según la versión de modelo).
///
/// Los comandos de control de Veteran NO se construyen aquí: el
/// protocolo de referencia sí define comandos de texto para la
/// luz, el modo de pedales, el reinicio del contador de viaje y
/// el pitido, pero quedan fuera de esta fase; cuando se
/// implementen, saldrán únicamente por la compuerta de seguridad
/// (safety_gate.dart). Apagar, bloquear el motor, tilt-back y
/// calibración no están verificados en el protocolo abierto:
/// no se ofrecen.
class VeteranAdapter extends BaseWheelAdapter {
  VeteranAdapter({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  /// Reloj para el reinicio del desempaquetador tras 100 ms sin
  /// notificaciones (inyectable en pruebas).
  final DateTime Function() _clock;

  final _VeteranUnpacker _unpacker = _VeteranUnpacker();
  DateTime? _lastDecodeAt;

  double _phaseCurrentA = 0;
  double _pitchDeg = 0;
  int _autoOffSeconds = 0;
  double _alertSpeedKmh = 0;
  double _tiltBackSpeedKmh = 0;
  int _pedalMode = 0;
  int _modelVersion = 0;

  // SmartBMS: dos bancos de hasta 42 celdas y 6 temperaturas.
  final List<double> _bms1Cells = List<double>.filled(42, 0);
  final List<double> _bms2Cells = List<double>.filled(42, 0);
  final List<double> _bms1Temps = List<double>.filled(6, 0);
  final List<double> _bms2Temps = List<double>.filled(6, 0);
  double _bms1CurrentA = 0;
  double _bms2CurrentA = 0;
  bool _hasBmsData = false;

  /// Corriente de fase de la última trama, en amperios (÷10).
  /// La corriente de batería del snapshot es la estimada
  /// (PWM × fase); esta es la de fase, directa del protocolo.
  double get phaseCurrentA => _phaseCurrentA;

  /// Ángulo de pitch de la última trama, en grados.
  double get pitchDeg => _pitchDeg;

  /// Segundos de auto-apagado configurados en la rueda.
  int get autoOffSeconds => _autoOffSeconds;

  /// Velocidad de alerta configurada en la rueda, en km/h.
  double get alertSpeedKmh => _alertSpeedKmh;

  /// Velocidad de tilt-back configurada en la rueda, en km/h.
  double get tiltBackSpeedKmh => _tiltBackSpeedKmh;

  /// Modo de pedales crudo reportado por la rueda.
  int get pedalMode => _pedalMode;

  /// Versión de modelo: el entero de la versión ÷ 1000
  /// (p. ej. 5 en una Lynx). Determina modelo, celdas y curva.
  int get modelVersion => _modelVersion;

  /// ¿Ya llegó algún paquete SmartBMS? (solo ruedas recientes).
  bool get hasBmsData => _hasBmsData;

  /// Corrientes reportadas por los paquetes SmartBMS, en A.
  double get bms1CurrentA => _bms1CurrentA;
  double get bms2CurrentA => _bms2CurrentA;

  /// Voltajes de celda del BMS 1 (V; 0 = celda aún no reportada).
  List<double> get bms1CellVoltages => List<double>.unmodifiable(_bms1Cells);

  /// Voltajes de celda del BMS 2 (V; 0 = celda aún no reportada).
  List<double> get bms2CellVoltages => List<double>.unmodifiable(_bms2Cells);

  /// Temperaturas del BMS 1 en °C (6 sensores).
  List<double> get bms1Temperatures => List<double>.unmodifiable(_bms1Temps);

  /// Temperaturas del BMS 2 en °C (6 sensores).
  List<double> get bms2Temperatures => List<double>.unmodifiable(_bms2Temps);

  /// Celdas con voltaje distinto de cero contadas en ambos BMS.
  int get detectedCells =>
      _bms1Cells.where((v) => v != 0).length +
      _bms2Cells.where((v) => v != 0).length;

  @override
  WheelBrand get brand => WheelBrand.veteran;

  @override
  WheelCapabilities get capabilities => const WheelCapabilities(
        telemetry: true,
        lights: true,
        beep: true,
        pedalMode: true,
      );

  @override
  List<Uint8List> initialRequests() => const <Uint8List>[];

  @override
  bool decode(Uint8List data) {
    final now = _clock();
    final last = _lastDecodeAt;
    if (last != null && now.difference(last).inMilliseconds > 100) {
      _unpacker.reset();
    }
    _lastDecodeAt = now;

    var liveData = false;
    for (final byte in data) {
      final frame = _unpacker.addByte(byte & 0xFF);
      if (frame != null) {
        _parseFrame(frame);
        liveData = true;
      }
    }
    return liveData;
  }

  /// Procesa una trama completa y válida (cabecera + `len` + 4).
  void _parseFrame(Uint8List f) {
    final voltageCv = _getU16BE(f, 4);
    final speedRaw = _getS16BE(f, 6);
    final tripM = _getU32RevBE(f, 8);
    final totalM = _getU32RevBE(f, 12);
    final phaseRaw = _getS16BE(f, 16);
    final tempRaw = _getS16BE(f, 18);
    final verRaw = _getU16BE(f, 28);
    final mVer = verRaw ~/ 1000;
    final pwmRaw = _getU16BE(f, 34);

    _phaseCurrentA = phaseRaw / 10.0;
    _pitchDeg = _getS16BE(f, 32) / 100.0;
    _autoOffSeconds = _getU16BE(f, 20);
    _alertSpeedKmh = _getU16BE(f, 24) / 100.0;
    _tiltBackSpeedKmh = _getU16BE(f, 26) / 100.0;
    _pedalMode = _getU16BE(f, 30);
    _modelVersion = mVer;
    final version = versionStringFor(verRaw);

    // Corriente de batería estimada (PWM × fase), con el redondeo
    // a centiamperios de la referencia; potencia = V × A.
    final currentA = ((pwmRaw / 10000.0) * (phaseRaw * 10)).round() / 100.0;
    final voltageV = voltageCv / 100.0;

    if (mVer >= 5 && f.length > 46) {
      _parseSmartBms(f);
    }

    final modelName = modelNameFor(mVer);
    updateTelemetry(telemetry.copyWith(
      speedKmh: speedRaw / 100.0,
      voltageV: voltageV,
      currentA: currentA,
      powerW: voltageV * currentA,
      batteryPct: batteryLevelFor(voltageCv, mVer),
      tempC: tempRaw / 100.0,
      pwmPct: pwmRaw / 100.0,
      distanceM: tripM,
      totalDistanceM: totalM,
      // «Unknown» no se publica como modelo: queda en null.
      model: modelName == 'Unknown' ? null : modelName,
    ));
    updateIdentity(identity.copyWith(
      brand: WheelBrand.veteran,
      model: modelName == 'Unknown' ? null : modelName,
      firmware: version,
    ));
  }

  /// Paquetes SmartBMS: el byte 46 rota 0–8; los paquetes 0–3
  /// alimentan el BMS 1 y los 4–7 el BMS 2 (el 8 no está
  /// definido en la referencia y se ignora).
  void _parseSmartBms(Uint8List f) {
    final pnum = f[46] & 0xFF;
    final cells = pnum < 4 ? _bms1Cells : _bms2Cells;
    final temps = pnum < 4 ? _bms1Temps : _bms2Temps;
    if (pnum == 0 || pnum == 4) {
      // Ojo: la referencia fija AMBAS corrientes sin importar el
      // paquete, y solo si la trama mide más de 72 bytes.
      if (f.length > 72) {
        _bms1CurrentA = _getS16BE(f, 69) / 100.0;
        _bms2CurrentA = _getS16BE(f, 71) / 100.0;
        _hasBmsData = true;
      }
    } else if (pnum == 1 || pnum == 5) {
      for (var i = 0; i < 15; i++) {
        cells[i] = _getS16BE(f, 53 + i * 2) / 1000.0;
      }
      _hasBmsData = true;
    } else if (pnum == 2 || pnum == 6) {
      for (var i = 0; i < 15; i++) {
        cells[15 + i] = _getU16BE(f, 53 + i * 2) / 1000.0;
      }
      _hasBmsData = true;
    } else if (pnum == 3 || pnum == 7) {
      for (var i = 0; i < 12; i++) {
        final off = 59 + i * 2;
        if (off < f.length) {
          cells[30 + i] = _getU16BE(f, off) / 1000.0;
        }
      }
      for (var i = 0; i < 6; i++) {
        temps[i] = _getS16BE(f, 47 + i * 2) / 100.0;
      }
      _hasBmsData = true;
    }
  }

  /// Nombre comercial según la versión de modelo.
  static String modelNameFor(int mVer) {
    if (mVer <= 1) return 'Sherman';
    return switch (mVer) {
      2 => 'Abrams',
      3 => 'Sherman S',
      4 => 'Patton',
      5 => 'Lynx',
      6 => 'Sherman L',
      7 => 'Patton S',
      8 => 'Oryx',
      9 => 'Lynx S',
      42 => 'Nosfet Apex',
      43 => 'Nosfet Aero',
      44 => 'Nosfet Aeon',
      _ => 'Unknown',
    };
  }

  /// Cadena de versión con el formato de la referencia:
  /// 1051 → «001.0.51», 5004 → «005.0.04».
  static String versionStringFor(int verRaw) {
    final major = (verRaw ~/ 1000).toString().padLeft(3, '0');
    final mid = ((verRaw % 1000) ~/ 100).toString();
    final minor = (verRaw % 100).toString().padLeft(2, '0');
    return '$major.$mid.$minor';
  }

  /// Celdas en serie del pack según la versión de modelo.
  static int cellsForModelVersion(int mVer) {
    if (mVer == 4 || mVer == 7 || mVer == 43) return 30;
    if (mVer == 8) return 42;
    if (mVer >= 5) return 36;
    return 24;
  }

  /// Porcentaje de batería por la curva estándar de cada familia
  /// de voltaje. [voltageCv] en centivoltios. Las versiones de
  /// modelo sin curva conocida devuelven 1, como la referencia.
  static int batteryLevelFor(int voltageCv, int mVer) {
    int curve(int minCv, int maxCv, double step) {
      if (voltageCv <= minCv) return 0;
      if (voltageCv >= maxCv) return 100;
      return ((voltageCv - minCv) / step).round();
    }

    if (mVer < 4) return curve(7935, 9870, 19.5);
    if (mVer == 4 || mVer == 7 || mVer == 43) {
      return curve(9918, 12337, 24.2);
    }
    if (mVer == 5 || mVer == 6 || mVer == 9 || mVer == 42 || mVer == 44) {
      return curve(11902, 14805, 29.03);
    }
    if (mVer == 8) return curve(13886, 17272, 34.125);
    return 1;
  }

  /// CRC32 estándar (IEEE 802.3) de `data[start..end]`, inclusive.
  /// Es el mismo algoritmo de las tramas largas del protocolo.
  static int crc32(List<int> data, int start, int end) {
    var crc = 0xFFFFFFFF;
    for (var i = start; i <= end; i++) {
      crc = _crcTable[(crc ^ data[i]) & 0xFF] ^ (crc >> 8);
    }
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }

  static final List<int> _crcTable = _buildCrcTable();

  static List<int> _buildCrcTable() {
    final table = List<int>.filled(256, 0);
    for (var n = 0; n < 256; n++) {
      var c = n;
      for (var k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1);
      }
      table[n] = c & 0xFFFFFFFF;
    }
    return table;
  }

  // Lecturas big-endian con guarda de longitud (fuera de rango
  // devuelven 0, como las utilidades de la referencia).

  static int _getU16BE(List<int> b, int off) {
    if (b.length < off + 2) return 0;
    return ((b[off] & 0xFF) << 8) | (b[off + 1] & 0xFF);
  }

  static int _getS16BE(List<int> b, int off) {
    final v = _getU16BE(b, off);
    return v >= 0x8000 ? v - 0x10000 : v;
  }

  static int _getU32BE(List<int> b, int off) {
    if (b.length < off + 4) return 0;
    return ((b[off] & 0xFF) << 24) |
        ((b[off + 1] & 0xFF) << 16) |
        ((b[off + 2] & 0xFF) << 8) |
        (b[off + 3] & 0xFF);
  }

  /// u32 con las mitades de 16 bits intercambiadas: así viajan
  /// las distancias en este protocolo.
  static int _getU32RevBE(List<int> b, int off) {
    if (b.length < off + 4) return 0;
    return ((b[off + 2] & 0xFF) << 24) |
        ((b[off + 3] & 0xFF) << 16) |
        ((b[off] & 0xFF) << 8) |
        (b[off + 1] & 0xFF);
  }

  // ---------------------------------------------------------------------------
  // Comandos de control: palabras ASCII completas, escritas tal cual
  // (verificado en la referencia). Tilt-back, alarmas, bloqueo,
  // calibración y apagado NO están implementados en la referencia
  // abierta para Veteran: no se ofrecen hasta verificarlos.

  @override
  List<CommandStep>? buildCommand(WheelCommandRequest request) {
    switch (request) {
      case LightRequest(:final state):
        return switch (state) {
          LightState.on => [CommandStep('SetLightON'.codeUnits)],
          LightState.off => [CommandStep('SetLightOFF'.codeUnits)],
          LightState.strobe => null,
        };
      case PedalModeRequest(:final mode):
        if (mode < 0 || mode > 2) return null;
        return [
          CommandStep(const ['SETh', 'SETm', 'SETs'][mode].codeUnits)
        ];
      case BeepRequest():
        if (_modelVersion >= 3) {
          // Modelos recientes (versión de modelo ≥ 3): trama binaria
          // fija de 14 bytes de la referencia.
          return [
            CommandStep(const [
              0x4C, 0x6B, 0x41, 0x70, 0x0E, 0x00, 0x80, //
              0x80, 0x80, 0x01, 0xCA, 0x87, 0xE6, 0x6F,
            ])
          ];
        }
        return [CommandStep('b'.codeUnits)];
      default:
        return null;
    }
  }
}

enum _UnpackState { unknown, lengthSearch, collecting }

/// Desempaquetador con estado de las tramas Veteran.
///
/// Busca la cabecera `DC 5A 5C`, lee `len` y recolecta hasta
/// completar `len + 4` bytes. Durante la recolección verifica los
/// bytes de los offsets 22, 23 y 30 (deben ser 0, salvo el 30 que
/// también admite 0x07): si alguno no cuadra, la «trama» era
/// basura y se abandona sin consumir el byte que falló.
class _VeteranUnpacker {
  final List<int> _buffer = <int>[];
  _UnpackState _state = _UnpackState.unknown;
  int _old1 = 0;
  int _old2 = 0;
  int _len = 0;

  /// Una vez que una trama larga valida su CRC, el formato nuevo
  /// queda activo y TODAS las tramas siguientes deben validarlo.
  bool usingCrc = false;

  /// Reinicia la búsqueda de cabecera. El búfer no se limpia
  /// (se recrea al encontrar la siguiente cabecera), como en la
  /// referencia; el latch de CRC tampoco se toca.
  void reset() {
    _old1 = 0;
    _old2 = 0;
    _state = _UnpackState.unknown;
  }

  /// Procesa un byte. Devuelve la trama completa si este byte la
  /// cierra y es válida; null en cualquier otro caso.
  Uint8List? addByte(int c) {
    switch (_state) {
      case _UnpackState.collecting:
        return _collectByte(c);
      case _UnpackState.lengthSearch:
        _buffer.add(c);
        _len = c & 0xFF;
        _state = _UnpackState.collecting;
        _old2 = _old1;
        _old1 = c;
        return null;
      case _UnpackState.unknown:
        if (c == 0x5C && _old1 == 0x5A && _old2 == 0xDC) {
          _buffer
            ..clear()
            ..addAll(const <int>[0xDC, 0x5A, 0x5C]);
          _state = _UnpackState.lengthSearch;
        } else if (c == 0x5A && _old1 == 0xDC) {
          _old2 = _old1;
        } else {
          _old2 = 0;
        }
        _old1 = c;
        return null;
    }
  }

  Uint8List? _collectByte(int c) {
    final bsize = _buffer.length;
    if ((bsize == 22 && c != 0x00) ||
        (bsize == 30 && !(c == 0x00 || c == 0x07)) ||
        (bsize == 23 && (c & 0xFE) != 0x00)) {
      // Verificación fallida: no era una trama; el byte no se
      // escribe y se vuelve a buscar cabecera.
      reset();
      return null;
    }
    _buffer.add(c);
    if (bsize == _len + 3) {
      // Trama completa: el búfer mide len + 4.
      final frame = Uint8List.fromList(_buffer);
      if (_len > 38 || usingCrc) {
        final provided = VeteranAdapter._getU32BE(frame, _len);
        final computed = VeteranAdapter.crc32(frame, 0, _len - 1);
        reset();
        if (provided == computed) {
          usingCrc = true;
          return frame;
        }
        return null;
      }
      reset();
      return frame;
    }
    return null;
  }
}
