import 'dart:typed_data';

import '../../../models/wheel_capabilities.dart';
import '../../../models/wheel_identity.dart';
import 'wheel_adapter.dart';

/// Adaptador KingSong — **solo telemetría** en esta fase.
///
/// Protocolo: tramas fijas de 20 bytes con cabecera `AA 55` y tipo
/// en el byte 16. Los campos multibyte se leen con la regla «R» de
/// la referencia abierta del protocolo: cada pareja de bytes viene invertida respecto a
/// big-endian. Sin cifrado ni handshake.
///
/// Tramas implementadas:
/// - `0xA9` live: voltaje, velocidad, distancia total, corriente,
///   temperatura, modo de pedales y % de batería por curva del modelo.
/// - `0xB9`: distancia del viaje, velocidad máxima, ventilador,
///   estado de carga y segunda temperatura.
/// - `0xBB`: nombre/modelo (de ahí sale el modelo y el firmware).
/// - `0xB3`: número de serie.
///
/// Los comandos de control de KingSong aún NO se construyen aquí:
/// cuando se implementen, saldrán únicamente por la compuerta de
/// seguridad (safety_gate.dart).
class KingSongAdapter extends BaseWheelAdapter {
  KingSongAdapter();

  /// Tipo de trama: byte 16.
  static const int typeLive = 0xA9;
  static const int typeTrip = 0xB9;
  static const int typeName = 0xBB;
  static const int typeSerial = 0xB3;

  /// Peticiones de solo lectura al conectar.
  static const int requestName = 0x9B;
  static const int requestSerial = 0x63;

  int? _pedalMode;
  int? _fanStatus;
  int? _chargingStatus;
  double? _topSpeedKmh;

  /// Modo de pedales reportado en la trama live (byte 14 si el
  /// byte 15 vale 0xE0): 0, 1 o 2 según el ajuste de la rueda.
  int? get pedalMode => _pedalMode;

  /// Ventilador encendido (1) / apagado (0), de la trama 0xB9.
  int? get fanStatus => _fanStatus;

  /// Estado de carga reportado en la trama 0xB9.
  int? get chargingStatus => _chargingStatus;

  /// Velocidad máxima registrada por la rueda (trama 0xB9), km/h.
  double? get topSpeedKmh => _topSpeedKmh;

  @override
  WheelBrand get brand => WheelBrand.kingsong;

  @override
  WheelCapabilities get capabilities => WheelCapabilities.telemetryOnly;

  @override
  List<Uint8List> initialRequests() => [
        buildReadRequest(requestName),
        buildReadRequest(requestSerial),
      ];

  /// Construye una trama de petición de solo lectura de 20 bytes:
  /// `AA 55` + 14 bytes de datos en cero + tipo + `14 5A 5A`.
  static Uint8List buildReadRequest(int type) {
    final frame = Uint8List(20);
    frame[0] = 0xAA;
    frame[1] = 0x55;
    frame[16] = type;
    frame[17] = 0x14;
    frame[18] = 0x5A;
    frame[19] = 0x5A;
    return frame;
  }

  @override
  bool decode(Uint8List data) {
    if (data.length < 20) return false;
    if (data[0] != 0xAA || data[1] != 0x55) return false;

    switch (data[16]) {
      case typeLive:
        _decodeLive(data);
        return true;
      case typeTrip:
        _decodeTrip(data);
        return false;
      case typeName:
        _decodeName(data);
        return false;
      case typeSerial:
        _decodeSerial(data);
        return false;
      default:
        return false;
    }
  }

  void _decodeLive(Uint8List data) {
    final voltageCv = _getInt2R(data, 2);
    final speedRaw = _getInt2R(data, 4);
    final totalDistanceM = _getInt4R(data, 6);
    // La corriente NO usa la lectura «R»: son los bytes 10–11 en
    // little-endian con signo (así lo define la referencia del protocolo).
    final currentRaw = ByteData.sublistView(data).getInt16(10, Endian.little);
    final tempRaw = _getInt2R(data, 12);
    if (data[15] == 0xE0) {
      _pedalMode = data[14];
    }
    final voltageV = voltageCv / 100.0;
    final currentA = currentRaw / 100.0;
    updateTelemetry(telemetry.copyWith(
      speedKmh: speedRaw / 100.0,
      voltageV: voltageV,
      currentA: currentA,
      powerW: voltageV * currentA,
      batteryPct: batteryLevelFor(voltageCv, model: identity.model),
      tempC: tempRaw / 100.0,
      totalDistanceM: totalDistanceM,
      model: identity.model,
    ));
  }

  void _decodeTrip(Uint8List data) {
    final tripDistanceM = _getInt4R(data, 2);
    _topSpeedKmh = _getInt2R(data, 8) / 100.0;
    _fanStatus = data[12];
    _chargingStatus = data[13];
    updateTelemetry(telemetry.copyWith(
      distanceM: tripDistanceM,
      temp2C: _getInt2R(data, 14) / 100.0,
    ));
  }

  void _decodeName(Uint8List data) {
    var end = 0;
    while (end < 14 && data[end + 2] != 0) {
      end++;
    }
    final name = String.fromCharCodes(data.sublist(2, 2 + end)).trim();
    if (name.isEmpty) return;
    final parts = name.split('-');
    final model =
        parts.length > 1 ? parts.sublist(0, parts.length - 1).join('-') : name;
    String? firmware;
    if (parts.length > 1) {
      final versionRaw = int.tryParse(parts.last);
      if (versionRaw != null) {
        firmware = (versionRaw / 100.0).toStringAsFixed(2);
      }
    }
    updateIdentity(identity.copyWith(
      brand: WheelBrand.kingsong,
      model: model,
      firmware: firmware,
    ));
    updateTelemetry(telemetry.copyWith(model: model));
  }

  void _decodeSerial(Uint8List data) {
    final bytes = Uint8List(17);
    bytes.setRange(0, 14, data, 2);
    bytes.setRange(14, 17, data, 17);
    final serial = String.fromCharCodes(bytes).replaceAll('\x00', '').trim();
    if (serial.isEmpty) return;
    updateIdentity(identity.copyWith(
      brand: WheelBrand.kingsong,
      serial: serial,
    ));
  }

  /// % de batería por curva lineal según la clase de voltaje
  /// nominal del modelo (réplica de las curvas base de la referencia abierta;
  /// [voltageCv] en centivoltios).
  static int batteryLevelFor(int voltageCv, {String? model}) {
    final (floorCv, ceilCv, divisor) = switch (model) {
      'KS-18L' ||
      'KS-16X' ||
      'KS-16XF' ||
      'RW' ||
      'KS-18LH' ||
      'KS-18LY' ||
      'KS-S18' ||
      'KS-S16' ||
      'KS-S16P' =>
        (6250, 8250, 20), // 84 V (20 celdas)
      'KS-S20' || 'KS-S22' => (9375, 12375, 30), // 126 V (30 celdas)
      'KS-S19' => (7500, 9900, 24), // 100.8 V (24 celdas)
      'KS-F18P' => (11250, 14850, 36), // 151.2 V (36 celdas)
      'KS-F22P' => (13125, 17325, 42), // 176.4 V (42 celdas)
      _ => (5000, 6600, 16), // 67.2 V (16 celdas), clase por defecto
    };
    if (voltageCv < floorCv) return 0;
    if (voltageCv >= ceilCv) return 100;
    return (voltageCv - floorCv) ~/ divisor;
  }

  /// Lectura «R» de 2 bytes: la pareja viene invertida y el valor
  /// resultante es big-endian con signo.
  static int _getInt2R(Uint8List arr, int offset) {
    final v = ((arr[offset + 1] & 0xFF) << 8) | (arr[offset] & 0xFF);
    return v >= 0x8000 ? v - 0x10000 : v;
  }

  /// Lectura «R» de 4 bytes: cada pareja viene invertida y el valor
  /// resultante es big-endian con signo.
  static int _getInt4R(Uint8List arr, int offset) {
    final v = ((arr[offset + 1] & 0xFF) << 24) |
        ((arr[offset] & 0xFF) << 16) |
        ((arr[offset + 3] & 0xFF) << 8) |
        (arr[offset + 2] & 0xFF);
    return v >= 0x80000000 ? v - 0x100000000 : v;
  }
}
