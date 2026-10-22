import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/ride.dart';

/// Guarda las rodadas como JSON en el directorio de documentos de la app.
class RideStore {
  static const _fileName = 'rides.json';

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// Lee todas las rodadas, de la más reciente a la más antigua.
  Future<List<Ride>> loadRides() async {
    try {
      final f = await _file();
      if (!await f.exists()) return [];
      final raw = await f.readAsString();
      if (raw.trim().isEmpty) return [];
      final list = jsonDecode(raw) as List<dynamic>;
      final rides = list
          .map((e) => Ride.fromJson(e as Map<String, dynamic>))
          .toList();
      rides.sort((a, b) => b.startedAt.compareTo(a.startedAt));
      return rides;
    } catch (_) {
      // Archivo corrupto o primera ejecución: se empieza de cero.
      return [];
    }
  }

  Future<void> _persist(List<Ride> rides) async {
    final f = await _file();
    final data = rides.map((r) => r.toJson()).toList();
    await f.writeAsString(jsonEncode(data));
  }

  /// Agrega una rodada nueva al historial.
  Future<void> saveRide(Ride ride) async {
    final rides = await loadRides();
    rides.insert(0, ride);
    await _persist(rides);
  }

  /// Borra una rodada por su id.
  Future<void> deleteRide(String id) async {
    final rides = await loadRides();
    rides.removeWhere((r) => r.id == id);
    await _persist(rides);
  }
}
