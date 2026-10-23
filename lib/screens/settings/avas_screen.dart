import 'package:flutter/material.dart';

import '../../services/avas_engine.dart';
import '../../state/app_settings.dart';
import '../../theme.dart';
import '../../widgets/ui_kit.dart';
import 'settings_widgets.dart';

/// Sonido de motor (AVAS): sistema de alerta acústica de vehículo.
/// La app emite un tono de «motor» por la bocina del teléfono para
/// que peatones y ciclistas te escuchen llegar. Tiene presets,
/// volumen propio y el tono sigue a la velocidad.
///
/// Reglas de la base v2:
/// - Apagado por defecto.
/// - Solo suena con rueda conectada (o demo) y velocidad > 0.
/// - Si salta una alarma real, el sonido se agacha casi a silencio:
///   las alarmas de la rueda nunca quedan tapadas.
/// - La lógica de decisión está completa y probada; el reproductor
///   de audio nativo se conecta en una fase posterior (hoy el motor
///   de audio es básico y silencioso).
class AvasScreen extends StatelessWidget {
  const AvasScreen({super.key, required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        // Estado actual de la lógica, calculado sin audio real.
        final preview = computeAvas(
          enabled: settings.avasEnabled,
          connected: true,
          speedKmh: 25,
          alarmActive: false,
          preset: settings.avasPreset,
          volume: settings.avasVolume,
        );
        return SettingsScaffold(
          title: 'Sonido de motor',
          children: [
            SettingsGroup(
              children: [
                SwitchTile(
                  title: 'Sonido de motor (AVAS)',
                  subtitle: 'Sistema de alerta acústica de vehículo: un tono '
                      'de motor por la bocina del teléfono para que te '
                      'escuchen al rodar.',
                  value: settings.avasEnabled,
                  onChanged: (on) => settings.update((s) => s.avasEnabled = on),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const SectionHeader('Preset de sonido'),
            RadioGroup<AvasPreset>(
              groupValue: settings.avasPreset,
              onChanged: (v) {
                if (v != null) settings.update((s) => s.avasPreset = v);
              },
              child: SettingsGroup(
                children: [
                  for (final preset in AvasPreset.values)
                    RadioListTile<AvasPreset>(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      title: Text(
                        preset.label,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        'Tono de ${preset.baseHz.toStringAsFixed(0)} a '
                        '${preset.maxHz.toStringAsFixed(0)} Hz según la '
                        'velocidad',
                        style: const TextStyle(color: subText, fontSize: 13),
                      ),
                      value: preset,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const SectionHeader('Volumen del motor'),
            SurfaceCard(
              child: Row(
                children: [
                  const Icon(Icons.volume_up_outlined, color: subText),
                  Expanded(
                    child: Slider(
                      value: settings.avasVolume,
                      onChanged: (v) =>
                          settings.update((s) => s.avasVolume = v),
                    ),
                  ),
                  Text(
                    '${(settings.avasVolume * 100).round()} %',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.shield_outlined, color: safetyAmber, size: 20),
                      SizedBox(width: 8),
                      Text('Seguridad primero',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 15.5)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'El sonido de motor solo suena rodando (velocidad '
                    'mayor que cero) y con la rueda conectada. Si salta '
                    'una alarma de velocidad, potencia, temperatura o '
                    'PWM, su volumen baja casi a silencio para que la '
                    'alarma se escuche siempre.',
                    style: TextStyle(color: subText, fontSize: 13.5),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    settings.avasEnabled
                        ? 'A 25 km/h tu preset sonaría a '
                            '${preview.frequencyHz.toStringAsFixed(0)} Hz '
                            'con volumen efectivo '
                            '${(preview.volume * 100).round()} %.'
                        : 'Activa el interruptor para habilitarlo.',
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 10),
                  const PillBadge('Motor de audio: básico', color: safetyAmber),
                  const SizedBox(height: 6),
                  const Text(
                    'La lógica de tonos y volúmenes está completa; el '
                    'reproductor de audio nativo se conecta en la '
                    'siguiente fase.',
                    style: TextStyle(color: subText, fontSize: 12.5),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
