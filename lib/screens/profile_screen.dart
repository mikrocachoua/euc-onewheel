import 'package:flutter/material.dart';

import '../services/ble/wheel_connection_controller.dart';
import '../state/app_settings.dart';
import '../theme.dart';
import '../widgets/ui_kit.dart';

/// Pestaña Perfil (base v2): tarjeta del rodador con avatar de
/// iniciales, nombre y ciudad, botón de edición, contadores sociales
/// y la fila de su dispositivo con la batería.
///
/// Con una rueda real conectada, la fila muestra esa rueda y su
/// batería en vivo; en modo demo muestra una rueda de demostración
/// genérica. La app es multimarca y no se enfoca en ningún modelo
/// en especial: nada aquí está fijo a una marca concreta.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    super.key,
    required this.settings,
    this.controller,
  });

  final AppSettings settings;
  final WheelConnectionController? controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        settings,
        if (controller != null) controller!,
      ]),
      builder: (context, _) {
        return SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, tabBarClearance),
            children: [
              Row(
                children: [
                  const SizedBox(width: 48),
                  const Expanded(child: Center(child: ScreenTitle('Perfil'))),
                  CircleIconButton(
                    icon: Icons.more_horiz,
                    tooltip: 'Más opciones',
                    onTap: () => _moreOptions(context),
                  ),
                ],
              ),
              const SizedBox(height: 34),
              _profileCard(context),
              const SizedBox(height: 14),
              _socialCard(),
              const SizedBox(height: 14),
              SurfaceCard(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                child: NavTile(
                  title: 'Valoración',
                  onTap: () => _snack(
                      context,
                      'Tu valoración de rodador se construye con tus '
                      'viajes guardados.'),
                ),
              ),
              const SizedBox(height: 14),
              _deviceCard(),
            ],
          ),
        );
      },
    );
  }

  Widget _profileCard(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        SurfaceCard(
          glassBlur: true,
          padding: const EdgeInsets.fromLTRB(18, 56, 18, 18),
          child: Column(
            children: [
              const Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text('25 días atrás',
                      style: TextStyle(color: subText, fontSize: 12.5)),
                ],
              ),
              const Text(
                'Ricardo Cachoúa',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 3),
              const Text('México, Cancún',
                  style: TextStyle(color: subText, fontSize: 15)),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  gradient: iconTileGradient(),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: funcBlue.withValues(alpha: 0.35)),
                ),
                child: const Center(
                  child: Text(
                    'EDITAR PERFIL',
                    style: TextStyle(
                      color: funcBlueLight,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Positioned(
          top: -26,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: surfaceDark,
                border: Border.all(color: surfaceBorder),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Center(
                child: Text(
                  'RC',
                  style: TextStyle(
                    color: funcBlue,
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _socialCard() {
    return const SurfaceCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                Text('0',
                    style:
                        TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                SizedBox(height: 2),
                Text('Amigos', style: TextStyle(fontSize: 15.5)),
              ],
            ),
          ),
          SizedBox(
            height: 44,
            child: VerticalDivider(color: surfaceBorder, thickness: 1),
          ),
          Expanded(
            child: Column(
              children: [
                Text('0',
                    style:
                        TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                SizedBox(height: 2),
                Text('Seguidores', style: TextStyle(fontSize: 15.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _deviceCard() {
    final ctrl = controller;
    String name;
    String? battery;
    if (ctrl != null && ctrl.state == WheelLinkState.connected) {
      name = settings.customDeviceName ??
          ctrl.identity.model ??
          ctrl.identity.brand.label;
      final pct = ctrl.telemetry.batteryPct;
      battery = pct != null ? '$pct%' : null;
    } else if (settings.demoMode) {
      // Ejemplo genérico del modo demo: ninguna marca en especial.
      name = settings.customDeviceName ?? 'Rueda de demostración';
      battery = '46%';
    } else {
      name = settings.customDeviceName ?? 'Sin rueda conectada';
      battery = null;
    }
    return SurfaceCard(
      glassBlur: true,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Row(
        children: [
          const Text('Dispositivo',
              style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: subText, fontSize: 15.5, fontWeight: FontWeight.w700),
            ),
          ),
          if (battery != null) ...[
            const SizedBox(width: 8),
            Text(battery,
                style: const TextStyle(color: subText, fontSize: 15.5)),
          ],
        ],
      ),
    );
  }

  void _moreOptions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Editar perfil'),
              onTap: () => Navigator.of(ctx).pop(),
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: const Text('Compartir perfil'),
              onTap: () => Navigator.of(ctx).pop(),
            ),
          ],
        ),
      ),
    );
  }

  void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
