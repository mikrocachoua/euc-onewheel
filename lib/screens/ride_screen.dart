import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';

import '../models/ride.dart';
import '../services/ride_store.dart';
import '../theme.dart';
import '../utils/format.dart';

enum _RideState { idle, recording, paused }

/// Pantalla de grabación de rodadas con GPS REAL del teléfono.
/// Dibuja la ruta en el degradado azul → cian de la identidad
/// sobre el mapa, acumula distancia/tiempos y, al terminar, guarda
/// la rodada y muestra el resumen completo.
class RideScreen extends StatefulWidget {
  const RideScreen({super.key});

  @override
  State<RideScreen> createState() => _RideScreenState();
}

class _RideScreenState extends State<RideScreen> {
  final _mapController = MapController();
  final _store = RideStore();

  // Cancún: centro por defecto mientras llega la primera señal GPS.
  LatLng _center = const LatLng(21.1619, -86.8515);
  bool _mapReady = false;
  bool _hasFix = false;

  _RideState _state = _RideState.idle;
  StreamSubscription<Position>? _sub;
  Timer? _ticker;
  final _stopwatch = Stopwatch();

  final List<RidePoint> _points = [];
  Position? _lastCounted;
  double _distanceMeters = 0;
  double _currentSpeedKmh = 0;
  double _maxSpeedKmh = 0;
  double _elevationGain = 0;
  double? _lastAltitude;
  DateTime? _startedAt;

  double get _avgSpeedKmh {
    final secs = _stopwatch.elapsed.inSeconds;
    if (secs == 0) return 0;
    return (_distanceMeters / secs) * 3.6;
  }

  @override
  void initState() {
    super.initState();
    _centerOnUser();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ticker?.cancel();
    _stopwatch.stop();
    super.dispose();
  }

  Future<void> _centerOnUser() async {
    try {
      final ok = await _ensurePermission(silent: true);
      if (!ok) return;
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
      if (!mounted) return;
      setState(() {
        _center = LatLng(pos.latitude, pos.longitude);
        _hasFix = true;
      });
      if (_mapReady) _mapController.move(_center, 16);
    } catch (_) {
      // Sin señal todavía: se queda el centro por defecto.
    }
  }

  Future<bool> _ensurePermission({bool silent = false}) async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!silent) _snack('Activa la ubicación del teléfono para grabar.');
      return false;
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied) {
      if (!silent) _snack('Sin permiso de ubicación no se puede grabar.');
      return false;
    }
    if (perm == LocationPermission.deniedForever) {
      if (!silent) {
        _snack('El permiso de ubicación está bloqueado. Actívalo en Ajustes.');
      }
      return false;
    }
    return true;
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _start() async {
    final ok = await _ensurePermission();
    if (!ok) return;

    setState(() {
      _points.clear();
      _distanceMeters = 0;
      _currentSpeedKmh = 0;
      _maxSpeedKmh = 0;
      _elevationGain = 0;
      _lastAltitude = null;
      _lastCounted = null;
      _startedAt = DateTime.now();
      _state = _RideState.recording;
    });
    _stopwatch
      ..reset()
      ..start();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });

    _sub?.cancel();
    _sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 3,
      ),
    ).listen(_onPosition, onError: (_) {});
  }

  void _onPosition(Position pos) {
    if (_state != _RideState.recording) return;
    // Ignora lecturas imprecisas: arruinan distancia y ruta.
    if (pos.accuracy > 25) return;

    final point = RidePoint(
      lat: pos.latitude,
      lng: pos.longitude,
      altitude: pos.altitude == 0 ? null : pos.altitude,
      speed: pos.speed < 0 ? null : pos.speed,
      t: pos.timestamp,
    );

    final last = _lastCounted;
    if (last != null) {
      final seg = Geolocator.distanceBetween(
        last.latitude,
        last.longitude,
        pos.latitude,
        pos.longitude,
      );
      // Filtra el "ruido" del GPS parado y saltos imposibles.
      if (seg >= 1.5 && seg <= 200) _distanceMeters += seg;
    }
    _lastCounted = pos;

    final alt = point.altitude;
    if (alt != null) {
      final prevAlt = _lastAltitude;
      if (prevAlt != null) {
        final diff = alt - prevAlt;
        if (diff > 0.5) _elevationGain += diff;
      }
      _lastAltitude = alt;
    }

    final kmh = (pos.speed < 0 ? 0.0 : pos.speed * 3.6);
    setState(() {
      _points.add(point);
      _currentSpeedKmh = kmh;
      if (kmh > _maxSpeedKmh) _maxSpeedKmh = kmh;
      _center = LatLng(pos.latitude, pos.longitude);
      _hasFix = true;
    });
    if (_mapReady) _mapController.move(_center, 16.5);
  }

  void _pause() {
    _sub?.pause();
    _stopwatch.stop();
    setState(() => _state = _RideState.paused);
  }

  void _resume() {
    _sub?.resume();
    _stopwatch.start();
    setState(() => _state = _RideState.recording);
  }

  Future<void> _finish() async {
    await _sub?.cancel();
    _sub = null;
    _ticker?.cancel();
    _stopwatch.stop();
    final seconds = _stopwatch.elapsed.inSeconds;

    if (_points.length < 2 || _distanceMeters < 5) {
      setState(() => _state = _RideState.idle);
      _snack('Rodada demasiado corta: no se guardó.');
      return;
    }

    final ride = Ride(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      startedAt: _startedAt ?? _points.first.t,
      endedAt: DateTime.now(),
      points: List.unmodifiable(_points),
      distanceMeters: _distanceMeters,
      durationSeconds: seconds,
      avgSpeedKmh: seconds > 0 ? (_distanceMeters / seconds) * 3.6 : 0,
      maxSpeedKmh: _maxSpeedKmh,
      elevationGainMeters: _elevationGain,
    );
    await _store.saveRide(ride);
    if (!mounted) return;
    setState(() => _state = _RideState.idle);
    _showSummary(ride);
  }

  void _showSummary(Ride ride) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Resumen de la rodada'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${ride.distanceKm.toStringAsFixed(2)} km',
              style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(formatDateTime(ride.startedAt),
                style: const TextStyle(color: subText)),
            const SizedBox(height: 14),
            _summaryRow('Duración', formatDuration(ride.duration)),
            _summaryRow('Velocidad media',
                '${ride.avgSpeedKmh.toStringAsFixed(1)} km/h'),
            _summaryRow('Velocidad máxima',
                '${ride.maxSpeedKmh.toStringAsFixed(1)} km/h'),
            _summaryRow('Desnivel positivo',
                '+${ride.elevationGainMeters.toStringAsFixed(0)} m'),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              SharePlus.instance.share(
                ShareParams(text: _shareText(ride)),
              );
            },
            icon: const Icon(Icons.share),
            label: const Text('Compartir'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Listo'),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: subText)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  String _shareText(Ride r) {
    return 'EUC OneWheel — Rodada ${formatDate(r.startedAt)}\n'
        'Distancia: ${r.distanceKm.toStringAsFixed(2)} km\n'
        'Duración: ${formatDuration(r.duration)}\n'
        'Velocidad media: ${r.avgSpeedKmh.toStringAsFixed(1)} km/h · '
        'Máxima: ${r.maxSpeedKmh.toStringAsFixed(1)} km/h\n'
        'Desnivel positivo: +${r.elevationGainMeters.toStringAsFixed(0)} m';
  }

  @override
  Widget build(BuildContext context) {
    final latLngs = _points.map((p) => LatLng(p.lat, p.lng)).toList();
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _center,
                  initialZoom: 16,
                  onMapReady: () => _mapReady = true,
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.euconewheel.euc_onewheel',
                  ),
                  if (latLngs.length > 1)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: latLngs,
                          gradientColors: const [funcBlue, evCyan, cyanLight],
                          strokeWidth: 4.5,
                        ),
                      ],
                    ),
                  if (_hasFix)
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: _center,
                          width: 22,
                          height: 22,
                          child: Container(
                            decoration: BoxDecoration(
                              color: funcBlue,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              Positioned(
                left: 8,
                bottom: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    '© OpenStreetMap contributors',
                    style: TextStyle(fontSize: 10, color: Colors.white70),
                  ),
                ),
              ),
            ],
          ),
        ),
        _statsBar(),
        _controls(),
      ],
    );
  }

  Widget _statsBar() {
    return Container(
      decoration: const BoxDecoration(
        color: cockpitBgTop,
        border: Border(top: BorderSide(color: surfaceBorder)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _stat(
              'DISTANCIA', '${(_distanceMeters / 1000).toStringAsFixed(2)} km'),
          _stat('TIEMPO', formatDuration(_stopwatch.elapsed)),
          _stat('AHORA', '${_currentSpeedKmh.toStringAsFixed(0)} km/h'),
          _stat('MEDIA', '${_avgSpeedKmh.toStringAsFixed(1)} km/h'),
          _stat('MÁX', '${_maxSpeedKmh.toStringAsFixed(0)} km/h'),
        ],
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
              fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: subText),
        ),
      ],
    );
  }

  Widget _controls() {
    return Container(
      color: cockpitBgTop,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Row(
        children: [
          if (_state == _RideState.idle)
            Expanded(
              child: FilledButton.icon(
                onPressed: _start,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Iniciar rodada'),
              ),
            ),
          if (_state == _RideState.recording) ...[
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pause,
                icon: const Icon(Icons.pause),
                label: const Text('Pausar'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: _finish,
                icon: const Icon(Icons.stop),
                label: const Text('Terminar'),
              ),
            ),
          ],
          if (_state == _RideState.paused) ...[
            Expanded(
              child: FilledButton.icon(
                onPressed: _resume,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Reanudar'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _finish,
                icon: const Icon(Icons.stop),
                label: const Text('Terminar'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
