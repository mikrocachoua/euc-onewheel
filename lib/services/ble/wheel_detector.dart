import '../../models/wheel_identity.dart';

/// UUIDs GATT relevantes, en su forma completa de 128 bits.
abstract final class GattUuid {
  static const String serialService = '0000ffe0-0000-1000-8000-00805f9b34fb';
  static const String serialChar = '0000ffe1-0000-1000-8000-00805f9b34fb';
  static const String kingsongExtraService =
      '0000fff0-0000-1000-8000-00805f9b34fb';
  static const String gotwayNewModuleService =
      '1d14d6ee-fd63-4fa1-bfa4-8f47b42119f0';
  static const String inmotionWriteService =
      '0000ffe5-0000-1000-8000-00805f9b34fb';
  static const String inmotionReadChar = '0000ffe4-0000-1000-8000-00805f9b34fb';
  static const String inmotionWriteChar =
      '0000ffe9-0000-1000-8000-00805f9b34fb';
  static const String nusService = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
  static const String nusRxChar = '6e400002-b5a3-f393-e0a9-e50e24dcca9e';
  static const String nusTxChar = '6e400003-b5a3-f393-e0a9-e50e24dcca9e';
  static const String ninebotZExtraService =
      '0000fee7-0000-1000-8000-00805f9b34fb';

  /// Transport family names used by the BLE layer.
  static const String transportSharedSerial = 'shared-ffe0';
  static const String transportInmotionClassic = 'inmotion-classic';
  static const String transportNus = 'nordic-uart';
}

/// Normaliza un UUID a su forma de 128 bits en minúsculas, aceptando
/// formas cortas de 16 bits («ffe0») o de 32 bits.
String normalizeUuid(String uuid) {
  var u = uuid.toLowerCase().trim();
  if (u.startsWith('0x')) u = u.substring(2);
  if (u.length == 4) return '0000$u-0000-1000-8000-00805f9b34fb';
  if (u.length == 8) return '$u-0000-1000-8000-00805f9b34fb';
  return u;
}

/// Resultado de analizar la huella GATT de un dispositivo:
/// las marcas candidatas y el transporte serie que hay que usar.
class GattFingerprint {
  const GattFingerprint({
    required this.candidates,
    required this.transport,
    this.transportConfidence = 0,
  });

  /// Marcas posibles según los servicios/características vistos.
  /// Puede venir más de una: el transporte ffe0/ffe1 lo comparten
  /// KingSong, Begode, Veteran y Ninebot clásico, y se desempata
  /// oliendo la primera trama ya conectado.
  final Set<WheelBrand> candidates;

  /// Transporte a usar (ver [GattUuid.transport*]); null si el
  /// dispositivo no expone ningún transporte serie conocido.
  final String? transport;

  /// Qué tan seguro es que ese sea el transporte (0–100).
  final int transportConfidence;
}

/// Detector de marca en dos pasos:
/// 1. **Huella GATT**: conjunto de servicios/características
///    descubiertos al conectar (el UUID por sí solo no basta: varias
///    marcas comparten el transporte serie ffe0/ffe1 o el NUS).
/// 2. **Olfateo de la primera trama**: cabeceras características de
///    cada protocolo sobre la característica de notificaciones.
abstract final class WheelDetector {
  /// Paso 1: analiza los UUID descubiertos de un dispositivo.
  static GattFingerprint fromGatt({
    required Set<String> serviceUuids,
    required Set<String> characteristicUuids,
  }) {
    final services = serviceUuids.map(normalizeUuid).toSet();
    final chars = characteristicUuids.map(normalizeUuid).toSet();

    final hasSerial = services.contains(GattUuid.serialService) &&
        chars.contains(GattUuid.serialChar);
    final hasNus = services.contains(GattUuid.nusService) &&
        chars.contains(GattUuid.nusRxChar) &&
        chars.contains(GattUuid.nusTxChar);
    final hasInmotionClassic = chars.contains(GattUuid.inmotionReadChar) &&
        (services.contains(GattUuid.inmotionWriteService) ||
            chars.contains(GattUuid.inmotionWriteChar));

    if (hasInmotionClassic && !hasSerial) {
      return const GattFingerprint(
        candidates: {WheelBrand.inmotion},
        transport: GattUuid.transportInmotionClassic,
        transportConfidence: 95,
      );
    }

    if (hasSerial) {
      // Transporte compartido: las cuatro marcas son candidatas y
      // el desempate final lo hace la primera trama. KingSong suele
      // anunciar además el servicio fff0; los módulos BLE nuevos de
      // Begode exponen 1d14d6ee… (huella solo-Begode/Veteran).
      final candidates = <WheelBrand>{
        WheelBrand.kingsong,
        WheelBrand.begode,
        WheelBrand.veteran,
        WheelBrand.ninebot,
      };
      if (services.contains(GattUuid.gotwayNewModuleService)) {
        candidates.remove(WheelBrand.kingsong);
      }
      return GattFingerprint(
        candidates: candidates,
        transport: GattUuid.transportSharedSerial,
        transportConfidence: 90,
      );
    }

    if (hasNus) {
      final candidates = <WheelBrand>{WheelBrand.inmotionV2};
      // Ninebot Z comparte el NUS y a veces expone además fee7.
      candidates.add(WheelBrand.ninebotZ);
      return GattFingerprint(
        candidates: candidates,
        transport: GattUuid.transportNus,
        transportConfidence:
            services.contains(GattUuid.ninebotZExtraService) ? 60 : 80,
      );
    }

    return const GattFingerprint(
      candidates: {WheelBrand.unknown},
      transport: null,
      transportConfidence: 0,
    );
  }

  /// Paso 2: huele la primera trama recibida y devuelve la marca
  /// cuyo protocolo la firma, o null si no se reconoce.
  ///
  /// Firmas: `AA 55` KingSong · `55 AA` Begode (o Ninebot clásico,
  /// ya desempatado por la huella) · `DC 5A 5C` Veteran ·
  /// `AA AA` InMotion (clásico o V2) · `5A A5` Ninebot Z.
  static WheelBrand? sniffFirstFrame(
    List<int> frame, {
    required Set<WheelBrand> candidates,
    required String? transport,
  }) {
    if (frame.length < 2) return null;
    final b0 = frame[0] & 0xFF;
    final b1 = frame[1] & 0xFF;

    if (b0 == 0xAA && b1 == 0x55) {
      return _pick(candidates, WheelBrand.kingsong);
    }
    if (b0 == 0x55 && b1 == 0xAA) {
      // En el transporte compartido es Begode; si la huella dejó
      // solo a Ninebot clásico como candidato, es Ninebot.
      if (candidates.length == 1 && candidates.contains(WheelBrand.ninebot)) {
        return WheelBrand.ninebot;
      }
      return _pick(candidates, WheelBrand.begode);
    }
    if (frame.length >= 3 &&
        b0 == 0xDC &&
        b1 == 0x5A &&
        (frame[2] & 0xFF) == 0x5C) {
      return _pick(candidates, WheelBrand.veteran);
    }
    if (b0 == 0xAA && b1 == 0xAA) {
      if (transport == GattUuid.transportNus) {
        return _pick(candidates, WheelBrand.inmotionV2);
      }
      return _pick(candidates, WheelBrand.inmotion);
    }
    if (b0 == 0x5A && b1 == 0xA5) {
      return _pick(candidates, WheelBrand.ninebotZ);
    }
    return null;
  }

  static WheelBrand? _pick(Set<WheelBrand> candidates, WheelBrand brand) {
    if (candidates.isEmpty || candidates.contains(brand)) return brand;
    return null;
  }
}
