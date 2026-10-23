import 'package:flutter/material.dart';

import '../services/ble/wheel_connection_controller.dart';
import '../state/app_settings.dart';
import '../theme.dart';
import '../widgets/ui_kit.dart';
import 'settings/about_screen.dart';
import 'settings/application_screen.dart';
import 'settings/extras_screen.dart';
import 'settings/integrations_screen.dart';
import 'settings/privacy_screen.dart';
import 'settings/support_screen.dart';

/// Pestaña Configuración (base v2): menú principal con las
/// subpantallas de Aplicación, Privacidad, Tienda/Extras,
/// Integración, Soporte y Acerca de, más los accesos rápidos al modo
/// demo y al nombre del dispositivo.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.settings,
    this.controller,
  });

  final AppSettings settings;
  final WheelConnectionController? controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        return SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, tabBarClearance),
            children: [
              const Center(child: ScreenTitle('Configuración')),
              const SizedBox(height: 16),
              SettingsGroupCard(
                children: [
                  NavTile(
                    title: 'Aplicación',
                    subtitle: 'Panel, alarmas, sonido de motor, '
                        'apariencia y más',
                    icon: Icons.apps_outlined,
                    onTap: () => _push(
                      context,
                      ApplicationSettingsScreen(settings: settings),
                    ),
                  ),
                  NavTile(
                    title: 'Privacidad',
                    subtitle: 'Localización, perfil social y '
                        'clasificaciones',
                    icon: Icons.privacy_tip_outlined,
                    onTap: () => _push(
                      context,
                      PrivacyScreen(settings: settings),
                    ),
                  ),
                  NavTile(
                    title: 'Tienda',
                    subtitle: 'Todo lo que incluye EUC OneWheel',
                    icon: Icons.storefront_outlined,
                    onTap: () => _push(context, const ExtrasScreen()),
                  ),
                  NavTile(
                    title: 'Integración',
                    subtitle: 'Relojes, radar, lentes y comunidad',
                    icon: Icons.hub_outlined,
                    onTap: () => _push(context, const IntegrationsScreen()),
                  ),
                  NavTile(
                    title: 'Soporte',
                    subtitle: 'Ayuda y compartir registros',
                    icon: Icons.support_agent_outlined,
                    onTap: () => _push(
                      context,
                      SupportScreen(controller: controller),
                    ),
                  ),
                  NavTile(
                    title: 'Acerca de',
                    subtitle: 'Versión, información y créditos',
                    icon: Icons.info_outline,
                    onTap: () => _push(context, const AboutScreen()),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const SectionHeader('Tu rueda'),
              SettingsGroupCard(
                children: [
                  NavTile(
                    title: 'Nombre del dispositivo',
                    subtitle: settings.customDeviceName ??
                        'Ponle un nombre personalizado a tu rueda',
                    icon: Icons.badge_outlined,
                    onTap: () => _renameDevice(context),
                  ),
                  SwitchTile(
                    title: 'Modo demo',
                    subtitle: 'Explora la app con datos simulados, sin rueda '
                        'real',
                    value: settings.demoMode,
                    onChanged: (on) => settings.update((s) => s.demoMode = on),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Tarjeta de seguridad en ÁMBAR (el color de seguridad
              // de la identidad): fondo y borde teñidos de ámbar.
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: safetyAmber.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(cardRadius),
                  border: Border.all(
                    color: safetyAmber.withValues(alpha: 0.35),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.shield_outlined, color: safetyAmber, size: 22),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Regla de seguridad de EUC OneWheel: ningún '
                        'control puede apagar, bloquear o recalibrar tu '
                        'rueda en movimiento. Esos comandos solo salen '
                        'con la rueda detenida y tu confirmación.',
                        style: TextStyle(color: subText, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  Future<void> _renameDevice(BuildContext context) async {
    final textController =
        TextEditingController(text: settings.customDeviceName ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nombre del dispositivo'),
        content: TextField(
          controller: textController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Ej. Mi rueda',
            labelText: 'Nombre personalizado',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(''),
            child: const Text('Quitar nombre'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(textController.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (name == null) return;
    settings.update((s) => s.customDeviceName = name.isEmpty ? null : name);
  }
}

/// Tarjeta blanca que agrupa filas con divisores (versión para las
/// pestañas principales, fuera de las subpantallas de ajustes).
class SettingsGroupCard extends StatelessWidget {
  const SettingsGroupCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) rows.add(const Divider(height: 1));
      rows.add(children[i]);
    }
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Column(children: rows),
    );
  }
}
