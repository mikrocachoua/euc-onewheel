/// Qué puede hacer la app con una rueda de una marca/modelo dados,
/// según lo que su adaptador ya implementa (no solo lo que el
/// protocolo permitiría en teoría).
///
/// La UI usa esto para decidir qué controles mostrar habilitados:
/// un control solo se activa si la capacidad está en `true` Y la
/// compuerta de seguridad lo permite en ese momento.
class WheelCapabilities {
  const WheelCapabilities({
    this.telemetry = false,
    this.lights = false,
    this.tiltBack = false,
    this.speedAlarms = false,
    this.pedalMode = false,
    this.calibration = false,
    this.motorLock = false,
    this.powerOff = false,
    this.beep = false,
    this.led = false,
    this.volume = false,
    this.transportMode = false,
  });

  /// Sin ninguna capacidad (rueda no identificada o sin adaptador).
  static const WheelCapabilities none = WheelCapabilities();

  /// Solo lectura de telemetría en vivo.
  static const WheelCapabilities telemetryOnly =
      WheelCapabilities(telemetry: true);

  /// Lectura de telemetría en vivo.
  final bool telemetry;

  /// Encender/apagar luces y LED.
  final bool lights;

  /// Cambiar la velocidad de tilt-back.
  final bool tiltBack;

  /// Cambiar las alarmas de velocidad.
  final bool speedAlarms;

  /// Cambiar el modo de pedales/conducción.
  final bool pedalMode;

  /// Ejecutar la calibración de nivel.
  final bool calibration;

  /// Bloquear el motor (antirrobo).
  final bool motorLock;

  /// Apagar la rueda remotamente.
  final bool powerOff;

  /// Beep/claxon de prueba.
  final bool beep;

  /// Cambiar el modo del LED decorativo.
  final bool led;

  /// Cambiar el volumen del beeper/altavoz.
  final bool volume;

  /// Activar/desactivar el modo transporte.
  final bool transportMode;
}
