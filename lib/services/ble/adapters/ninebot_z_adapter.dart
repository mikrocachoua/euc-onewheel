import 'dart:typed_data';

import '../../../models/wheel_capabilities.dart';
import '../../../models/wheel_identity.dart';
import '../../../models/wheel_telemetry.dart';
import 'wheel_adapter.dart';

/// Adaptador Ninebot, variante **Z** — **solo telemetría** en
/// esta fase.
///
/// Transporte: Nordic UART (servicio `6e400001`, RX `…0002`,
/// TX `…0003`); la detección llega por la huella GATT de ese
/// transporte y el olfateo de la primera trama (`5A A5`).
///
/// Tramas: cabecera `5A A5` y un cuerpo
/// `[len][origen][destino][comando][parámetro][datos…][crc]`,
/// donde `len` es el número de bytes de datos, así que la trama
/// completa mide `len + 9`. El último par de bytes es una suma de
/// comprobación: la suma de todo el cuerpo anterior, invertida
/// (`^ 0xFFFF`) y guardada little-endian.
///
/// **Cifrado:** el cuerpo viaja con XOR contra una clave
/// («gamma») de 16 bytes: el byte 0 (el `len`) va en claro y cada
/// byte `j ≥ 1` se combina con `gamma[(j − 1) % 16]`. La gamma
/// arranca en ceros y la rueda la entrega al inicio de la
/// conexión como respuesta a la petición de clave (comando
/// `0x5B` desde el generador de claves, dirección `0x16`); a
/// partir de ahí peticiones y respuestas usan esa gamma.
///
/// Como la rueda solo responde cuando se le pregunta, el
/// adaptador declara [pollRequests] y [pollInterval]: una
/// secuencia de peticiones **de solo lectura** que avanza con las
/// respuestas — clave, número de serie, firmware, tres bloques
/// de parámetros, serie/estado/celdas de cada BMS — y al final
/// pide los datos en vivo (`LiveData`) en cada ronda, refrescando
/// el estado de los BMS de cuando en cuando.
///
/// Mensajes que se interpretan (todos verificados contra tramas
/// reales de una Z10 capturadas en las pruebas del protocolo):
/// - **Serie** (controlador, parámetro `0x10`): 14 caracteres
///   ASCII; el modelo se reporta simplemente como «Ninebot Z»
///   (la trama no distingue Z6/Z8/Z10).
/// - **Firmware** (controlador, `0x1A`): versión «x.y.z» en
///   hexadecimal por nibbles y dos códigos de error y dos de
///   aviso, con su tabla de textos.
/// - **LiveData** (controlador, `0xB0`): la telemetría en vivo.
///   Velocidad y velocidad media en centésimas de km/h, voltaje
///   y corriente (con signo) en centésimas, temperatura en
///   décimas de °C, batería en % directo (sin curva), odómetro
///   i32 en metros y distancia del viaje u16 ×10 m. La potencia
///   se calcula V × A. El PWM no viaja en la trama (la referencia
///   lo derivaba de límites configurados en la app), así que
///   queda en null, sin inventar.
/// - **BMS 1 y BMS 2** (`0x11`/`0x12`): serie y fabricación
///   (`0x10`), estado (`0x30`: carga restante, voltaje, corriente,
///   dos temperaturas con desplazamiento −20, salud) y voltajes
///   de las 16 celdas (`0x40`, en milivoltios). El modelo
///   compartido no tiene sitio para tanto detalle: se expone en
///   [bms1] y [bms2].
/// - **Parámetros 1/2/3** (controlador, anclas `0x70`/`0xC6`/
///   `0xF5`): los ajustes que la rueda reporta (bloqueo, modo
///   limitado y sus velocidades, alarmas, LED, banderas de
///   conducción, volumen) se exponen como getters de solo
///   lectura, igual que otros adaptadores exponen lo que sus
///   tramas de ajustes reportan.
///
/// **Discrepancia anotada:** la implementación de referencia
/// reconoce la respuesta de clave por `parámetro == 0x00`, pero
/// su propia captura real de una Z10 trae `parámetro == 0x01`
/// en esa trama (con origen y comando correctos y CRC válido):
/// con el despacho literal, la clave nunca se instalaría. Aquí
/// la clave se reconoce por **origen `0x16` + comando `0x5B`**
/// con al menos 16 bytes de datos, que es lo que la captura
/// real verifica.
///
/// La variante **clásica** de Ninebot (transporte serie
/// `ffe0`/`ffe1`, tramas `55 AA`) queda **fuera**: no existen
/// vectores de tramas reales suyos con los que verificar un
/// parseo, así que sigue solo detectada, con el aviso honesto
/// de la interfaz. Los comandos de control de la variante Z
/// (bloqueo, modo limitado, alarmas, LED, calibración…) sí
/// están verificados byte a byte en la referencia, pero quedan
/// fuera de esta fase de telemetría; cuando se implementen,
/// saldrán únicamente por la compuerta de seguridad
/// (safety_gate.dart).
class NinebotZAdapter extends BaseWheelAdapter {
  // Direcciones del bus CAN sobre BLE.
  static const int _addrApp = 0x3E;
  static const int _addrController = 0x14;
  static const int _addrBms1 = 0x11;
  static const int _addrBms2 = 0x12;
  static const int _addrKeyGenerator = 0x16;

  // Comandos.
  static const int _cmdRead = 0x01;
  static const int _cmdGetKey = 0x5B;

  // Parámetros del controlador.
  static const int _paramSerialNumber = 0x10;
  static const int _paramFirmware = 0x1A;
  static const int _paramBleVersion = 0x68;
  static const int _paramParams1 = 0x70; // ancla: modo de bloqueo
  static const int _paramParams2 = 0xC6; // ancla: modo LED
  static const int _paramParams3 = 0xF5; // ancla: volumen
  static const int _paramLiveData = 0xB0;

  // Parámetros de los BMS.
  static const int _paramBmsSn = 0x10;
  static const int _paramBmsLife = 0x30;
  static const int _paramBmsCells = 0x40;

  /// Modelo que se reporta: la trama de serie no distingue
  /// entre Z6, Z8 y Z10.
  static const String modelName = 'Ninebot Z';

  final _NinebotZUnpacker _unpacker = _NinebotZUnpacker();

  /// Clave de cifrado vigente: 16 bytes, en ceros hasta que la
  /// rueda responde a la petición de clave.
  List<int> _gamma = List<int>.filled(16, 0);
  bool _keyNegotiated = false;

  // Paso de la secuencia de sondeo: -1 = esperando la clave,
  // 0..10 = identidad/parámetros/BMS, 11 = datos en vivo.
  int _pollStep = -1;
  int _stepSends = 0;
  int _livePolls = 0;

  // Datos extra que el modelo compartido no tiene.
  int? _errorCode;
  int? _alarmCode;
  int? _escStatus;
  double? _avgSpeedKmh;
  int? _operatingTimeSec;
  int? _firmwareError1;
  int? _firmwareError2;
  int? _firmwareWarn1;
  int? _firmwareWarn2;

  // Ajustes reportados por la rueda (solo lectura).
  int? _lockMode;
  int? _limitedMode;
  double? _limitModeSpeed1Kmh;
  double? _limitModeSpeedKmh;
  int? _alarmsMask;
  double? _alarm1SpeedKmh;
  double? _alarm2SpeedKmh;
  double? _alarm3SpeedKmh;
  int? _ledMode;
  int? _ledColor1;
  int? _ledColor2;
  int? _ledColor3;
  int? _ledColor4;
  int? _pedalSensitivity;
  int? _driveFlags;
  int? _speakerVolume;

  final _BmsState _bmsState1 = _BmsState();
  final _BmsState _bmsState2 = _BmsState();

  @override
  WheelBrand get brand => WheelBrand.ninebotZ;

  @override
  WheelCapabilities get capabilities => WheelCapabilities.telemetryOnly;

  /// ¿La rueda ya entregó su clave de cifrado?
  bool get keyNegotiated => _keyNegotiated;

  /// Código de error del controlador (trama en vivo), si llegó.
  int? get errorCode => _errorCode;

  /// Código de alarma del controlador (trama en vivo), si llegó.
  int? get alarmCode => _alarmCode;

  /// Palabra de estado del controlador (trama en vivo), si llegó.
  int? get escStatus => _escStatus;

  /// Velocidad media del viaje en km/h, si llegó.
  double? get avgSpeedKmh => _avgSpeedKmh;

  /// Tiempo de funcionamiento en segundos, si llegó.
  int? get operatingTimeSec => _operatingTimeSec;

  /// Primer código de error del firmware (trama de versión).
  int? get firmwareErrorCode => _firmwareError1;

  /// Segundo código de error del firmware (trama de versión).
  int? get firmwareError2Code => _firmwareError2;

  /// Códigos de aviso del firmware (trama de versión).
  List<int?> get firmwareWarnCodes => <int?>[_firmwareWarn1, _firmwareWarn2];

  /// Texto del error principal del firmware, si lo hay.
  String? get firmwareErrorText {
    final code = _firmwareError1;
    if (code == null || code == 0) return null;
    var text = errorTextFor(code);
    final second = _firmwareError2;
    if (second != null && second != 0) {
      text = '$text\n${errorTextFor(second)}';
    }
    return text;
  }

  /// ¿La rueda reporta el modo de bloqueo activado?
  bool? get lockModeEnabled => _lockMode == null ? null : _lockMode == 1;

  /// ¿La rueda reporta el modo limitado activado?
  bool? get limitedModeEnabled =>
      _limitedMode == null ? null : _limitedMode == 1;

  /// Velocidad límite 1 del modo limitado en km/h, si llegó.
  double? get limitModeSpeed1Kmh => _limitModeSpeed1Kmh;

  /// Velocidad límite del modo limitado en km/h, si llegó.
  double? get limitModeSpeedKmh => _limitModeSpeedKmh;

  /// Máscara de alarmas activas reportada por la rueda.
  int? get alarmsMask => _alarmsMask;

  /// Velocidades de las alarmas 1–3 reportadas, en km/h.
  List<double?> get alarmSpeedsKmh =>
      <double?>[_alarm1SpeedKmh, _alarm2SpeedKmh, _alarm3SpeedKmh];

  /// Modo LED reportado por la rueda, si llegó.
  int? get ledMode => _ledMode;

  /// Colores LED 1–4 reportados (componente leída del protocolo).
  List<int?> get ledColors =>
      <int?>[_ledColor1, _ledColor2, _ledColor3, _ledColor4];

  /// Sensibilidad de pedales reportada, si llegó.
  int? get pedalSensitivity => _pedalSensitivity;

  /// Banderas de conducción reportadas (luces, DRL, asistente de
  /// freno…), en crudo, si llegaron.
  int? get driveFlags => _driveFlags;

  /// Volumen del altavoz reportado, si llegó.
  int? get speakerVolume => _speakerVolume;

  /// Últimos datos conocidos del BMS 1 (null si aún no llegó
  /// ninguna trama suya).
  NinebotBmsData? get bms1 => _bmsState1.snapshot();

  /// Últimos datos conocidos del BMS 2 (null si aún no llegó
  /// ninguna trama suya).
  NinebotBmsData? get bms2 => _bmsState2.snapshot();

  /// Tabla de textos de error del protocolo (códigos de la trama
  /// de versión de firmware).
  static String errorTextFor(int code) {
    switch (code) {
      case 0:
        return 'Sin error';
      case 1:
        return 'Error del sensor de corriente';
      case 2:
        return 'Sobrecorriente de software';
      case 3:
        return 'Sobrecorriente de hardware';
      case 4:
        return 'Error del sensor Hall';
      case 5:
        return 'Bloquear la rueda';
      case 6:
        return 'El acelerador no vuelve a cero al arrancar';
      case 7:
        return 'Error del acelerador';
      case 8:
        return 'Puerto serie anormal';
      case 9:
        return 'Fallo del sensor Hall del motor';
      case 10:
        return 'Temperatura alta del MOSFET';
      case 11:
        return 'Error de la placa base';
      case 12:
        return 'Temperatura alta';
      case 13:
        return 'El voltaje de la batería no es válido al arrancar';
      case 14:
        return 'Voltaje de la batería bajo al arrancar';
      case 15:
        return 'Voltaje de la batería alto al arrancar';
      case 16:
        return 'Error del potenciómetro';
      case 17:
        return 'Error del sensor de temperatura ambiente';
      case 18:
        return 'Error del sensor de temperatura del MOSFET';
      case 19:
        return 'Error del sensor de temperatura del motor';
      case 20:
        return 'Temperatura del motor demasiado alta';
      case 21:
        return 'La corriente regenerativa es demasiado alta';
      case 22:
        return 'Fallo de comunicación de datos serie';
      case 23:
        return 'Rueda bloqueada en el arranque del motor';
      case 24:
        return 'Voltaje general > 65 V o < 40 V';
      case 25:
        return 'VGM - Voltaje < 10 V';
      case 26:
        return 'Error de ADC';
      case 27:
        return 'La muestra de voltaje VCC no es 5 V';
      case 28:
        return 'Caída del codificador Hall';
      default:
        return 'Error desconocido';
    }
  }

  @override
  List<Uint8List> initialRequests() => <Uint8List>[
        bleVersionRequest(),
        getKeyRequest(),
      ];

  @override
  List<Uint8List> pollRequests() {
    // Tras demasiados envíos sin respuesta, se avanza igual:
    // una rueda sin segundo BMS no debe atascar la secuencia.
    if (_pollStep >= -1 && _pollStep < 11 && _stepSends >= 10) {
      _pollStep++;
      _stepSends = 0;
    }
    _stepSends++;
    switch (_pollStep) {
      case -1:
        return <Uint8List>[getKeyRequest()];
      case 0:
        return <Uint8List>[serialNumberRequest()];
      case 1:
        return <Uint8List>[firmwareRequest()];
      case 2:
        return <Uint8List>[params1Request()];
      case 3:
        return <Uint8List>[params2Request()];
      case 4:
        return <Uint8List>[params3Request()];
      case 5:
        return <Uint8List>[bmsSerialRequest(1)];
      case 6:
        return <Uint8List>[bmsLifeRequest(1)];
      case 7:
        return <Uint8List>[bmsCellsRequest(1)];
      case 8:
        return <Uint8List>[bmsSerialRequest(2)];
      case 9:
        return <Uint8List>[bmsLifeRequest(2)];
      case 10:
        return <Uint8List>[bmsCellsRequest(2)];
      default:
        // En vivo: datos en vivo en cada ronda y, cada 24, el
        // estado de un BMS (alternando) para mantenerlo fresco.
        _livePolls++;
        if (_livePolls % 24 == 0) {
          final pack = (_livePolls ~/ 24).isOdd ? 1 : 2;
          return <Uint8List>[bmsLifeRequest(pack)];
        }
        return <Uint8List>[liveDataRequest()];
    }
  }

  @override
  Duration? get pollInterval => const Duration(milliseconds: 150);

  // ---------------------------------------------------------------------------
  // Construcción de peticiones (SOLO LECTURA: identidad y datos).

  /// Arma una trama de petición: cuerpo
  /// `[len][app][destino][comando][parámetro][datos…]` + suma
  /// invertida little-endian, cifrado con la gamma vigente y
  /// prefijo `5A A5`.
  Uint8List _buildMessage({
    required int destination,
    required int command,
    required int parameter,
    List<int> data = const <int>[],
  }) {
    final body = <int>[
      data.length,
      _addrApp,
      destination,
      command,
      parameter,
      ...data,
    ];
    var sum = 0;
    for (final b in body) {
      sum += b & 0xFF;
    }
    final check = (sum ^ 0xFFFF) & 0xFFFF;
    body.add(check & 0xFF);
    body.add((check >> 8) & 0xFF);
    final out = <int>[0x5A, 0xA5, body[0]];
    for (var j = 1; j < body.length; j++) {
      out.add((body[j] ^ _gamma[(j - 1) % 16]) & 0xFF);
    }
    return Uint8List.fromList(out);
  }

  /// Petición de lectura genérica al controlador o a un BMS.
  Uint8List _read(int destination, int parameter, int dataLength) =>
      _buildMessage(
        destination: destination,
        command: _cmdRead,
        parameter: parameter,
        data: <int>[dataLength],
      );

  /// Versión del módulo BLE (primer saludo de la secuencia).
  Uint8List bleVersionRequest() =>
      _read(_addrController, _paramBleVersion, 0x02);

  /// Pide la clave de cifrado al generador de claves.
  Uint8List getKeyRequest() => _buildMessage(
        destination: _addrKeyGenerator,
        command: _cmdGetKey,
        parameter: 0x00,
      );

  /// Pide el número de serie al controlador.
  Uint8List serialNumberRequest() =>
      _read(_addrController, _paramSerialNumber, 0x0E);

  /// Pide la versión de firmware y sus códigos de error.
  Uint8List firmwareRequest() => _read(_addrController, _paramFirmware, 0x06);

  /// Pide el primer bloque de parámetros (bloqueo y alarmas).
  Uint8List params1Request() => _read(_addrController, _paramParams1, 0x20);

  /// Pide el segundo bloque de parámetros (LED y conducción).
  Uint8List params2Request() => _read(_addrController, _paramParams2, 0x1C);

  /// Pide el tercer bloque de parámetros (volumen).
  Uint8List params3Request() => _read(_addrController, _paramParams3, 0x02);

  /// Pide los datos en vivo (la telemetría).
  Uint8List liveDataRequest() => _read(_addrController, _paramLiveData, 0x20);

  /// Pide la serie y fabricación del BMS [pack] (1 o 2).
  Uint8List bmsSerialRequest(int pack) =>
      _read(pack == 1 ? _addrBms1 : _addrBms2, _paramBmsSn, 0x22);

  /// Pide el estado del BMS [pack] (1 o 2).
  Uint8List bmsLifeRequest(int pack) =>
      _read(pack == 1 ? _addrBms1 : _addrBms2, _paramBmsLife, 0x18);

  /// Pide los voltajes de celda del BMS [pack] (1 o 2).
  Uint8List bmsCellsRequest(int pack) =>
      _read(pack == 1 ? _addrBms1 : _addrBms2, _paramBmsCells, 0x20);

  // ---------------------------------------------------------------------------
  // Decodificación.

  @override
  bool decode(Uint8List frame) {
    var live = false;
    for (final byte in frame) {
      final complete = _unpacker.add(byte);
      if (complete == null) continue;
      if (_handleFrame(complete)) live = true;
    }
    return live;
  }

  /// Verifica (suma) y descifra una trama completa y la despacha.
  /// Devuelve `true` solo si era la trama de datos en vivo.
  bool _handleFrame(Uint8List frame) {
    if (frame.length < 9) return false;
    final body = _decrypt(frame.sublist(2));
    // La suma se comprueba sobre el cuerpo ya descifrado.
    var sum = 0;
    for (var i = 0; i < body.length - 2; i++) {
      sum += body[i];
    }
    final expected = (sum ^ 0xFFFF) & 0xFFFF;
    final actual =
        ((body[body.length - 1] & 0xFF) << 8) | (body[body.length - 2] & 0xFF);
    if (expected != actual) return false;

    final source = body[1];
    final command = body[3];
    final parameter = body[4];
    final data = Uint8List.sublistView(body, 5, body.length - 2);

    // La clave se reconoce por origen y comando (ver la nota de
    // discrepancia en la cabecera de la clase): la captura real
    // trae parámetro 0x01, no el 0x00 del despacho de referencia.
    if (source == _addrKeyGenerator && command == _cmdGetKey) {
      if (data.length >= 16) {
        _gamma = List<int>.from(data.sublist(0, 16));
        _keyNegotiated = true;
        _advanceFrom(-1, 0);
      }
      return false;
    }

    if (source == _addrController) {
      switch (parameter) {
        case _paramBleVersion:
          return false;
        case _paramSerialNumber:
          _parseSerialNumber(data);
          _advanceFrom(0, 1);
          return false;
        case _paramFirmware:
          _parseFirmware(data);
          _advanceFrom(1, 2);
          return false;
        case _paramParams1:
          _parseParams1(data);
          _advanceFrom(2, 3);
          return false;
        case _paramParams2:
          _parseParams2(data);
          _advanceFrom(3, 4);
          return false;
        case _paramParams3:
          _parseParams3(data);
          _advanceFrom(4, 5);
          return false;
        case _paramLiveData:
          return _parseLiveData(data);
      }
      return false;
    }

    if (source == _addrBms1 || source == _addrBms2) {
      final pack = source == _addrBms1 ? 1 : 2;
      final state = pack == 1 ? _bmsState1 : _bmsState2;
      final base = pack == 1 ? 5 : 8;
      switch (parameter) {
        case _paramBmsSn:
          _parseBmsSn(state, data);
          _advanceFrom(base, base + 1);
          return false;
        case _paramBmsLife:
          _parseBmsLife(state, data);
          _advanceFrom(base + 1, base + 2);
          return false;
        case _paramBmsCells:
          _parseBmsCells(state, data);
          _advanceFrom(base + 2, base + 3);
          return false;
      }
    }
    return false;
  }

  /// Aplica el cifrado XOR con la gamma vigente a un cuerpo:
  /// el byte 0 va en claro; el byte `j ≥ 1` usa
  /// `gamma[(j − 1) % 16]`. Cifrar y descifrar es lo mismo.
  Uint8List _decrypt(Uint8List body) {
    final out = Uint8List.fromList(body);
    for (var j = 1; j < out.length; j++) {
      out[j] = (out[j] ^ _gamma[(j - 1) % 16]) & 0xFF;
    }
    return out;
  }

  /// Avanza la secuencia de sondeo si está en el paso [from].
  void _advanceFrom(int from, int to) {
    if (_pollStep == from) {
      _pollStep = to;
      _stepSends = 0;
    }
  }

  void _parseSerialNumber(Uint8List d) {
    if (d.isEmpty) return;
    final serial = String.fromCharCodes(d).replaceAll('\u0000', '').trim();
    updateIdentity(identity.copyWith(
      brand: WheelBrand.ninebotZ,
      model: modelName,
      serial: serial,
    ));
  }

  void _parseFirmware(Uint8List d) {
    if (d.length < 4) return;
    String hexDigit(int v) => (v & 0x0F).toRadixString(16).toUpperCase();
    final version =
        '${hexDigit(d[1])}.${hexDigit(d[0] >> 4)}.${hexDigit(d[0])}';
    _firmwareError1 = d[2];
    _firmwareError2 = d[3];
    if (d.length >= 6) {
      _firmwareWarn1 = d[4];
      _firmwareWarn2 = d[5];
    }
    updateIdentity(identity.copyWith(
      brand: WheelBrand.ninebotZ,
      firmware: version,
    ));
  }

  /// Bloque 1: bloqueo, modo limitado y alarmas (32 bytes).
  void _parseParams1(Uint8List d) {
    if (d.length < 32) return;
    _lockMode = _u16(d, 0);
    _limitedMode = _u16(d, 4);
    _limitModeSpeed1Kmh = _u16(d, 6) / 100.0;
    _limitModeSpeedKmh = _u16(d, 8) / 100.0;
    _alarmsMask = _u16(d, 24);
    _alarm1SpeedKmh = _u16(d, 26) / 100.0;
    _alarm2SpeedKmh = _u16(d, 28) / 100.0;
    _alarm3SpeedKmh = _u16(d, 30) / 100.0;
  }

  /// Bloque 2: LED, sensibilidad y banderas de conducción.
  void _parseParams2(Uint8List d) {
    if (d.length < 28) return;
    _ledMode = _u16(d, 0);
    _ledColor1 = (_i32(d, 4) >> 16) & 0xFF;
    _ledColor2 = (_i32(d, 8) >> 16) & 0xFF;
    _ledColor3 = (_i32(d, 12) >> 16) & 0xFF;
    _ledColor4 = (_i32(d, 16) >> 16) & 0xFF;
    _pedalSensitivity = _u16(d, 24);
    _driveFlags = _u16(d, 26);
  }

  /// Bloque 3: volumen del altavoz (el valor viaja desplazado).
  void _parseParams3(Uint8List d) {
    if (d.length < 2) return;
    _speakerVolume = _u16(d, 0) >> 3;
  }

  /// Datos en vivo: la telemetría principal (32 bytes).
  bool _parseLiveData(Uint8List d) {
    if (d.length < 28) return false;
    _errorCode = _u16(d, 0);
    _alarmCode = _u16(d, 2);
    _escStatus = _u16(d, 4);
    final batteryPct = _u16(d, 8);
    final speedKmh = _u16(d, 10) / 100.0;
    _avgSpeedKmh = _u16(d, 12) / 100.0;
    final totalDistanceM = _i32(d, 14);
    final tripDistanceM = _u16(d, 18) * 10;
    _operatingTimeSec = _u16(d, 20);
    final tempC = _s16(d, 22) / 10.0;
    final voltageV = _u16(d, 24) / 100.0;
    final currentA = _s16(d, 26) / 100.0;
    updateTelemetry(WheelTelemetry(
      speedKmh: speedKmh,
      voltageV: voltageV,
      currentA: currentA,
      powerW: voltageV * currentA,
      batteryPct: batteryPct.clamp(0, 100),
      tempC: tempC,
      distanceM: tripDistanceM,
      totalDistanceM: totalDistanceM,
      model: modelName,
    ));
    return true;
  }

  /// Serie y fabricación de un BMS (34 bytes útiles).
  void _parseBmsSn(_BmsState state, Uint8List d) {
    if (d.length < 34) return;
    state.serial =
        String.fromCharCodes(d.sublist(0, 14)).replaceAll('\u0000', '').trim();
    String hexDigit(int v) => (v & 0x0F).toRadixString(16).toUpperCase();
    state.version =
        '${d[15].toRadixString(16).toUpperCase()}.${hexDigit(d[14] >> 4)}.${hexDigit(d[14])}';
    state.factoryCapMah = _u16(d, 16);
    state.actualCapMah = _u16(d, 18);
    state.fullCycles = _u16(d, 22);
    state.chargeCount = _u16(d, 24);
    final mfg = _u16(d, 32);
    final day = (mfg & 0x1F).toString().padLeft(2, '0');
    final month = ((mfg >> 5) & 0x0F).toString().padLeft(2, '0');
    final year = (mfg >> 9).toString().padLeft(2, '0');
    state.mfgDate = '$day.$month.20$year';
    state.received = true;
  }

  /// Estado de un BMS: carga, voltaje, temperaturas y salud.
  void _parseBmsLife(_BmsState state, Uint8List d) {
    if (d.length < 24) return;
    state.status = _u16(d, 0);
    state.remainingCapMah = _u16(d, 2);
    state.remainingPct = _u16(d, 4);
    state.currentA = _s16(d, 6) / 100.0;
    state.voltageV = _u16(d, 8) / 100.0;
    state.temp1C = d[10] - 20;
    state.temp2C = d[11] - 20;
    state.balanceMap = _u16(d, 12);
    state.healthPct = _u16(d, 22);
    state.received = true;
  }

  /// Voltajes de las 16 celdas de un BMS, en milivoltios.
  void _parseBmsCells(_BmsState state, Uint8List d) {
    if (d.length < 32) return;
    state.cellsV = <double>[
      for (var i = 0; i < 16; i++) _u16(d, i * 2) / 1000.0,
    ];
    state.received = true;
  }

  // ---------------------------------------------------------------------------
  // Ayudantes little-endian (con la longitud ya comprobada).

  static int _u16(Uint8List d, int off) => d[off] | (d[off + 1] << 8);

  static int _s16(Uint8List d, int off) {
    final v = _u16(d, off);
    return v >= 0x8000 ? v - 0x10000 : v;
  }

  static int _i32(Uint8List d, int off) =>
      _u16(d, off) | (_u16(d, off + 2) << 16);
}

/// Datos de un BMS de Ninebot Z tal como los reporta su
/// protocolo: el modelo compartido de telemetría no tiene sitio
/// para el detalle por pack, así que el adaptador lo expone
/// aparte, como foto inmutable del último estado conocido.
class NinebotBmsData {
  const NinebotBmsData({
    this.serial,
    this.version,
    this.factoryCapMah,
    this.actualCapMah,
    this.fullCycles,
    this.chargeCount,
    this.mfgDate,
    this.status,
    this.remainingCapMah,
    this.remainingPct,
    this.currentA,
    this.voltageV,
    this.temp1C,
    this.temp2C,
    this.balanceMap,
    this.healthPct,
    this.cellsV = const <double>[],
  });

  /// Número de serie del pack (14 caracteres).
  final String? serial;

  /// Versión del firmware del BMS («x.y.z»).
  final String? version;

  /// Capacidad de fábrica en mAh.
  final int? factoryCapMah;

  /// Capacidad actual estimada en mAh.
  final int? actualCapMah;

  /// Ciclos completos de carga.
  final int? fullCycles;

  /// Número de cargas.
  final int? chargeCount;

  /// Fecha de fabricación («dd.mm.aaaa»).
  final String? mfgDate;

  /// Palabra de estado del BMS.
  final int? status;

  /// Capacidad restante en mAh.
  final int? remainingCapMah;

  /// Carga restante en %.
  final int? remainingPct;

  /// Corriente del pack en A.
  final double? currentA;

  /// Voltaje del pack en V.
  final double? voltageV;

  /// Temperaturas 1 y 2 del pack en °C (viajan con +20).
  final int? temp1C;
  final int? temp2C;

  /// Mapa de balanceo de celdas.
  final int? balanceMap;

  /// Salud del pack en %.
  final int? healthPct;

  /// Voltaje de cada celda en V (16 posiciones; las no pobladas
  /// llegan a 0.0 — la referencia fija 14 celdas útiles).
  final List<double> cellsV;

  /// Celdas con voltaje distinto de cero.
  int get cellCount => cellsV.where((v) => v > 0).length;
}

/// Estado mutable de un BMS dentro del adaptador; se expone
/// hacia fuera como [NinebotBmsData].
class _BmsState {
  bool received = false;
  String? serial;
  String? version;
  int? factoryCapMah;
  int? actualCapMah;
  int? fullCycles;
  int? chargeCount;
  String? mfgDate;
  int? status;
  int? remainingCapMah;
  int? remainingPct;
  double? currentA;
  double? voltageV;
  int? temp1C;
  int? temp2C;
  int? balanceMap;
  int? healthPct;
  List<double> cellsV = const <double>[];

  NinebotBmsData? snapshot() {
    if (!received) return null;
    return NinebotBmsData(
      serial: serial,
      version: version,
      factoryCapMah: factoryCapMah,
      actualCapMah: actualCapMah,
      fullCycles: fullCycles,
      chargeCount: chargeCount,
      mfgDate: mfgDate,
      status: status,
      remainingCapMah: remainingCapMah,
      remainingPct: remainingPct,
      currentA: currentA,
      voltageV: voltageV,
      temp1C: temp1C,
      temp2C: temp2C,
      balanceMap: balanceMap,
      healthPct: healthPct,
      cellsV: List<double>.unmodifiable(cellsV),
    );
  }
}

/// Desempaquetador con estado del protocolo Ninebot Z.
///
/// Busca la cabecera `5A A5`; el byte siguiente es `len` y la
/// trama completa mide `len + 9`. Solo busca la cabecera cuando
/// no está recolectando: un `5A A5` dentro de los datos no
/// reinicia la trama, igual que en la referencia.
class _NinebotZUnpacker {
  static const int _unknown = 0;
  static const int _started = 1;
  static const int _collecting = 2;
  static const int _done = 3;

  int _state = _unknown;
  final List<int> _buffer = <int>[];
  int _old = 0;
  int _frameLen = 0;

  /// Alimenta un byte; devuelve la trama completa cuando se
  /// cierra, o null mientras tanto.
  Uint8List? add(int byte) {
    final c = byte & 0xFF;
    switch (_state) {
      case _collecting:
        _buffer.add(c);
        if (_buffer.length == _frameLen + 9) {
          _state = _done;
          final frame = Uint8List.fromList(_buffer);
          _buffer.clear();
          _state = _unknown;
          return frame;
        }
        return null;
      case _started:
        _buffer.add(c);
        _frameLen = c;
        _state = _collecting;
        return null;
      default:
        if (c == 0xA5 && _old == 0x5A) {
          _buffer
            ..clear()
            ..add(0x5A)
            ..add(0xA5);
          _state = _started;
        }
        _old = c;
        return null;
    }
  }
}
