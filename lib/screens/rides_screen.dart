import 'package:flutter/material.dart';

import '../models/ride.dart';
import '../services/ride_store.dart';
import '../state/app_settings.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../utils/units.dart';
import '../widgets/ui_kit.dart';
import 'ride_detail_screen.dart';
import 'ride_screen.dart';

/// Pestaña Viajes (base v2): historial de rodadas con tarjetas
/// completas (fecha, distancia, duración, velocidad media y máxima),
/// acceso directo a grabar una rodada nueva con GPS y el aviso de la
/// grabación automática cuando está activada.
class RidesScreen extends StatefulWidget {
  const RidesScreen({super.key, required this.settings});

  final AppSettings settings;

  @override
  State<RidesScreen> createState() => RidesScreenState();
}

class RidesScreenState extends State<RidesScreen> {
  final _store = RideStore();
  late Future<List<Ride>> _future;

  @override
  void initState() {
    super.initState();
    _future = _store.loadRides();
  }

  /// Recarga la lista (se llama al entrar a la pestaña).
  void reload() {
    setState(() {
      _future = _store.loadRides();
    });
  }

  Future<void> _openRecorder() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const Scaffold(body: RideScreen()),
      ),
    );
    reload();
  }

  Future<void> _openDetail(Ride ride) async {
    final deleted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => RideDetailScreen(ride: ride)),
    );
    if (deleted == true) reload();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Column(
              children: [
                const Center(child: ScreenTitle('Viajes')),
                const SizedBox(height: 14),
                SurfaceCard(
                  glassBlur: true,
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const GlassIconTile(
                        icon: Icons.play_circle_fill,
                        iconSize: 28,
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Grabar una rodada',
                                style: TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w800)),
                            SizedBox(height: 3),
                            Text(
                              'Ruta en el mapa con el GPS real del '
                              'teléfono y resumen completo al terminar.',
                              style: TextStyle(color: subText, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      PillButton(label: 'Rodar', onPressed: _openRecorder),
                    ],
                  ),
                ),
                if (widget.settings.autoGpsRecording) ...[
                  const SizedBox(height: 10),
                  const Row(
                    children: [
                      Icon(Icons.gps_fixed, color: safetyAmber, size: 16),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Grabación automática de GPS activada: el '
                          'seguimiento puede reducir la batería del '
                          'teléfono.',
                          style: TextStyle(color: subText, fontSize: 12.5),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Expanded(child: _historyList()),
        ],
      ),
    );
  }

  Widget _historyList() {
    return FutureBuilder<List<Ride>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final rides = snap.data ?? [];
        if (rides.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.route, size: 56, color: subText),
                const SizedBox(height: 16),
                Text(
                  'Aún no tienes viajes guardados',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurface),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Pulsa «Rodar» y sal a rodar: la ruta se graba con el '
                  'GPS real del teléfono y quedará aquí, en tu '
                  'historial.',
                  style: TextStyle(color: subText),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () async => reload(),
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, tabBarClearance),
            itemCount: rides.length,
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _rideCard(rides[i]),
            ),
          ),
        );
      },
    );
  }

  Widget _rideCard(Ride ride) {
    final s = widget.settings;
    final dist = displayDistanceKm(ride.distanceKm, imperial: s.imperial);
    final avg = displaySpeed(ride.avgSpeedKmh, imperial: s.imperial);
    final max = displaySpeed(ride.maxSpeedKmh, imperial: s.imperial);
    final unit = distanceUnit(imperial: s.imperial);
    final sUnit = speedUnit(imperial: s.imperial);
    return SurfaceCard(
      padding: const EdgeInsets.all(16),
      onTap: () => _openDetail(ride),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const GlassIconTile(
                icon: Icons.route,
                size: 46,
                iconSize: 23,
                radius: 13,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${dist.toStringAsFixed(2)} $unit',
                      style: const TextStyle(
                          fontSize: 19, fontWeight: FontWeight.w800),
                    ),
                    Text(
                      formatDateTime(ride.startedAt),
                      style: const TextStyle(color: subText, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: subText),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _miniStat('Duración', formatDuration(ride.duration)),
              _miniStat('Media', '${avg.toStringAsFixed(1)} $sUnit'),
              _miniStat('Máxima', '${max.toStringAsFixed(1)} $sUnit'),
              _miniStat('Desnivel',
                  '+${ride.elevationGainMeters.toStringAsFixed(0)} m'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value,
            style:
                const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
        Text(label, style: const TextStyle(color: subText, fontSize: 11.5)),
      ],
    );
  }
}
