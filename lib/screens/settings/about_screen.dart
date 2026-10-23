import 'package:flutter/material.dart';

import '../../app_info.dart';
import '../../theme.dart';
import '../../widgets/ui_kit.dart';
import 'settings_widgets.dart';

/// Configuración → Acerca de: identidad de la app, versión real,
/// librerías de terceros y créditos. Texto 100 % propio de
/// EUC OneWheel.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
      title: 'Acerca de',
      children: [
        Center(
          child: Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Image.asset('assets/logo.jpg',
                    width: 96, height: 96, fit: BoxFit.cover),
              ),
              const SizedBox(height: 14),
              Text(
                appName,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Versión: $appVersion (build $appBuild)',
                style: TextStyle(color: subText, fontSize: 15),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        const SectionHeader('Información'),
        SettingsGroup(
          children: [
            NavTile(
              title: 'Novedades de la versión 2',
              subtitle: 'La nueva base de la app',
              onTap: () => _info(
                  context,
                  'Novedades de la versión 2',
                  'Interfaz rediseñada por completo con identidad '
                      'propia: cluster digital sobre grafito azulado con '
                      'paneles de vidrio en capas, azul funcional como '
                      'acento de trabajo y el rojo de la marca solo como '
                      'luz dentro del tubo del velocímetro. Navegación '
                      'flotante de cinco secciones, panel de conducción '
                      'personalizable con medidor circular, alarmas '
                      'configurables, sonido de motor (AVAS) con presets, '
                      'mapa a pantalla completa con filtros, historial de '
                      'viajes con gráficos y exportación CSV, temas '
                      'oscuro, claro y negro puro, y la misma base '
                      'Bluetooth multimarca de siempre.'),
            ),
            NavTile(
              title: 'Rueda compatible',
              subtitle: 'InMotion · KingSong · Begode/Gotway · '
                  'Veteran/LeaperKim · Ninebot',
              onTap: () => _info(
                  context,
                  'Compatibilidad',
                  'EUC OneWheel detecta tu rueda automáticamente por '
                      'Bluetooth y trabaja con las marcas principales. La '
                      'telemetría y los controles se activan por marca '
                      'según su adaptador, siempre con la regla de '
                      'seguridad: ningún ajuste de marcha sin la rueda '
                      'detenida y tu confirmación.'),
            ),
            NavTile(
              title: 'Librerías de terceros',
              subtitle: 'Componentes abiertos que usa la app',
              onTap: () => _info(
                  context,
                  'Librerías de terceros',
                  'Flutter y Dart (Google), flutter_blue_plus '
                      '(Bluetooth LE), flutter_map y OpenStreetMap '
                      '(mapas), geolocator (GPS), latlong2, intl, '
                      'path_provider, permission_handler y share_plus. '
                      'Los mapas muestran la atribución '
                      '«© OpenStreetMap contributors».'),
            ),
            NavTile(
              title: 'Créditos',
              subtitle: 'Hecha para rodar',
              onTap: () => _info(
                  context,
                  'Créditos',
                  'EUC OneWheel es un producto original, diseñado y '
                      'desarrollado para la comunidad de rodadores de '
                      'monociclo eléctrico. Gracias por rodar con '
                      'nosotros.'),
            ),
          ],
        ),
      ],
    );
  }

  void _info(BuildContext context, String title, String body) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Listo'),
          ),
        ],
      ),
    );
  }
}
