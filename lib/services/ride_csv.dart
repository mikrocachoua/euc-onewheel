import '../models/ride.dart';

/// Construye el CSV de una rodada: una fila por punto GPS con hora,
/// coordenadas, altitud y velocidad. Función pura y testeable; la
/// exportación a archivo/hoja de compartir vive en la pantalla de
/// detalle.
String buildRideCsv(Ride ride) {
  final buffer = StringBuffer()
    ..writeln('# EUC OneWheel — exportación de viaje')
    ..writeln('# Inicio,${ride.startedAt.toIso8601String()}')
    ..writeln('# Distancia km,${ride.distanceKm.toStringAsFixed(3)}')
    ..writeln('# Duración s,${ride.durationSeconds}')
    ..writeln('# Velocidad media km/h,${ride.avgSpeedKmh.toStringAsFixed(2)}')
    ..writeln('# Velocidad máxima km/h,${ride.maxSpeedKmh.toStringAsFixed(2)}')
    ..writeln('hora,latitud,longitud,altitud_m,velocidad_kmh');
  for (final p in ride.points) {
    final speedKmh = p.speed == null ? '' : (p.speed! * 3.6).toStringAsFixed(2);
    buffer.writeln('${p.t.toIso8601String()},${p.lat},${p.lng},'
        '${p.altitude ?? ''},$speedKmh');
  }
  return buffer.toString();
}

/// Nombre de archivo sugerido para la exportación de una rodada.
String rideCsvFileName(Ride ride) {
  final d = ride.startedAt;
  String two(int n) => n.toString().padLeft(2, '0');
  return 'euc-onewheel-viaje-${d.year}${two(d.month)}${two(d.day)}-'
      '${two(d.hour)}${two(d.minute)}.csv';
}
