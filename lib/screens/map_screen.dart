import 'dart:async';

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../state/app_settings.dart';
import '../theme.dart';
import '../widgets/ui_kit.dart';
import 'settings/map_filters_screen.dart';

/// Pestaña Mapa (base v2): mapa a PANTALLA COMPLETA con tu ubicación
/// en vivo (punto azul), botones circulares de zoom + / −, botón de
/// centrar, acceso a filtros y botón AR (función en preparación).
///
/// Usa flutter_map + OpenStreetMap, la misma ruta de mapas de la app.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key, required this.settings});

  final AppSettings settings;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _mapController = MapController();
  StreamSubscription<Position>? _sub;
  bool _mapReady = false;

  // Cancún: centro por defecto mientras llega la primera señal GPS.
  LatLng _position = const LatLng(21.1619, -86.8515);
  bool _hasFix = false;

  @override
  void initState() {
    super.initState();
    _startLocation();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _startLocation() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
      _updatePosition(pos, move: true);
      _sub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
        ),
      ).listen((p) => _updatePosition(p), onError: (_) {});
    } catch (_) {
      // Sin plataforma de ubicación (p. ej. pruebas): el mapa queda
      // centrado en el punto por defecto.
    }
  }

  void _updatePosition(Position pos, {bool move = false}) {
    if (!mounted) return;
    setState(() {
      _position = LatLng(pos.latitude, pos.longitude);
      _hasFix = true;
    });
    if (move && _mapReady) _mapController.move(_position, 16);
  }

  void _centerOnMe() {
    if (_mapReady) _mapController.move(_position, 16.5);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _position,
            initialZoom: 15.5,
            onMapReady: () => _mapReady = true,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.euconewheel.euc_onewheel',
            ),
            if (_hasFix)
              MarkerLayer(
                markers: [
                  Marker(
                    point: _position,
                    width: 30,
                    height: 30,
                    child: Container(
                      decoration: BoxDecoration(
                        color: funcBlue,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 4),
                        boxShadow: [
                          BoxShadow(
                            color: funcBlue.withValues(alpha: 0.45),
                            blurRadius: 12,
                            spreadRadius: 3,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
        // Encabezado flotante.
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(
              children: [
                const SizedBox(width: 48),
                const Expanded(
                  child: Center(
                    child: Text(
                      'Mapa',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        shadows: [Shadow(color: Colors.black38, blurRadius: 8)],
                      ),
                    ),
                  ),
                ),
                CircleIconButton(
                  icon: Icons.tune,
                  tooltip: 'Filtrar',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          MapFiltersScreen(settings: widget.settings),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Botón AR (en preparación).
        Positioned(
          right: 14,
          top: MediaQuery.of(context).padding.top + 74,
          child: _roundButton(
            label: 'AR',
            onTap: () =>
                _snack('La vista de realidad aumentada está en preparación.'),
          ),
        ),
        // Zoom + / −.
        Positioned(
          right: 14,
          bottom: tabBarClearance + 108,
          child: Column(
            children: [
              _roundIconButton(Icons.add, () {
                if (_mapReady) {
                  _mapController.move(_mapController.camera.center,
                      _mapController.camera.zoom + 1);
                }
              }),
              const SizedBox(height: 10),
              _roundIconButton(Icons.remove, () {
                if (_mapReady) {
                  _mapController.move(_mapController.camera.center,
                      _mapController.camera.zoom - 1);
                }
              }),
            ],
          ),
        ),
        // Centrar en mi ubicación.
        Positioned(
          right: 14,
          bottom: tabBarClearance + 26,
          child:
              _roundIconButton(Icons.navigation, _centerOnMe, color: funcBlue),
        ),
        // Buscar (en preparación) y atribución.
        Positioned(
          left: 14,
          bottom: tabBarClearance + 26,
          child: _roundIconButton(Icons.search, () {
            _snack('La búsqueda de lugares en el mapa está en '
                'preparación.');
          }),
        ),
        Positioned(
          left: 8,
          bottom: tabBarClearance - 18,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              '© OpenStreetMap contributors',
              style: TextStyle(fontSize: 10, color: Colors.white70),
            ),
          ),
        ),
      ],
    );
  }

  Widget _roundButton({required String label, required VoidCallback onTap}) {
    return ClipOval(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Material(
          color: surfaceDark.withValues(alpha: 0.72),
          shape: const CircleBorder(
            side: BorderSide(color: Color(0x2EFFFFFF)),
          ),
          elevation: 4,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 54,
              height: 54,
              child: Center(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: funcBlue,
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _roundIconButton(IconData icon, VoidCallback onTap,
      {Color color = Colors.white}) {
    return ClipOval(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Material(
          color: surfaceDark.withValues(alpha: 0.72),
          shape: const CircleBorder(
            side: BorderSide(color: Color(0x2EFFFFFF)),
          ),
          elevation: 4,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 54,
              height: 54,
              child: Icon(icon, color: color, size: 26),
            ),
          ),
        ),
      ),
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
