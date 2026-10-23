/// Snapshot inmutable de la telemetría en vivo de la rueda.
///
/// Todos los valores nacen en un estado neutro (0 / null) y se van
/// completando conforme el adaptador de la marca decodifica tramas.
/// Las unidades ya vienen convertidas: km/h, voltios, amperios,
/// vatios, °C y metros.
class WheelTelemetry {
  const WheelTelemetry({
    this.speedKmh = 0,
    this.voltageV = 0,
    this.currentA = 0,
    this.powerW = 0,
    this.batteryPct,
    this.tempC = 0,
    this.temp2C,
    this.pwmPct,
    this.distanceM = 0,
    this.totalDistanceM = 0,
    this.model,
  });

  /// Snapshot neutro: sin datos de ninguna rueda todavía.
  static const WheelTelemetry neutral = WheelTelemetry();

  /// Velocidad actual en km/h (puede ser negativa en reversa).
  final double speedKmh;

  /// Voltaje del pack en V.
  final double voltageV;

  /// Corriente en A (negativa = regenerando/cargando).
  final double currentA;

  /// Potencia en W (la reporta la rueda o se calcula V × A).
  final double powerW;

  /// Nivel de batería 0–100, calculado por curva según el modelo.
  final int? batteryPct;

  /// Temperatura principal en °C.
  final double tempC;

  /// Segunda temperatura en °C, si la marca la reporta.
  final double? temp2C;

  /// Ciclo de trabajo del controlador (PWM) 0–100, si la marca lo
  /// reporta o puede derivarse; null cuando no se conoce.
  final double? pwmPct;

  /// Distancia del viaje actual en metros.
  final int distanceM;

  /// Odómetro total de la rueda en metros.
  final int totalDistanceM;

  /// Modelo detectado (p. ej. «KS-S18»), si ya se conoce.
  final String? model;

  /// ¿La rueda se está moviendo? (umbral mínimo anti-ruido).
  bool get isMoving => speedKmh.abs() > 0.01;

  WheelTelemetry copyWith({
    double? speedKmh,
    double? voltageV,
    double? currentA,
    double? powerW,
    int? batteryPct,
    double? tempC,
    double? temp2C,
    double? pwmPct,
    int? distanceM,
    int? totalDistanceM,
    String? model,
  }) {
    return WheelTelemetry(
      speedKmh: speedKmh ?? this.speedKmh,
      voltageV: voltageV ?? this.voltageV,
      currentA: currentA ?? this.currentA,
      powerW: powerW ?? this.powerW,
      batteryPct: batteryPct ?? this.batteryPct,
      tempC: tempC ?? this.tempC,
      temp2C: temp2C ?? this.temp2C,
      pwmPct: pwmPct ?? this.pwmPct,
      distanceM: distanceM ?? this.distanceM,
      totalDistanceM: totalDistanceM ?? this.totalDistanceM,
      model: model ?? this.model,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is WheelTelemetry &&
      other.speedKmh == speedKmh &&
      other.voltageV == voltageV &&
      other.currentA == currentA &&
      other.powerW == powerW &&
      other.batteryPct == batteryPct &&
      other.tempC == tempC &&
      other.temp2C == temp2C &&
      other.pwmPct == pwmPct &&
      other.distanceM == distanceM &&
      other.totalDistanceM == totalDistanceM &&
      other.model == model;

  @override
  int get hashCode => Object.hash(speedKmh, voltageV, currentA, powerW,
      batteryPct, tempC, temp2C, pwmPct, distanceM, totalDistanceM, model);
}
