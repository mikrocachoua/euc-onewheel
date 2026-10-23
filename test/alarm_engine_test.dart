import 'package:euc_onewheel/models/wheel_telemetry.dart';
import 'package:euc_onewheel/services/alarm_engine.dart';
import 'package:euc_onewheel/state/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

Map<AlarmKind, AlarmThreshold> _thresholds() => {
      AlarmKind.velocidad: const AlarmThreshold(value: 30),
      AlarmKind.amperaje: const AlarmThreshold(value: 30),
      AlarmKind.potencia: const AlarmThreshold(value: 2000),
      AlarmKind.temperatura: const AlarmThreshold(value: 65),
      AlarmKind.pwm: const AlarmThreshold(value: 85),
    };

void main() {
  group('Motor de alarmas', () {
    test('sin telemetría problemática no salta ninguna alarma', () {
      const t = WheelTelemetry(
        speedKmh: 18,
        currentA: 9,
        powerW: 700,
        tempC: 38,
        pwmPct: 40,
      );
      expect(evaluateAlarms(t, _thresholds()), isEmpty);
    });

    test('la velocidad por encima del umbral dispara su alarma', () {
      const t = WheelTelemetry(speedKmh: 31);
      final alarms = evaluateAlarms(t, _thresholds());
      expect(alarms, hasLength(1));
      expect(alarms.single.kind, AlarmKind.velocidad);
      expect(alarms.single.measured, 31);
    });

    test('varias alarmas pueden saltar a la vez', () {
      const t = WheelTelemetry(
        speedKmh: 40,
        currentA: 45,
        powerW: 3200,
        tempC: 71,
        pwmPct: 93,
      );
      final kinds = evaluateAlarms(t, _thresholds()).map((a) => a.kind);
      expect(kinds, containsAll(AlarmKind.values));
    });

    test('una alarma deshabilitada nunca salta', () {
      final thresholds = _thresholds();
      thresholds[AlarmKind.velocidad] =
          const AlarmThreshold(enabled: false, value: 30);
      const t = WheelTelemetry(speedKmh: 55);
      expect(evaluateAlarms(t, thresholds), isEmpty);
    });

    test('sin PWM reportado, la alarma de PWM no puede saltar', () {
      const t = WheelTelemetry(speedKmh: 10); // pwmPct null
      final alarms = evaluateAlarms(t, _thresholds());
      expect(alarms.map((a) => a.kind), isNot(contains(AlarmKind.pwm)));
    });

    test('corriente negativa (regenerando) se evalúa por su magnitud', () {
      const t = WheelTelemetry(currentA: -38);
      final alarms = evaluateAlarms(t, _thresholds());
      expect(alarms.map((a) => a.kind), contains(AlarmKind.amperaje));
    });
  });
}
