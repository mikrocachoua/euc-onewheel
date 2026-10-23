import 'package:flutter/material.dart';

import '../../theme.dart';

import '../../state/app_settings.dart';
import '../../widgets/ui_kit.dart';
import 'settings_widgets.dart';

/// Filtros del mapa: qué rodadores/dispositivos se muestran. Se
/// guardan en los ajustes de la app.
class MapFiltersScreen extends StatelessWidget {
  const MapFiltersScreen({super.key, required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        return SettingsScaffold(
          title: 'Filtrar',
          children: [
            SettingsGroup(
              children: [
                SwitchTile(
                  title: 'Solo Amigos',
                  value: settings.mapFriendsOnly,
                  onChanged: (on) =>
                      settings.update((s) => s.mapFriendsOnly = on),
                ),
                SwitchTile(
                  title: 'Solo en línea',
                  value: settings.mapOnlineOnly,
                  onChanged: (on) =>
                      settings.update((s) => s.mapOnlineOnly = on),
                ),
                SwitchTile(
                  title: 'Solo con el dispositivo conectado',
                  value: settings.mapConnectedOnly,
                  onChanged: (on) =>
                      settings.update((s) => s.mapConnectedOnly = on),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const SurfaceCard(
              child: Text(
                'Los filtros se aplican a los rodadores que la app '
                'muestra sobre el mapa. Tu propia ubicación siempre se '
                've.',
                style: TextStyle(color: subText, fontSize: 13.5),
              ),
            ),
          ],
        );
      },
    );
  }
}
