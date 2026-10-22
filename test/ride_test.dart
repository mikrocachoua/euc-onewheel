import 'package:euc_onewheel/models/ride.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Ride sobrevive el viaje de ida y vuelta a JSON', () {
    final ride = Ride(
      id: '1',
      startedAt: DateTime(2026, 10, 22, 7, 30),
      endedAt: DateTime(2026, 10, 22, 7, 55),
      points: [
        RidePoint(
          lat: 21.1619,
          lng: -86.8515,
          altitude: 10,
          speed: 5.5,
          t: DateTime(2026, 10, 22, 7, 30),
        ),
        RidePoint(
          lat: 21.1625,
          lng: -86.8520,
          t: DateTime(2026, 10, 22, 7, 31),
        ),
      ],
      distanceMeters: 5230,
      durationSeconds: 1500,
      avgSpeedKmh: 12.5,
      maxSpeedKmh: 28.4,
      elevationGainMeters: 24,
    );

    final back = Ride.fromJson(ride.toJson());
    expect(back.id, ride.id);
    expect(back.distanceKm, closeTo(5.23, 0.001));
    expect(back.points.length, 2);
    expect(back.points.first.lat, 21.1619);
    expect(back.points.first.speed, 5.5);
    expect(back.points.last.altitude, isNull);
    expect(back.maxSpeedKmh, 28.4);
  });
}
