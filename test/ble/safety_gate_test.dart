import 'dart:typed_data';

import 'package:euc_onewheel/models/wheel_telemetry.dart';
import 'package:euc_onewheel/services/ble/safety_gate.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pruebas de la compuerta de seguridad (regla dura del usuario):
/// ningún comando crítico puede salir con la rueda en movimiento.
void main() {
  late List<Uint8List> sent;
  late bool connected;
  late DateTime now;
  late SafetyGate gate;

  final frame = Uint8List.fromList([0xAA, 0x55, 0x40]);

  setUp(() {
    sent = [];
    connected = true;
    now = DateTime(2026, 10, 22, 12, 0, 0);
    gate = SafetyGate(
      isConnected: () => connected,
      send: (f) async => sent.add(f),
      now: () => now,
    );
  });

  Future<GateVerdict> run(
    WheelCommand command, {
    double speedKmh = 0,
    bool confirmed = true,
    DateTime? telemetryAt,
    bool withTelemetry = true,
  }) {
    return gate.execute(
      command: command,
      frame: frame,
      telemetry: WheelTelemetry(speedKmh: speedKmh),
      telemetryAt: withTelemetry
          ? (telemetryAt ?? now.subtract(const Duration(milliseconds: 500)))
          : null,
      userConfirmed: confirmed,
    );
  }

  group('comandos críticos', () {
    test('se bloquean con la rueda en movimiento (velocidad > 0)', () async {
      for (final command in [
        WheelCommand.powerOff,
        WheelCommand.motorLock,
        WheelCommand.calibration,
        WheelCommand.tiltBack,
        WheelCommand.speedAlarms,
        WheelCommand.pedalMode,
      ]) {
        final verdict = await run(command, speedKmh: 5);
        expect(verdict.allowed, isFalse, reason: '$command');
        expect(verdict.reason, contains('movimiento'));
      }
      expect(sent, isEmpty); // nada salió hacia la rueda
    });

    test('también se bloquean con velocidad negativa (reversa)', () async {
      final verdict = await run(WheelCommand.powerOff, speedKmh: -3);
      expect(verdict.allowed, isFalse);
      expect(sent, isEmpty);
    });

    test('pasan con velocidad = 0, telemetría fresca y confirmación', () async {
      final verdict = await run(WheelCommand.powerOff);
      expect(verdict.allowed, isTrue);
      expect(sent, [frame]);
      expect(gate.log.length, 1);
      expect(gate.log.single.command, WheelCommand.powerOff);
    });

    test('sin confirmación explícita se bloquean aun detenidos', () async {
      final verdict = await run(WheelCommand.calibration, confirmed: false);
      expect(verdict.allowed, isFalse);
      expect(verdict.reason, contains('confirmación'));
      expect(sent, isEmpty);
    });

    test('con telemetría vieja (> 2 s) se bloquean', () async {
      final verdict = await run(
        WheelCommand.tiltBack,
        telemetryAt: now.subtract(const Duration(seconds: 3)),
      );
      expect(verdict.allowed, isFalse);
      expect(verdict.reason, contains('reciente'));
      expect(sent, isEmpty);
    });

    test('sin ninguna telemetría recibida se bloquean', () async {
      final verdict = await run(WheelCommand.motorLock, withTelemetry: false);
      expect(verdict.allowed, isFalse);
      expect(sent, isEmpty);
    });
  });

  group('comandos moderados y bajos', () {
    test('la luz puede salir en movimiento, pero con confirmación', () async {
      final ok = await run(WheelCommand.light, speedKmh: 20);
      expect(ok.allowed, isTrue);
      expect(sent, [frame]);

      sent.clear();
      final no = await run(WheelCommand.light,
          speedKmh: 20, confirmed: false, withTelemetry: false);
      expect(no.allowed, isFalse);
      expect(sent, isEmpty);
    });

    test('el beep (bajo) no exige confirmación ni rueda detenida', () async {
      final verdict = await run(WheelCommand.beep,
          speedKmh: 15, confirmed: false, withTelemetry: false);
      expect(verdict.allowed, isTrue);
      expect(sent, [frame]);
    });
  });

  group('sin conexión', () {
    test('todo comando se bloquea cuando no hay enlace', () async {
      connected = false;
      final verdict = await run(WheelCommand.beep, withTelemetry: false);
      expect(verdict.allowed, isFalse);
      expect(verdict.reason, contains('conexión'));
      expect(sent, isEmpty);
    });
  });
}
