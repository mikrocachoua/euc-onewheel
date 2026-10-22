import 'package:flutter/material.dart';

import '../models/ride.dart';
import '../services/ride_store.dart';
import '../theme.dart';
import '../utils/format.dart';
import 'ride_detail_screen.dart';

/// Historial de rodadas guardadas en el teléfono.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => HistoryScreenState();
}

class HistoryScreenState extends State<HistoryScreen> {
  final _store = RideStore();
  late Future<List<Ride>> _future;

  @override
  void initState() {
    super.initState();
    _future = _store.loadRides();
  }

  /// Recarga la lista (se llama al entrar a la pestaña y tras borrar).
  void reload() {
    setState(() {
      _future = _store.loadRides();
    });
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
      child: FutureBuilder<List<Ride>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final rides = snap.data ?? [];
          if (rides.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.route, size: 56, color: brandRed),
                    SizedBox(height: 16),
                    Text(
                      'Aún no tienes rodadas guardadas',
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Ve a la pestaña Rodar, pulsa "Iniciar rodada" y sal a '
                      'rodar: la ruta se graba con el GPS real del teléfono.',
                      style: TextStyle(color: Colors.white60),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => reload(),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: rides.length,
              itemBuilder: (context, i) => _rideCard(rides[i]),
            ),
          );
        },
      ),
    );
  }

  Widget _rideCard(Ride ride) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: brandRed.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(13),
          ),
          child: const Icon(Icons.route, color: brandRed),
        ),
        title: Text(
          '${ride.distanceKm.toStringAsFixed(2)} km',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          '${formatDateTime(ride.startedAt)} · '
          '${formatDuration(ride.duration)} · '
          'media ${ride.avgSpeedKmh.toStringAsFixed(1)} km/h',
          style: const TextStyle(color: Colors.white60),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.white38),
        onTap: () => _openDetail(ride),
      ),
    );
  }
}
