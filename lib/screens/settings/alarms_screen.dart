import 'package:flutter/material.dart';

import '../../state/app_settings.dart';
import '../../theme.dart';
import '../../widgets/ui_kit.dart';
import 'settings_widgets.dart';

/// Alarmas configurables sobre la telemetría en vivo: velocidad,
/// amperaje, potencia, temperatura y PWM. Cada una tiene su
/// interruptor y su umbral editable; cuando un valor lo supera, el
/// panel muestra el aviso y suena una alerta (y el sonido de motor,
/// si está activo, se agacha para no taparla).
class AlarmsScreen extends StatelessWidget {
  const AlarmsScreen({super.key, required this.settings});

  final AppSettings settings;

  /// Rango razonable de ajuste por tipo de alarma (min, max, paso).
  static (double, double, double) _rangeFor(AlarmKind kind) => switch (kind) {
        AlarmKind.velocidad => (5, 80, 1),
        AlarmKind.amperaje => (5, 120, 1),
        AlarmKind.potencia => (200, 6000, 100),
        AlarmKind.temperatura => (40, 100, 1),
        AlarmKind.pwm => (50, 100, 1),
      };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        return SettingsScaffold(
          title: 'Alarmas',
          children: [
            const SurfaceCard(
              child: Text(
                'Define a partir de qué valor quieres que el panel te '
                'avise mientras ruedas. Las alarmas de la app son un '
                'apoyo visual y sonoro: las protecciones propias de '
                'tu rueda siguen mandando siempre.',
                style: TextStyle(color: subText, fontSize: 14),
              ),
            ),
            const SizedBox(height: 16),
            for (final kind in AlarmKind.values) ...[
              _alarmCard(context, kind),
              const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }

  Widget _alarmCard(BuildContext context, AlarmKind kind) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final threshold = settings.alarms[kind]!;
    final (min, max, step) = _rangeFor(kind);
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Alarma por ${kind.label.toLowerCase()}',
                  style: const TextStyle(
                      fontSize: 16.5, fontWeight: FontWeight.w800),
                ),
              ),
              Switch(
                value: threshold.enabled,
                onChanged: (on) => settings.update((s) {
                  s.alarms[kind] = threshold.copyWith(enabled: on);
                }),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: threshold.value.clamp(min, max),
                  min: min,
                  max: max,
                  divisions: ((max - min) / step).round(),
                  onChanged: threshold.enabled
                      ? (v) => settings.update((s) {
                            s.alarms[kind] = threshold.copyWith(value: v);
                          })
                      : null,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: funcBlue.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: funcBlue.withValues(alpha: 0.30)),
                ),
                child: Text(
                  '${threshold.value.toStringAsFixed(0)} ${kind.unit}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: dark ? funcBlueLight : const Color(0xFF1B5FBF),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
