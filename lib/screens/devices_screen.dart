import 'package:flutter/material.dart';

import '../models/wheel_identity.dart';
import '../services/app_log.dart';
import '../services/ble/wheel_connection_controller.dart';
import '../services/demo_data.dart';
import '../state/app_settings.dart';
import '../theme.dart';
import '../widgets/ui_kit.dart';
import 'panel_screen.dart';
import 'settings/data_screen.dart';

/// Pestaña Dispositivos (base v2): encabezado con el logo y el
/// distintivo «Demo» cuando no hay rueda real, acceso a los datos de
/// la app y la lista «ENCONTRADO» de dispositivos Bluetooth cercanos.
///
/// El escaneo y la conexión son los reales de la base Bluetooth: al
/// conectar, la app detecta la marca por su huella GATT y la primera
/// trama (InMotion, KingSong, Begode/Gotway, Veteran/LeaperKim,
/// Ninebot). En modo demo se muestran ejemplos del entorno y el panel
/// funciona con datos simulados.
class DevicesScreen extends StatelessWidget {
  const DevicesScreen({
    super.key,
    required this.controller,
    required this.settings,
  });

  final WheelConnectionController controller;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([controller, settings]),
      builder: (context, _) {
        final demo =
            settings.demoMode && controller.state != WheelLinkState.connected;
        return SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, tabBarClearance),
            children: [
              _header(context, demo),
              const SizedBox(height: 10),
              if (controller.state == WheelLinkState.connected)
                _connectedCard(context)
              else if (demo)
                _demoCard(context)
              else
                _scanCard(context),
              const SectionHeader('Encontrado'),
              if (demo) _demoList(context) else _realList(context),
              const SizedBox(height: 8),
              _brandsNote(),
            ],
          ),
        );
      },
    );
  }

  Widget _header(BuildContext context, bool demo) {
    return Row(
      children: [
        CircleIconButton(
          icon: Icons.storage_outlined,
          tooltip: 'Datos de la app',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AppDataScreen()),
          ),
        ),
        const Expanded(child: Center(child: ScreenTitle('EUC OneWheel'))),
        if (demo)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white24),
            ),
            child: const Text(
              'Demo',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
          )
        else
          const SizedBox(width: 48),
      ],
    );
  }

  // — Estado conectado (rueda real) ————————————————

  Widget _connectedCard(BuildContext context) {
    final identity = controller.identity;
    final hasAdapter = controller.adapter != null;
    final title = settings.customDeviceName ??
        identity.model ??
        (identity.brand != WheelBrand.unknown
            ? identity.brand.label
            : (identity.advertisedName ?? 'Rueda conectada'));
    return SurfaceCard(
      glassBlur: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bluetooth_connected, color: funcBlue, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 17)),
              ),
              const PillBadge('CONECTADA', color: funcBlueLight),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            hasAdapter
                ? 'Recibiendo telemetría en vivo de tu rueda.'
                : 'Marca detectada: ${identity.brand.label}. Su adaptador '
                    'de telemetría está en desarrollo: la app ya sabe qué '
                    'rueda es, y sus datos se activarán en cuanto el '
                    'adaptador de esta marca esté implementado.',
            style: const TextStyle(color: subText, fontSize: 13.5),
          ),
          if (identity.serial != null) ...[
            const SizedBox(height: 4),
            Text('Serie: ${identity.serial}',
                style: const TextStyle(color: subText, fontSize: 12.5)),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              PillButton(
                label: 'Ver panel',
                onPressed: () => _openPanel(context),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: () {
                  AppLog.instance.add('Rueda desconectada por el usuario');
                  controller.disconnect();
                },
                icon: const Icon(Icons.bluetooth_disabled, size: 18),
                label: const Text('Desconectar'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // — Modo demo ————————————————————————————————

  Widget _demoCard(BuildContext context) {
    return SurfaceCard(
      glassBlur: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.science_outlined, color: funcBlue, size: 22),
              SizedBox(width: 8),
              Expanded(
                child: Text('Modo demo activo',
                    style:
                        TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Estás explorando la app con datos simulados, sin una rueda '
            'real. El panel de conducción, las alarmas y el sonido de '
            'motor funcionan igual que con tu rueda conectada.',
            style: TextStyle(color: subText, fontSize: 13.5),
          ),
          const SizedBox(height: 14),
          PillButton(
            label: 'Abrir panel demo',
            onPressed: () => _openPanel(context),
          ),
        ],
      ),
    );
  }

  Widget _demoList(BuildContext context) {
    return Column(
      children: [
        for (final device in demoEnvironmentDevices)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _deviceCard(
              name: device.name,
              onConnect: device.isWheel
                  ? () => _openPanel(context)
                  : () => _snack(context,
                      'En el modo demo solo la rueda de ejemplo abre el panel.'),
            ),
          ),
      ],
    );
  }

  // — Escaneo real ———————————————————————————————

  Widget _scanCard(BuildContext context) {
    final state = controller.state;
    final scanning = state == WheelLinkState.scanning;
    final connecting = state == WheelLinkState.connecting;
    return SurfaceCard(
      glassBlur: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.bluetooth, color: funcBlue, size: 22),
              SizedBox(width: 8),
              Text('Conectar mi rueda',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Enciende tu rueda y búscala: la app detecta '
            'automáticamente su marca y modelo por Bluetooth.',
            style: TextStyle(color: subText, fontSize: 13.5),
          ),
          if (controller.errorMessage != null) ...[
            const SizedBox(height: 10),
            Text(
              controller.errorMessage!,
              style: const TextStyle(color: safetyAmber, fontSize: 13),
            ),
          ],
          const SizedBox(height: 14),
          if (connecting)
            const Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                SizedBox(width: 10),
                Text('Conectando con la rueda…',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ],
            )
          else if (scanning)
            OutlinedButton.icon(
              onPressed: () => controller.stopScan(),
              icon: const Icon(Icons.stop_circle_outlined, size: 18),
              label: const Text('Detener búsqueda'),
            )
          else
            Row(
              children: [
                PillButton(
                  label: controller.permissionBlocked ? 'Reintentar' : 'Buscar',
                  onPressed: () {
                    AppLog.instance.add('Escaneo Bluetooth iniciado');
                    controller.startScan();
                  },
                ),
                if (controller.permissionBlocked) ...[
                  const SizedBox(width: 10),
                  OutlinedButton(
                    onPressed: () => controller.openPermissionSettings(),
                    child: const Text('Abrir ajustes'),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }

  Widget _realList(BuildContext context) {
    final devices = controller.foundDevices;
    if (controller.state == WheelLinkState.scanning && devices.isEmpty) {
      return const SurfaceCard(
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Buscando dispositivos cercanos… acércate a tu rueda '
                'encendida.',
                style: TextStyle(color: subText, fontSize: 13.5),
              ),
            ),
          ],
        ),
      );
    }
    if (devices.isEmpty) {
      return const SurfaceCard(
        child: Text(
          'Todavía no se ha encontrado ningún dispositivo. Pulsa '
          '«Buscar» con tu rueda encendida y cerca del teléfono. La '
          'marca de cada rueda se detecta al conectar.',
          style: TextStyle(color: subText, fontSize: 13.5),
        ),
      );
    }
    return Column(
      children: [
        for (final device in devices)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _deviceCard(
              name: device.displayName,
              subtitle: 'Señal ${device.rssi} dBm',
              onConnect: () {
                AppLog.instance.add('Conectando con ${device.displayName}');
                controller.connect(device);
              },
            ),
          ),
      ],
    );
  }

  /// Tarjeta de un dispositivo encontrado: icono Bluetooth con
  /// ondas, nombre, «0 conexiones» y botón píldora «Conectar».
  Widget _deviceCard({
    required String name,
    String? subtitle,
    required VoidCallback onConnect,
  }) {
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          const Icon(Icons.bluetooth_audio, color: subText, size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                      fontSize: 16.5, fontWeight: FontWeight.w800),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle ?? '0 conexiones',
                  style: const TextStyle(color: subText, fontSize: 13.5),
                ),
              ],
            ),
          ),
          PillButton(label: 'Conectar', onPressed: onConnect),
        ],
      ),
    );
  }

  Widget _brandsNote() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: iconTileGradient(),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: const Row(
        children: [
          Icon(Icons.verified_outlined, color: funcBlueLight),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Compatible con las marcas principales: InMotion, '
              'KingSong, Begode/Gotway, Veteran/LeaperKim y Ninebot. '
              'La detección es automática y multimarca.',
              style: TextStyle(fontSize: 13, color: inkText),
            ),
          ),
        ],
      ),
    );
  }

  void _openPanel(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          body: AppBackground(
            child: PanelScreen(
              controller: controller,
              settings: settings,
            ),
          ),
        ),
      ),
    );
  }

  void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
