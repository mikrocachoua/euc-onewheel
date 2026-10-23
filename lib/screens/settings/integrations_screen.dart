import 'package:flutter/material.dart';

import '../../theme.dart';

import '../../widgets/ui_kit.dart';
import 'settings_widgets.dart';

/// Configuración → Integración: lista de integraciones con otros
/// dispositivos y servicios. Las no implementadas se marcan
/// «Próximamente», sin excepción.
class IntegrationsScreen extends StatelessWidget {
  const IntegrationsScreen({super.key});

  static const _items = <(IconData, String, String)>[
    (
      Icons.groups_outlined,
      'electro.club',
      'Comunidad de rodadores: comparte rutas y rodadas'
    ),
    (Icons.mic_outlined, 'Siri Shortcuts', 'Controla la app con atajos de voz'),
    (Icons.watch_outlined, 'Reloj Garmin', 'Ve tu telemetría en la muñeca'),
    (
      Icons.radar_outlined,
      'Garmin Varia',
      'Radar trasero de tráfico en tus rodadas'
    ),
    (
      Icons.visibility_outlined,
      'Espejo «Third Eye»',
      'Espejo inteligente para rodar más seguro'
    ),
    (
      Icons.smart_display_outlined,
      'ActiveLook',
      'Lentes con pantalla de datos en vivo'
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
      title: 'Integración',
      children: [
        SettingsGroup(
          children: [
            for (final (icon, title, subtitle) in _items)
              NavTile(
                title: title,
                subtitle: subtitle,
                icon: icon,
                trailing: const PillBadge('Próximamente'),
                onTap: () => _soon(context, title),
              ),
          ],
        ),
        const SizedBox(height: 14),
        const SurfaceCard(
          child: Text(
            'Las integraciones se activarán por fases y solo se '
            'anunciarán como disponibles cuando funcionen de verdad.',
            style: TextStyle(color: subText, fontSize: 13.5),
          ),
        ),
      ],
    );
  }

  void _soon(BuildContext context, String title) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('«$title» llegará próximamente.')),
    );
  }
}
