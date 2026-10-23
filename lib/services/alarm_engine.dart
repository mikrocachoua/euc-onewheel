import '../models/wheel_telemetry.dart';
import '../state/app_settings.dart';

/// Una alarma disparada por la telemetría en vivo: qué es, qué valor
/// se midió y qué umbral se superó.
class ActiveAlarm {
  const ActiveAlarm({
    required this.kind,
    required this.measured,
    required this.threshold,
  });

  final AlarmKind kind;
  final double measured;
  final double threshold;

  /// Texto corto para el aviso en el panel.
  String get message =>
      '${kind.label}: ${measured.toStringAsFixed(kind == AlarmKind.velocidad || kind == AlarmKind.temperatura || kind == AlarmKind.pwm ? 0 : 1)} '
      '${kind.unit} (límite ${threshold.toStringAsFixed(0)} ${kind.unit})';
}

/// Valor de telemetría que vigila cada tipo de alarma (null si la
/// rueda no lo reporta: la alarma simplemente no puede saltar).
double? _measuredFor(AlarmKind kind, WheelTelemetry t) => switch (kind) {
      AlarmKind.velocidad => t.speedKmh.abs(),
      AlarmKind.amperaje => t.currentA.abs(),
      AlarmKind.potencia => t.powerW.abs(),
      AlarmKind.temperatura => t.tempC,
      AlarmKind.pwm => t.pwmPct,
    };

/// Evalúa la telemetría contra los umbrales configurados y devuelve
/// las alarmas activas. Función pura: la usan el panel (aviso
/// visual/sonoro) y el motor AVAS (las alarmas reales siempre tienen
/// prioridad sobre el sonido de motor).
List<ActiveAlarm> evaluateAlarms(
  WheelTelemetry telemetry,
  Map<AlarmKind, AlarmThreshold> thresholds,
) {
  final active = <ActiveAlarm>[];
  for (final kind in AlarmKind.values) {
    final threshold = thresholds[kind];
    if (threshold == null || !threshold.enabled) continue;
    final measured = _measuredFor(kind, telemetry);
    if (measured == null) continue;
    if (measured >= threshold.value) {
      active.add(ActiveAlarm(
        kind: kind,
        measured: measured,
        threshold: threshold.value,
      ));
    }
  }
  return active;
}
