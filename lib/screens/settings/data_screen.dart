import 'package:flutter/material.dart';

import '../../app_info.dart';
import '../../services/app_log.dart';
import '../../services/ride_store.dart';
import '../../theme.dart';
import '../../widgets/ui_kit.dart';

/// Datos de la app: cuántas rodadas guarda el teléfono, versión y
/// limpieza del registro de eventos de la sesión.
class AppDataScreen extends StatefulWidget {
  const AppDataScreen({super.key});

  @override
  State<AppDataScreen> createState() => _AppDataScreenState();
}

class _AppDataScreenState extends State<AppDataScreen> {
  int? _rideCount;

  @override
  void initState() {
    super.initState();
    RideStore().loadRides().then((rides) {
      if (mounted) setState(() => _rideCount = rides.length);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _header(context),
              const SizedBox(height: 16),
              SurfaceCard(
                child: Column(
                  children: [
                    _row('Versión de la app', '$appVersion (build $appBuild)'),
                    const Divider(),
                    _row(
                      'Rodadas guardadas en este teléfono',
                      _rideCount == null ? '…' : '$_rideCount',
                    ),
                    const Divider(),
                    _row(
                      'Eventos en el registro de esta sesión',
                      '${AppLog.instance.entries.length}',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Tus datos viven en tu teléfono',
                      style:
                          TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Las rodadas se guardan como un archivo en los '
                      'datos de la app y los ajustes en otro. Nada sale '
                      'del dispositivo salvo que tú lo compartas.',
                      style: TextStyle(color: subText, fontSize: 13.5),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () {
                        AppLog.instance.clear();
                        setState(() {});
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Registro de la sesión borrado.')),
                        );
                      },
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Borrar registro de la sesión'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Row(
      children: [
        CircleIconButton(
          icon: Icons.arrow_back_ios_new,
          onTap: () => Navigator.of(context).pop(),
        ),
        const Expanded(child: Center(child: ScreenTitle('Datos de la app'))),
        const SizedBox(width: 48),
      ],
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 15.5)),
          ),
          Text(value,
              style:
                  const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
        ],
      ),
    );
  }
}
