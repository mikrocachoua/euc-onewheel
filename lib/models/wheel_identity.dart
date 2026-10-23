/// Marcas de rueda que EUC OneWheel sabe reconocer por Bluetooth.
///
/// Cada marca tiene su propio protocolo sobre BLE; el detector
/// (wheel_detector.dart) decide la marca por la huella GATT y por la
/// primera trama recibida, y el controlador crea el adaptador que
/// corresponda.
enum WheelBrand {
  kingsong('KingSong'),
  begode('Begode (Gotway)'),
  veteran('Veteran (LeaperKim)'),
  inmotion('InMotion'),
  inmotionV2('InMotion V2'),
  ninebot('Ninebot'),
  ninebotZ('Ninebot Z'),
  unknown('Desconocida');

  const WheelBrand(this.label);

  /// Nombre visible para el usuario.
  final String label;
}

/// Identidad de una rueda conectada: qué es, quién la anuncia y,
/// cuando el protocolo lo reporta, su número de serie y firmware.
class WheelIdentity {
  const WheelIdentity({
    this.brand = WheelBrand.unknown,
    this.deviceId = '',
    this.advertisedName,
    this.model,
    this.serial,
    this.firmware,
  });

  final WheelBrand brand;

  /// Id del dispositivo Bluetooth (dirección/UUID del periférico).
  final String deviceId;

  /// Nombre que la rueda anuncia por BLE, si lo publica.
  final String? advertisedName;

  /// Modelo (p. ej. «KS-S18»), cuando el protocolo lo informa.
  final String? model;

  /// Número de serie, cuando el protocolo lo informa.
  final String? serial;

  /// Versión de firmware, cuando el protocolo la informa.
  final String? firmware;

  WheelIdentity copyWith({
    WheelBrand? brand,
    String? deviceId,
    String? advertisedName,
    String? model,
    String? serial,
    String? firmware,
  }) {
    return WheelIdentity(
      brand: brand ?? this.brand,
      deviceId: deviceId ?? this.deviceId,
      advertisedName: advertisedName ?? this.advertisedName,
      model: model ?? this.model,
      serial: serial ?? this.serial,
      firmware: firmware ?? this.firmware,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is WheelIdentity &&
      other.brand == brand &&
      other.deviceId == deviceId &&
      other.advertisedName == advertisedName &&
      other.model == model &&
      other.serial == serial &&
      other.firmware == firmware;

  @override
  int get hashCode =>
      Object.hash(brand, deviceId, advertisedName, model, serial, firmware);
}
