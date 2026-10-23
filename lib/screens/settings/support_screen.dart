import 'package:flutter/material.dart';

import '../../theme.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/app_log.dart';
import '../../services/ble/wheel_connection_controller.dart';
import '../../widgets/ui_kit.dart';
import 'settings_widgets.dart';

/// Configuración → Soporte: canal de ayuda y «Compartir registros»
/// (exporta el registro de la app junto con la auditoría de la
/// compuerta de seguridad, sin ningún dato de cuentas).
class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key, this.controller});

  final WheelConnectionController? controller;

  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
      title: 'Soporte',
      children: [
        SettingsGroup(
          children: [
            NavTile(
              title: 'Canal de soporte',
              subtitle: 'Informar de un error o solicitar una función',
              icon: Icons.support_agent_outlined,
              onTap: () => _shareLogs(context, support: true),
            ),
            NavTile(
              title: 'Compartir registros',
              subtitle: 'Exporta el registro de la app para revisarlo',
              icon: Icons.ios_share_outlined,
              onTap: () => _shareLogs(context, support: false),
            ),
          ],
        ),
        const SizedBox(height: 14),
        const SurfaceCard(
          child: Text(
            'El registro solo contiene eventos de la app (escaneos, '
            'conexiones, alarmas del panel y el historial de comandos '
            'que la compuerta de seguridad dejó salir). No incluye '
            'cuentas, contraseñas ni tus rutas.',
            style: TextStyle(color: subText, fontSize: 13.5),
          ),
        ),
      ],
    );
  }

  void _shareLogs(BuildContext context, {required bool support}) {
    final gate = controller?.safetyGate;
    final extra = StringBuffer();
    if (gate != null && gate.log.isNotEmpty) {
      extra.writeln('Comandos autorizados por la compuerta de seguridad:');
      for (final entry in gate.log) {
        extra.writeln('${entry.at.toIso8601String()} · ${entry.command.name} · '
            'velocidad ${entry.speedKmh} km/h');
      }
    }
    SharePlus.instance.share(
      ShareParams(
        text: AppLog.instance.exportText(extra: extra.toString()),
        subject: support
            ? 'EUC OneWheel — reporte para soporte'
            : 'EUC OneWheel — registro de la app',
      ),
    );
  }
}
