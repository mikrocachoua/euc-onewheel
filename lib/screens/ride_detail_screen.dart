import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';

import '../models/ride.dart';
import '../services/ride_store.dart';
import '../theme.dart';
import '../utils/format.dart';

/// Detalle de una rodada: mapa con su ruta y estadísticas completas.
class RideDetailScreen extends StatelessWidget {
  final Ride ride;

  const RideDetailScreen({super.key, required this.ride});

  String get _shareText =>
      'EUC OneWheel — Rodada ${formatDate(ride.startedAt)}\n'
      'Distancia: ${ride.distanceKm.toStringAsFixed(2)} km\n'
      'Duración: ${formatDuration(ride.duration)}\n'
      'Velocidad media: ${ride.avgSpeedKmh.toStringAsFixed(1)} km/h · '
      'Máxima: ${ride.maxSpeedKmh.toStringAsFixed(1)} km/h\n'
      'Desnivel positivo: +${ride.elevationGainMeters.toStringAsFixed(0)} m';

  Future<void> _delete(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Borrar esta rodada?'),
        content: const Text('Se eliminará del historial de este teléfono.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await RideStore().deleteRide(ride.id);
    if (context.mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final pts = ride.points.map((p) => LatLng(p.lat, p.lng)).toList();
    final hasRoute = pts.isNotEmpty;
    final center = hasRoute
        ? pts[pts.length ~/ 2]
        : const LatLng(21.1619, -86.8515); // Cancún por defecto

    return Scaffold(
      appBar: AppBar(
        title: Text('Rodada · ${formatDate(ride.startedAt)}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'Compartir resumen',
            onPressed: () => SharePlus.instance.share(
              ShareParams(text: _shareText),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Borrar rodada',
            onPressed: () => _delete(context),
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 300,
            child: FlutterMap(
              options: MapOptions(
                initialCenter: center,
                initialZoom: 15,
                initialCameraFit: pts.length > 1
                    ? CameraFit.bounds(
                        bounds: LatLngBounds.fromPoints(pts),
                        padding: const EdgeInsets.all(28),
                      )
                    : null,
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.euconewheel.euc_onewheel',
                ),
                if (pts.length > 1)
                  PolylineLayer(
                    polylines: [
                      Polyline(points: pts, color: brandRed, strokeWidth: 4.5),
                    ],
                  ),
                if (hasRoute)
                  MarkerLayer(
                    markers: [
                      _dot(pts.first, Colors.green),
                      if (pts.length > 1) _dot(pts.last, brandRed),
                    ],
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  '${ride.distanceKm.toStringAsFixed(2)} km',
                  style: const TextStyle(
                      fontSize: 36, fontWeight: FontWeight.w800),
                ),
                Text(
                  formatDateTime(ride.startedAt),
                  style: const TextStyle(color: Colors.white60),
                ),
                const SizedBox(height: 16),
                _row('Duración', formatDuration(ride.duration)),
                _row('Velocidad media',
                    '${ride.avgSpeedKmh.toStringAsFixed(1)} km/h'),
                _row('Velocidad máxima',
                    '${ride.maxSpeedKmh.toStringAsFixed(1)} km/h'),
                _row('Desnivel positivo',
                    '+${ride.elevationGainMeters.toStringAsFixed(0)} m'),
                _row('Puntos GPS', '${ride.points.length}'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Marker _dot(LatLng point, Color color) {
    return Marker(
      point: point,
      width: 18,
      height: 18,
      child: Container(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white60)),
          Text(value,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
