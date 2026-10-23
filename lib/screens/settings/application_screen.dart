import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../state/app_settings.dart';
import '../../widgets/ui_kit.dart';
import 'alarms_screen.dart';
import 'avas_screen.dart';
import 'data_screen.dart';
import 'panel_config_screen.dart';
import 'settings_widgets.dart';

/// Configuración → Aplicación: panel personalizado, grabador de
/// video, volumen automático, sonido de motor, grabación automática
/// de GPS, apariencia, introducción y más opciones. Todo persiste.
class ApplicationSettingsScreen extends StatelessWidget {
  const ApplicationSettingsScreen({super.key, required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        return SettingsScaffold(
          title: 'Aplicación',
          children: [
            const SectionHeader('Panel personalizado'),
            SettingsGroup(
              children: [
                NavTile(
                  title: 'Panel personalizado',
                  subtitle: 'Seleccionar indicadores para mostrar y ajustar '
                      'el tamaño',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PanelConfigScreen(settings: settings),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const SectionHeader('Alarmas'),
            SettingsGroup(
              children: [
                NavTile(
                  title: 'Alarmas',
                  subtitle: 'Por velocidad, amperaje, potencia, temperatura '
                      'y PWM',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AlarmsScreen(settings: settings),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const SectionHeader('Grabador de video'),
            SettingsGroup(
              children: [
                NavTile(
                  title: 'Grabador de video',
                  subtitle: 'Graba desde la cámara con las métricas '
                      'superpuestas',
                  trailing: const PillBadge('En desarrollo'),
                  onTap: () => _inDevelopment(
                      context,
                      'Grabador de video',
                      'Grabará video desde la cámara del teléfono con la '
                          'velocidad, la batería y la ruta superpuestas, '
                          'listo para compartir.'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const SectionHeader('Volumen automático'),
            SettingsGroup(
              children: [
                SwitchTile(
                  title: 'Volumen automático',
                  subtitle: 'El volumen de la música dependerá de la velocidad',
                  value: settings.autoVolume,
                  onChanged: (on) => settings.update((s) => s.autoVolume = on),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const SectionHeader('Sonido de motor'),
            SettingsGroup(
              children: [
                NavTile(
                  title: 'Sonido de motor',
                  subtitle: 'Sistema de alerta acústica de vehículo (AVAS) '
                      'con presets',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AvasScreen(settings: settings),
                    ),
                  ),
                ),
                SwitchTile(
                  title: 'Beep personalizado',
                  subtitle: 'Reemplaza el pitido de aviso de la app',
                  value: settings.customBeep,
                  onChanged: (on) => settings.update((s) => s.customBeep = on),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const SectionHeader('Grabación automática de seguimiento GPS'),
            SettingsGroup(
              children: [
                SwitchTile(
                  title: 'Grabación automática de seguimiento GPS',
                  subtitle: 'La grabación del recorrido puede reducir la '
                      'duración de la batería de tu teléfono',
                  value: settings.autoGpsRecording,
                  onChanged: (on) =>
                      settings.update((s) => s.autoGpsRecording = on),
                ),
                SwitchTile(
                  title: 'Modo demo',
                  subtitle: 'Explora la app con datos simulados, sin rueda '
                      'real conectada',
                  value: settings.demoMode,
                  onChanged: (on) => settings.update((s) => s.demoMode = on),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const SectionHeader('Apariencia'),
            SettingsGroup(
              children: [
                SwitchTile(
                  title: 'Sistema Imperial',
                  subtitle: 'Usar millas en lugar de kilómetros',
                  value: settings.imperial,
                  onChanged: (on) => settings.update((s) => s.imperial = on),
                ),
                _segmentedRow(
                  title: 'Unidad de temperatura',
                  options: const [(false, '°C'), (true, '°F')],
                  selected: settings.tempFahrenheit,
                  onChanged: (v) =>
                      settings.update((s) => s.tempFahrenheit = v),
                ),
                _segmentedRow(
                  title: 'Unidad de presión',
                  options: const [(false, 'bar'), (true, 'psi')],
                  selected: settings.pressurePsi,
                  onChanged: (v) => settings.update((s) => s.pressurePsi = v),
                ),
                ChoiceTile<AppThemeChoice>(
                  title: 'Tema',
                  valueLabel: settings.themeChoice.label,
                  options: [
                    for (final t in AppThemeChoice.values) (t, t.label),
                  ],
                  current: settings.themeChoice,
                  onChanged: (v) => settings.update((s) => s.themeChoice = v),
                ),
                SwitchTile(
                  title: 'Introducción',
                  subtitle: 'Mostrando consejos y novedades durante el '
                      'arranque de la app',
                  value: settings.showIntroTips,
                  onChanged: (on) =>
                      settings.update((s) => s.showIntroTips = on),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const SectionHeader('Otro'),
            SettingsGroup(
              children: [
                SwitchTile(
                  title: 'Bloqueo de orientación',
                  subtitle: 'Bloquear cambios en la orientación de la pantalla',
                  value: settings.lockOrientation,
                  onChanged: (on) {
                    settings.update((s) => s.lockOrientation = on);
                    SystemChrome.setPreferredOrientations(
                      on
                          ? [DeviceOrientation.portraitUp]
                          : DeviceOrientation.values,
                    );
                  },
                ),
                SwitchTile(
                  title: 'Permanecer siempre encendido',
                  subtitle: 'No permitir que la pantalla del dispositivo se '
                      'apague mientras la app está abierta',
                  value: settings.keepAwake,
                  onChanged: (on) => settings.update((s) => s.keepAwake = on),
                ),
                ChoiceTile<int>(
                  title: 'Reset automático de ruta',
                  subtitle: 'Un nuevo viaje comenzará tras la cuenta atrás',
                  valueLabel: settings.autoTripResetHours == 0
                      ? 'Nunca'
                      : '${settings.autoTripResetHours} h',
                  options: const [
                    (0, 'Nunca'),
                    (2, '2 h'),
                    (4, '4 h'),
                    (6, '6 h'),
                    (12, '12 h'),
                    (24, '24 h'),
                  ],
                  current: settings.autoTripResetHours,
                  onChanged: (v) =>
                      settings.update((s) => s.autoTripResetHours = v),
                ),
                NavTile(
                  title: 'Datos de la app',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AppDataScreen()),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _segmentedRow({
    required String title,
    required List<(bool, String)> options,
    required bool selected,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(title,
                style: const TextStyle(
                    fontSize: 16.5, fontWeight: FontWeight.w700)),
          ),
          SegmentedChoice<bool>(
            options: options,
            selected: selected,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  void _inDevelopment(BuildContext context, String title, String body) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text('$body\n\nEsta función está en desarrollo en la '
            'base v2; llegará en una fase posterior, sin fecha '
            'prometida.'),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }
}
