import 'package:flutter/material.dart';

import '../../theme.dart';

import '../../state/app_settings.dart';
import '../../widgets/ui_kit.dart';
import 'settings_widgets.dart';

/// Configuración → Privacidad: quién puede ver tu localización y tu
/// perfil social, precisión y actualización de ubicación en segundo
/// plano, y participación en clasificaciones. Todo persiste.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key, required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        return SettingsScaffold(
          title: 'Privacidad',
          children: [
            SettingsGroup(
              children: [
                ChoiceTile<VisibilityChoice>(
                  title: 'Quién puede ver su localización',
                  valueLabel: settings.locationVisibility.label,
                  options: [
                    for (final v in VisibilityChoice.values) (v, v.label),
                  ],
                  current: settings.locationVisibility,
                  onChanged: (v) =>
                      settings.update((s) => s.locationVisibility = v),
                ),
                ChoiceTile<VisibilityChoice>(
                  title: 'Quién puede ver tu perfil social',
                  valueLabel: settings.profileVisibility.label,
                  options: [
                    for (final v in VisibilityChoice.values) (v, v.label),
                  ],
                  current: settings.profileVisibility,
                  onChanged: (v) =>
                      settings.update((s) => s.profileVisibility = v),
                ),
                SwitchTile(
                  title: 'Precisión de localización mejorada',
                  subtitle: 'Incrementa el consumo de batería',
                  value: settings.enhancedLocationPrecision,
                  onChanged: (on) =>
                      settings.update((s) => s.enhancedLocationPrecision = on),
                ),
                SwitchTile(
                  title: 'Usar actualización de ubicación en segundo plano',
                  subtitle: 'Es necesario para que el rastreador funcione '
                      'correctamente y actualice la ruta',
                  value: settings.backgroundLocation,
                  onChanged: (on) =>
                      settings.update((s) => s.backgroundLocation = on),
                ),
                SwitchTile(
                  title: 'Participación en clasificaciones',
                  value: settings.leaderboards,
                  onChanged: (on) =>
                      settings.update((s) => s.leaderboards = on),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const SurfaceCard(
              child: Text(
                'Tu ubicación solo se usa para grabar tus rutas y '
                'mostrarte en el mapa. Estos ajustes definen qué se '
                'comparte cuando uses las funciones sociales de la '
                'app; nada se publica sin que lo pidas.',
                style: TextStyle(color: subText, fontSize: 13.5),
              ),
            ),
          ],
        );
      },
    );
  }
}
