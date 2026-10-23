import '../state/app_settings.dart';

/// Salida del motor AVAS en un instante: si debe sonar, con qué tono
/// (frecuencia en Hz), qué volumen efectivo y si está «agachado»
/// (ducking) porque hay una alarma real sonando.
class AvasOutput {
  const AvasOutput({
    required this.sounding,
    required this.frequencyHz,
    required this.volume,
    required this.ducked,
  });

  /// Silencio total: AVAS apagado, sin rueda o rueda detenida.
  static const AvasOutput silent = AvasOutput(
    sounding: false,
    frequencyHz: 0,
    volume: 0,
    ducked: false,
  );

  final bool sounding;
  final double frequencyHz;
  final double volume; // 0..1 ya con ducking aplicado
  final bool ducked;
}

/// Velocidad a la que el tono AVAS llega a su frecuencia máxima.
const double avasFullSpeedKmh = 60;

/// Factor de volumen cuando una alarma real tiene prioridad: el
/// sonido de motor baja casi a silencio para nunca taparla.
const double avasDuckFactor = 0.12;

/// Lógica pura del sonido de motor (AVAS, sistema de alerta acústica
/// de vehículo): decide si suena y con qué tono/volumen según el
/// estado de la app, sin tocar ningún reproductor de audio.
///
/// Reglas:
/// - Apagado por defecto; solo suena con el interruptor activo.
/// - Requiere rueda conectada y velocidad > 0 (rodando).
/// - El tono sube con la velocidad, de la frecuencia base del preset
///   a su máxima a [avasFullSpeedKmh].
/// - Si hay una alarma real activa, el volumen se «agacha»
///   ([avasDuckFactor]): las alarmas de la rueda mandan siempre.
AvasOutput computeAvas({
  required bool enabled,
  required bool connected,
  required double speedKmh,
  required bool alarmActive,
  required AvasPreset preset,
  required double volume,
}) {
  if (!enabled || !connected || speedKmh <= 0) return AvasOutput.silent;
  final ratio = (speedKmh / avasFullSpeedKmh).clamp(0.0, 1.0);
  final frequency = preset.baseHz + (preset.maxHz - preset.baseHz) * ratio;
  final ducked = alarmActive;
  return AvasOutput(
    sounding: true,
    frequencyHz: frequency,
    volume: (volume.clamp(0.0, 1.0)) * (ducked ? avasDuckFactor : 1.0),
    ducked: ducked,
  );
}

/// Interfaz del reproductor de audio del AVAS. La implementación por
/// defecto de la base v2 es silenciosa (el motor de audio nativo se
/// conecta en una fase posterior); la lógica de decisión vive en
/// [computeAvas] y ya está cubierta por pruebas.
abstract class AvasAudioBackend {
  void apply(AvasOutput output);
  void stop();
}

/// Backend sin audio: registra la última salida pedida. Sirve como
/// base segura mientras no hay reproductor nativo conectado.
class SilentAvasBackend implements AvasAudioBackend {
  AvasOutput lastOutput = AvasOutput.silent;
  bool stopped = false;

  @override
  void apply(AvasOutput output) {
    lastOutput = output;
    stopped = false;
  }

  @override
  void stop() {
    lastOutput = AvasOutput.silent;
    stopped = true;
  }
}
