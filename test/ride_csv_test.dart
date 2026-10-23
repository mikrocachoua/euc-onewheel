import 'package:euc_onewheel/models/ride.dart';
import 'package:euc_onewheel/services/ride_csv.dart';
import 'package:euc_onewheel/utils/units.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Exportación CSV de un viaje', () {
    final ride = Ride(
      id: '7',
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

    test('el CSV trae encabezados, resumen y una fila por punto', () {
      final csv = buildRideCsv(ride);
      expect(csv, contains('hora,latitud,longitud,altitud_m,velocidad_kmh'));
      expect(csv, contains('# Distancia km,5.230'));
      expect(csv, contains('21.1619,-86.8515,10.0,19.80'));
      // El segundo punto no trae altitud ni velocidad: celdas vacías.
      expect(csv, contains('21.1625,-86.852,'));
    });

    test('el nombre de archivo incluye la fecha del viaje', () {
      expect(rideCsvFileName(ride), 'euc-onewheel-viaje-20261022-0730.csv');
    });
  });

  group('Conversión de unidades', () {
    test('velocidad métrica e imperial', () {
      expect(displaySpeed(30, imperial: false), 30);
      expect(displaySpeed(30, imperial: true), closeTo(18.64, 0.01));
      expect(speedUnit(imperial: true), 'mph');
      expect(speedUnit(imperial: false), 'km/h');
    });

    test('temperatura °C y °F', () {
      expect(displayTemp(25, fahrenheit: false), 25);
      expect(displayTemp(25, fahrenheit: true), 77);
      expect(tempUnit(fahrenheit: true), '°F');
    });

    test('presión bar y psi', () {
      expect(displayPressure(2, psi: false), 2);
      expect(displayPressure(2, psi: true), closeTo(29.008, 0.01));
      expect(pressureUnit(psi: true), 'psi');
    });
  });
}
