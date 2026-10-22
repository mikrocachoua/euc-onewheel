/// Un punto GPS capturado durante una rodada.
class RidePoint {
  final double lat;
  final double lng;

  /// Altitud en metros (puede ser null si el GPS no la reportó).
  final double? altitude;

  /// Velocidad instantánea en m/s reportada por el GPS (puede ser null).
  final double? speed;

  /// Momento de captura.
  final DateTime t;

  const RidePoint({
    required this.lat,
    required this.lng,
    this.altitude,
    this.speed,
    required this.t,
  });

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lng': lng,
        'alt': altitude,
        'spd': speed,
        't': t.millisecondsSinceEpoch,
      };

  factory RidePoint.fromJson(Map<String, dynamic> json) => RidePoint(
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        altitude: (json['alt'] as num?)?.toDouble(),
        speed: (json['spd'] as num?)?.toDouble(),
        t: DateTime.fromMillisecondsSinceEpoch(json['t'] as int),
      );
}

/// Una rodada grabada con GPS: ruta completa y estadísticas detalladas
/// de la actividad.
class Ride {
  final String id;
  final DateTime startedAt;
  final DateTime endedAt;
  final List<RidePoint> points;
  final double distanceMeters;
  final int durationSeconds;
  final double avgSpeedKmh;
  final double maxSpeedKmh;

  /// Desnivel positivo estimado en metros, calculado con las altitudes GPS.
  final double elevationGainMeters;

  const Ride({
    required this.id,
    required this.startedAt,
    required this.endedAt,
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.avgSpeedKmh,
    required this.maxSpeedKmh,
    required this.elevationGainMeters,
  });

  double get distanceKm => distanceMeters / 1000.0;

  Duration get duration => Duration(seconds: durationSeconds);

  Map<String, dynamic> toJson() => {
        'id': id,
        'startedAt': startedAt.toIso8601String(),
        'endedAt': endedAt.toIso8601String(),
        'points': points.map((p) => p.toJson()).toList(),
        'distanceMeters': distanceMeters,
        'durationSeconds': durationSeconds,
        'avgSpeedKmh': avgSpeedKmh,
        'maxSpeedKmh': maxSpeedKmh,
        'elevationGainMeters': elevationGainMeters,
      };

  factory Ride.fromJson(Map<String, dynamic> json) => Ride(
        id: json['id'] as String,
        startedAt: DateTime.parse(json['startedAt'] as String),
        endedAt: DateTime.parse(json['endedAt'] as String),
        points: (json['points'] as List<dynamic>)
            .map((e) => RidePoint.fromJson(e as Map<String, dynamic>))
            .toList(),
        distanceMeters: (json['distanceMeters'] as num).toDouble(),
        durationSeconds: json['durationSeconds'] as int,
        avgSpeedKmh: (json['avgSpeedKmh'] as num).toDouble(),
        maxSpeedKmh: (json['maxSpeedKmh'] as num).toDouble(),
        elevationGainMeters: (json['elevationGainMeters'] as num).toDouble(),
      );
}
