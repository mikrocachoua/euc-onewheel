import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/ride.dart';
import '../services/ride_csv.dart';
import '../services/ride_store.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/speed_chart.dart';
import '../widgets/ui_kit.dart';

/// Detalle de un viaje: mapa con la ruta, resumen completo, gráfico
/// de velocidad en el tiempo, exportación a CSV, compartir el resumen
/// (hoja del sistema) y borrar.
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

  Future<void> _exportCsv(BuildContext context) async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${rideCsvFileName(ride)}');
      await file.writeAsString(buildRideCsv(ride));
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: 'Viaje EUC OneWheel (CSV)',
        ),
      );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo generar el archivo CSV.')),
        );
      }
    }
  }

  Future<void> _delete(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Borrar este viaje?'),
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
    final speedsKmh = [
      for (final p in ride.points)
        if (p.speed != null) p.speed! * 3.6,
    ];

    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: Row(
                  children: [
                    CircleIconButton(
                      icon: Icons.arrow_back_ios_new,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                    Expanded(
                      child: Center(
                        child: ScreenTitle(
                            'Viaje · ${formatDate(ride.startedAt)}'),
                      ),
                    ),
                    CircleIconButton(
                      icon: Icons.delete_outline,
                      tooltip: 'Borrar viaje',
                      onTap: () => _delete(context),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(cardRadius),
                      child: SizedBox(
                        height: 280,
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
                              userAgentPackageName:
                                  'com.euconewheel.euc_onewheel',
                            ),
                            if (pts.length > 1)
                              PolylineLayer(
                                polylines: [
                                  Polyline(
                                    points: pts,
                                    gradientColors: const [
                                      funcBlue,
                                      evCyan,
                                      cyanLight,
                                    ],
                                    strokeWidth: 4.5,
                                  ),
                                ],
                              ),
                            if (hasRoute)
                              MarkerLayer(
                                markers: [
                                  _dot(pts.first, okGreen),
                                  if (pts.length > 1) _dot(pts.last, evCyan),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    SurfaceCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SilverGradientText(
                            '${ride.distanceKm.toStringAsFixed(2)} km',
                            style: const TextStyle(
                                fontSize: 34, fontWeight: FontWeight.w800),
                          ),
                          Text(
                            formatDateTime(ride.startedAt),
                            style: const TextStyle(color: subText),
                          ),
                          const SizedBox(height: 14),
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
                    const SizedBox(height: 14),
                    SurfaceCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Velocidad en el viaje',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 12),
                          SpeedChart(speedsKmh: speedsKmh),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => SharePlus.instance.share(
                              ShareParams(text: _shareText),
                            ),
                            icon: const Icon(Icons.share, size: 19),
                            label: const Text('Compartir'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _exportCsv(context),
                            icon: const Icon(Icons.file_download_outlined,
                                size: 19),
                            label: const Text('Exportar CSV'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Al compartir eliges la app: Facebook, Instagram, '
                      'TikTok, X o Snapchat, si están instaladas.',
                      style: TextStyle(color: subText, fontSize: 12),
                      textAlign: TextAlign.center,
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
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: subText)),
          Text(value,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
