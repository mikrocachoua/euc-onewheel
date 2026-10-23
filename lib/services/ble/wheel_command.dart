import 'safety_gate.dart';

/// Estado de luz que se pide a la rueda (no todas las marcas ni todos
/// los adaptadores soportan estrobo; el adaptador decide).
enum LightState { off, on, strobe }

/// Un paso de la ejecución de un comando: la trama a enviar y la
/// espera que debe cumplirse ANTES de enviarla. Los protocolos con
/// secuencias temporizadas (Begode, apagado de InMotion) se expresan
/// como varios pasos; el controlador los pasa uno a uno por la
/// compuerta de seguridad, en orden.
class CommandStep {
  const CommandStep(this.frame, {this.delayBefore = Duration.zero});

  /// Trama cruda lista para escribir en la característica BLE.
  final List<int> frame;

  /// Espera previa a enviar esta trama (cero en el primer paso).
  final Duration delayBefore;
}

/// Petición de comando de control con parámetros, tal como la genera
/// la UI. Cada adaptador sabe construir (o no) las tramas de su marca
/// a partir de la petición: `buildCommand` devuelve `null` cuando el
/// comando no está implementado/verificado para esa marca, y la UI
/// solo ofrece los controles que las capacidades del adaptador
/// anuncian.
///
/// Ninguna petición escribe por sí misma: el controlador pasa cada
/// trama por la [SafetyGate], el único punto de salida.
sealed class WheelCommandRequest {
  const WheelCommandRequest();

  /// Comando de la compuerta al que equivale esta petición.
  WheelCommand get command;
}

/// Encender/apagar la luz (o estrobo donde exista).
class LightRequest extends WheelCommandRequest {
  const LightRequest(this.state);
  final LightState state;
  @override
  WheelCommand get command => WheelCommand.light;
}

/// Beep/claxon de prueba de la rueda.
class BeepRequest extends WheelCommandRequest {
  const BeepRequest();
  @override
  WheelCommand get command => WheelCommand.beep;
}

/// Modo de pedales: 0 = duro, 1 = medio, 2 = suave.
class PedalModeRequest extends WheelCommandRequest {
  const PedalModeRequest(this.mode);
  final int mode;
  @override
  WheelCommand get command => WheelCommand.pedalMode;
}

/// Velocidad máxima (tilt-back) en km/h; 0 = sin límite donde el
/// protocolo lo admite.
class TiltBackRequest extends WheelCommandRequest {
  const TiltBackRequest(this.kmh);
  final int kmh;
  @override
  WheelCommand get command => WheelCommand.tiltBack;
}

/// Velocidades de alarma en km/h, en orden (1ª, 2ª, 3ª según marca).
///
/// En KingSong la misma trama lleva alarmas Y velocidad máxima: ahí
/// [tiltBackKmh] debe acompañar a las alarmas para no borrar el
/// límite vigente (el editor de la UI las pide juntas).
class SpeedAlarmsRequest extends WheelCommandRequest {
  const SpeedAlarmsRequest(this.speedsKmh, {this.tiltBackKmh});
  final List<int> speedsKmh;
  final int? tiltBackKmh;
  @override
  WheelCommand get command => WheelCommand.speedAlarms;
}

/// Modo de alarmas de Begode: 0 = dos alarmas, 1 = una, 2 = apagadas,
/// 3 = personalizado (firmware custom).
class AlarmModeRequest extends WheelCommandRequest {
  const AlarmModeRequest(this.mode);
  final int mode;
  @override
  WheelCommand get command => WheelCommand.speedAlarms;
}

/// Calibración de nivel de la rueda (detenida, nivelada y apoyada).
class CalibrationRequest extends WheelCommandRequest {
  const CalibrationRequest();
  @override
  WheelCommand get command => WheelCommand.calibration;
}

/// Bloqueo/desbloqueo de motor (antirrobo).
class MotorLockRequest extends WheelCommandRequest {
  const MotorLockRequest(this.lock);
  final bool lock;
  @override
  WheelCommand get command => WheelCommand.motorLock;
}

/// Apagar la rueda remotamente.
class PowerOffRequest extends WheelCommandRequest {
  const PowerOffRequest();
  @override
  WheelCommand get command => WheelCommand.powerOff;
}

/// Modo transporte on/off.
class TransportModeRequest extends WheelCommandRequest {
  const TransportModeRequest(this.on);
  final bool on;
  @override
  WheelCommand get command => WheelCommand.transportMode;
}

/// Modo del LED decorativo (número de modo según la marca).
class LedModeRequest extends WheelCommandRequest {
  const LedModeRequest(this.mode);
  final int mode;
  @override
  WheelCommand get command => WheelCommand.led;
}

/// Volumen del beeper/altavoz (nivel 0–9 según la marca).
class VolumeRequest extends WheelCommandRequest {
  const VolumeRequest(this.level);
  final int level;
  @override
  WheelCommand get command => WheelCommand.volume;
}
