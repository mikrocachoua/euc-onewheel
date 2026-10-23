import 'dart:typed_data';

import 'package:euc_onewheel/models/wheel_identity.dart';
import 'package:euc_onewheel/services/ble/adapters/begode_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

/// Vectores de tramas reales del protocolo Begode (Gotway): los
/// mismos flujos hex y valores esperados que valida la
/// implementación de referencia de código abierto del protocolo
/// (tramas partidas entre notificaciones BLE, paquetes «basura»,
/// SmartBMS y el texto de arranque con nombre/firmware).
Uint8List hex(String s) {
  final out = Uint8List(s.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(s.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

void main() {
  group('BegodeAdapter · trama A sintética (espejo de la referencia)', () {
    test('voltaje 60 V, velocidad −1111, corriente −8322, temp 99', () {
      final adapter = BegodeAdapter();
      // Construida campo a campo como en la referencia: cabecera,
      // voltaje BE, velocidad BE con signo, hueco, distancia en el
      // offset 8, corriente de fase, temperatura, relleno, tipo 0.
      final frame = Uint8List(24);
      frame[0] = 0x55;
      frame[1] = 0xAA;
      frame[2] = 6000 >> 8;
      frame[3] = 6000 & 0xFF;
      frame[4] = (-1111) >> 8 & 0xFF;
      frame[5] = (-1111) & 0xFF;
      frame[8] = 3231 >> 8;
      frame[9] = 3231 & 0xFF;
      frame[10] = (-8322) >> 8 & 0xFF;
      frame[11] = (-8322) & 0xFF;
      frame[12] = 99 >> 8;
      frame[13] = 99 & 0xFF;
      frame[14] = 14;
      frame[15] = 15;
      frame[16] = 16;
      frame[17] = 17;
      frame[18] = 0;
      frame[19] = 0x18;
      frame.fillRange(20, 24, 0x5A);

      expect(adapter.decode(frame), isTrue);
      final t = adapter.telemetry;
      expect(t.voltageV, closeTo(60.0, 1e-9));
      // Velocidad: round(−1111 × 3.6) / 100 = −40.0 km/h.
      expect(t.speedKmh, closeTo(-40.0, 1e-9));
      // Temperatura IMU: 99 / 340 + 36.53 ≈ 36.82 °C (la
      // referencia la valida truncada a 36).
      expect(t.tempC, closeTo(99 / 340 + 36.53, 1e-9));
      expect(t.currentA, closeTo(-83.22, 1e-9));
      expect(adapter.phaseCurrentA, closeTo(-83.22, 1e-9));
      expect(t.powerW, closeTo(60.0 * -83.22, 1e-6));
      expect(t.distanceM, 3231);
      expect(t.batteryPct, 54); // curva estándar: (6000−5290)/13
    });
  });

  group('BegodeAdapter · placa 2020 (tramas partidas)', () {
    test('A y B reensambladas entre tres notificaciones', () {
      final adapter = BegodeAdapter();
      final r1 =
          adapter.decode(hex('55AA19C1000000000000008CF0000001FFF80018'));
      final r2 =
          adapter.decode(hex('5A5A5A5A55AA000060D248001C20006400010007'));
      final r3 = adapter.decode(hex('000804185A5A5A5A'));

      expect(r1, isFalse); // la trama A aún está incompleta
      expect(r2, isTrue); // se completa la trama A (en vivo)
      expect(r3, isFalse); // se completa la B, que no es «en vivo»

      final t = adapter.telemetry;
      expect(t.voltageV, closeTo(65.93, 1e-9));
      expect(t.speedKmh, closeTo(0, 1e-9));
      // (−4096 / 340 + 36.53) ≈ 24.48 °C (referencia: 24).
      expect(t.tempC, closeTo(-4096 / 340 + 36.53, 1e-9));
      expect(t.currentA, closeTo(1.4, 1e-9));
      expect(t.distanceM, 0);
      expect(t.totalDistanceM, 24786);
      expect(t.batteryPct, 100);
    });
  });

  group('BegodeAdapter · placa nueva con SmartBMS (dos pasadas)', () {
    const chunks = [
      '55aa17750538007602eefb64f494148100090018',
      '5a5a5a5a55aa0032000004b10000000013880000',
      '000001005a5a5a5a55aa00000000000000000000',
      '00000000000003005a5a5a5a55aa003c278c4900',
      '1c2000c800000000001204185a5a5a5a55aa022c',
      '000000000000000000000000000007185a5a5a5a',
    ];

    test('secuencia completa: voltaje real y corriente real mandan', () {
      final adapter = BegodeAdapter();
      final results = <bool>[];

      // Primera pasada.
      for (var i = 0; i < chunks.length; i++) {
        results.add(adapter.decode(hex(chunks[i])));
        if (i == 1) {
          // Tras la trama A: corriente de fase y voltaje de la A.
          expect(adapter.phaseCurrentA, closeTo(-11.8, 1e-9));
          expect(adapter.telemetry.voltageV, closeTo(60.05, 1e-9));
        }
        if (i == 2) {
          // Tras la trama 0x01: el voltaje real del BMS manda.
          expect(adapter.telemetry.voltageV, closeTo(120.10, 1e-9));
          expect(adapter.pwmLimit, 50);
        }
      }
      // Segunda pasada idéntica: solo la 0x07 final cuenta como
      // dato en vivo (el voltaje y la corriente reales ya tomaron
      // el relevo, como valida la referencia).
      for (final chunk in chunks) {
        results.add(adapter.decode(hex(chunk)));
      }

      expect(results, [
        false, true, false, false, false, false, //
        false, false, false, false, false, true,
      ]);

      final t = adapter.telemetry;
      // round(1336 × 3.6) / 100 = 48.10 km/h.
      expect(t.speedKmh, closeTo(48.10, 1e-9));
      // (−2924 / 340 + 36.53) ≈ 27.93 °C (referencia: 27).
      expect(t.tempC, closeTo(-2924 / 340 + 36.53, 1e-9));
      expect(t.voltageV, closeTo(120.10, 1e-9));
      expect(t.currentA, closeTo(-5.56, 1e-9)); // trama 0x07
      expect(t.distanceM, 750);
      expect(t.totalDistanceM, 3942284);
      expect(t.batteryPct, 55);
    });

    test('segunda variante de placa nueva', () {
      final adapter = BegodeAdapter();
      const chunks2 = [
        '55aa177007390076001103b6f387148100090018',
        '5a5a5a5a55aa0032000004b00000000013880000',
        '000001025a5a5a5a55aa00000000000000000000',
        '00000000000003025a5a5a5a55aa003c24af4900',
        '1c2000c800000100001204185a5a5a5a55aafd7e',
        '000000000000000000000000000007185a5a5a5a',
      ];
      final results = <bool>[];
      for (var i = 0; i < chunks2.length; i++) {
        results.add(adapter.decode(hex(chunks2[i])));
        if (i == 1) {
          expect(adapter.phaseCurrentA, closeTo(9.5, 1e-9));
        }
      }
      for (final chunk in chunks2) {
        results.add(adapter.decode(hex(chunk)));
      }
      expect(results, [
        false, true, false, false, false, false, //
        false, false, false, false, false, true,
      ]);

      final t = adapter.telemetry;
      // round(1849 × 3.6) / 100 = 66.56 km/h.
      expect(t.speedKmh, closeTo(66.56, 1e-9));
      expect(t.tempC, closeTo(-3193 / 340 + 36.53, 1e-9));
      expect(t.voltageV, closeTo(120.00, 1e-9));
      expect(t.currentA, closeTo(6.42, 1e-9));
      expect(t.distanceM, 17);
      expect(t.totalDistanceM, 3941551);
      expect(t.batteryPct, 54);
    });
  });

  group('BegodeAdapter · placa extraña (A y B separadas por la cola)', () {
    test('valores de A y ajustes de B', () {
      final adapter = BegodeAdapter();
      final r1 =
          adapter.decode(hex('55AA19A0000C00000000032AF8150001FFF80018'));
      final r2 = adapter.decode(hex('5A5A5A5A'));
      final r3 =
          adapter.decode(hex('55AA000026E324001C19001E0001000700080418'));
      final r4 = adapter.decode(hex('5A5A5A5A'));

      expect([r1, r2, r3, r4], [false, true, false, false]);

      final t = adapter.telemetry;
      expect(t.speedKmh, closeTo(0.43, 1e-9)); // round(12×3.6)/100
      // (−2027 / 340 + 36.53) ≈ 30.57 °C (referencia: 30).
      expect(t.tempC, closeTo(-2027 / 340 + 36.53, 1e-9));
      expect(t.voltageV, closeTo(65.6, 1e-9));
      expect(t.currentA, closeTo(8.1, 1e-9));
      expect(t.distanceM, 0);
      expect(t.totalDistanceM, 9955);
      expect(t.batteryPct, 97);

      // Ajustes de la trama B (settings = 0x2400).
      expect(adapter.pedalMode, 1);
      expect(adapter.speedAlarmMode, 1);
      expect(adapter.rollAngleMode, 0);
      expect(adapter.inMiles, isFalse);
      expect(adapter.autoOffSeconds, 7193);
      expect(adapter.tiltBackSpeedKmh, 30);
      expect(adapter.ledMode, 1);
      expect(adapter.alertFlags, 0);
      expect(adapter.lightMode, 3);
    });
  });

  group('BegodeAdapter · tramas del ejemplo de especificación', () {
    test('trama A de ejemplo', () {
      final adapter = BegodeAdapter();
      final r = adapter
          .decode(hex('55AA19F0000000000000012CFDCA0001FFF800185A5A5A5A'));
      expect(r, isTrue);
      final t = adapter.telemetry;
      expect(t.voltageV, closeTo(66.4, 1e-9));
      expect(t.batteryPct, 100);
      expect(t.speedKmh, closeTo(0, 1e-9));
      expect(t.distanceM, 0);
      expect(t.currentA, closeTo(3.0, 1e-9));
      // (−566 / 340 + 36.53) ≈ 34.87 °C.
      expect(t.tempC, closeTo(-566 / 340 + 36.53, 1e-9));
    });

    test('trama B de ejemplo: distancia total y ajustes', () {
      final adapter = BegodeAdapter();
      final r1 =
          adapter.decode(hex('55AA000A4A1248001C20002A0003000700080418'));
      final r2 = adapter.decode(hex('5A5A5A5A'));
      expect([r1, r2], [false, false]);
      expect(adapter.telemetry.totalDistanceM, 674322);
      // settings = 0x4800.
      expect(adapter.pedalMode, 2);
      expect(adapter.speedAlarmMode, 2);
      expect(adapter.rollAngleMode, 0);
      expect(adapter.autoOffSeconds, 7200);
      expect(adapter.tiltBackSpeedKmh, 42);
      expect(adapter.ledMode, 3);
      expect(adapter.lightMode, 3);
    });

    test('tilt-back reportado como 100+ se normaliza a 0', () {
      final adapter = BegodeAdapter();
      // Trama B de la placa 2020: tilt-back crudo = 100.
      adapter.decode(hex('55AA000060D248001C20006400010007'));
      adapter.decode(hex('000804185A5A5A5A'));
      expect(adapter.tiltBackSpeedKmh, 0);
    });
  });

  group('BegodeAdapter · SmartBMS', () {
    test('las tramas de celdas no son telemetría en vivo', () {
      final adapter = BegodeAdapter();
      const frames = [
        '55aa0f930f890f850f830f810f890f930f9902005a5a5a5a',
        '55aa0f9a0f940f980f980f940f950f880f8002015a5a5a5a',
        '55aa0f910f920f930f8f0f930f970f960f9202025a5a5a5a',
        '55aa0fdd0fdf0fdf0fe20fe10fda0fde0fda02035a5a5a5a',
        '55aa0fdf0fe00fda0fe00fdf0fdd0fda0fd802045a5a5a5a',
        '55aa0fdb0fde0fdd0fe10fd80fd50fdb0fd302055a5a5a5a',
        '55aa0fd40fda00000000000000000000000002065a5a5a5a',
        '55aa0fd60fda0fda0fda0fd30fd60fd30fd303005a5a5a5a',
        '55aa0fcf0fcb0fce0fd40fd40fd20fcc0fcc03015a5a5a5a',
        '55aa0fcd0fcd0fcf0fca0fd00fd60fd50fd803025a5a5a5a',
        '55aa0fce0fe40fe00fe40fdf0fd70fd60fd603035a5a5a5a',
        '55aa0fde0fdf0fda0fdf0fe10fde0fda0fd803045a5a5a5a',
        '55aa0fdb0fe00fe00fe20fd90fda0fdc0fd603055a5a5a5a',
        '55aa0fd60fdd00000000000000000000000003065a5a5a5a',
      ];
      for (final frame in frames) {
        expect(adapter.decode(hex(frame)), isFalse);
      }
    });

    test('cuenta las celdas con voltaje de los paquetes BMS', () {
      final adapter = BegodeAdapter();
      // Paquete 0 del BMS 1: 8 celdas con voltaje.
      adapter.decode(hex('55aa0f930f890f850f830f810f890f930f9902005a5a5a5a'));
      expect(adapter.detectedCells, 8);
    });
  });

  group('BegodeAdapter · texto de arranque (nombre y firmware)', () {
    test('GW da la versión y NAME el modelo', () {
      final adapter = BegodeAdapter();
      final r1 = adapter.decode(hex('475732303032303031'));
      final r2 = adapter.decode(hex('4e414d453a45584e0d0a'));
      final r3 = adapter.decode(hex('204d505536353030b3f5cabcbbafb3c9b9a620'));
      expect([r1, r2, r3], [false, false, false]);
      expect(adapter.identity.model, 'EXN');
      expect(adapter.identity.firmware, '2002001');
      expect(adapter.identity.brand, WheelBrand.begode);
      expect(adapter.firmwareFamily, 'Begode');
      expect(adapter.telemetry.model, 'EXN');
    });
  });

  group('BegodeAdapter · desempaquetador', () {
    test('datos corruptos de 0 a 29 bytes nunca decodifican', () {
      final adapter = BegodeAdapter();
      for (var len = 0; len < 30; len++) {
        final junk = Uint8List.fromList(List.generate(len, (i) => i));
        expect(adapter.decode(junk), isFalse, reason: 'len=$len');
      }
    });

    test('paquete basura 55 AA 5A 55 AA se reensambla', () {
      final adapter = BegodeAdapter();
      // Basura documentada del protocolo seguida del resto de una
      // trama A válida (la de los valores normales).
      final r = adapter.decode(hex('55AA5A55AA'
          '1770FBA900000C9FDF7E00630E0F10110018'
          '5A5A5A5A'));
      expect(r, isTrue);
      expect(adapter.telemetry.voltageV, closeTo(60.0, 1e-9));
      expect(adapter.telemetry.distanceM, 3231);
    });

    test('paquete basura 55 AA 5A 5A 55 AA se reensambla', () {
      final adapter = BegodeAdapter();
      final r = adapter.decode(hex('55AA5A5A55AA'
          '1770FBA900000C9FDF7E00630E0F10110018'
          '5A5A5A5A'));
      expect(r, isTrue);
      expect(adapter.telemetry.speedKmh, closeTo(-40.0, 1e-9));
    });

    test('una cola que no es 5A invalida la trama y resincroniza', () {
      final adapter = BegodeAdapter();
      // Trama con la cola corrupta (00 en vez de 5A).
      final bad = adapter.decode(hex('55AA1770FBA900000C9FDF7E0063'
          '0E0F10110018'
          '5A5A5A00'));
      expect(bad, isFalse);
      // La siguiente trama válida sí decodifica.
      final good = adapter.decode(hex('55AA1770FBA900000C9FDF7E0063'
          '0E0F10110018'
          '5A5A5A5A'));
      expect(good, isTrue);
      expect(adapter.telemetry.voltageV, closeTo(60.0, 1e-9));
    });
  });

  group('BegodeAdapter · voltaje: curva y reescalado', () {
    test('curva estándar de batería sobre el voltaje crudo', () {
      expect(BegodeAdapter.batteryLevelFor(5000), 0);
      expect(BegodeAdapter.batteryLevelFor(5290), 0);
      expect(BegodeAdapter.batteryLevelFor(6000), 54);
      expect(BegodeAdapter.batteryLevelFor(6579), 99);
      expect(BegodeAdapter.batteryLevelFor(6580), 100);
      expect(BegodeAdapter.batteryLevelFor(6640), 100);
    });

    test('tabla de factores y celdas por clase de pack', () {
      expect(BegodeAdapter.scalerForVoltageIndex(0), 1.0);
      expect(BegodeAdapter.scalerForVoltageIndex(1), 1.25);
      expect(BegodeAdapter.scalerForVoltageIndex(2), 1.5);
      expect(BegodeAdapter.scalerForVoltageIndex(3),
          closeTo(1.7380952380952381, 1e-12));
      expect(BegodeAdapter.scalerForVoltageIndex(4), 2.0);
      expect(BegodeAdapter.scalerForVoltageIndex(5), 2.5);
      expect(BegodeAdapter.scalerForVoltageIndex(6), 2.25);
      expect(BegodeAdapter.cellsForVoltageIndex(0), 16);
      expect(BegodeAdapter.cellsForVoltageIndex(1), 20);
      expect(BegodeAdapter.cellsForVoltageIndex(2), 24);
      expect(BegodeAdapter.cellsForVoltageIndex(3), 32);
      expect(BegodeAdapter.cellsForVoltageIndex(4), 32);
      expect(BegodeAdapter.cellsForVoltageIndex(5), 40);
      expect(BegodeAdapter.cellsForVoltageIndex(6), 36);
    });

    test(
        'con pack de 100.8 V el voltaje se reescala ×1.5 y el % '
        'se sigue calculando sobre el crudo', () {
      final adapter =
          BegodeAdapter(voltageScaler: BegodeAdapter.scalerForVoltageIndex(2));
      final r = adapter.decode(hex('55AA1770FBA900000C9FDF7E0063'
          '0E0F10110018'
          '5A5A5A5A'));
      expect(r, isTrue);
      expect(adapter.telemetry.voltageV, closeTo(90.0, 1e-9));
      expect(adapter.telemetry.batteryPct, 54);
      expect(adapter.telemetry.powerW, closeTo(90.0 * -83.22, 1e-6));
    });
  });

  group('BegodeAdapter · base', () {
    test('el snapshot inicial es neutro y solo hay telemetría', () {
      final adapter = BegodeAdapter();
      expect(adapter.brand, WheelBrand.begode);
      expect(adapter.telemetry.speedKmh, 0);
      expect(adapter.telemetry.voltageV, 0);
      expect(adapter.telemetry.batteryPct, isNull);
      expect(adapter.identity.model, isNull);
      final caps = adapter.capabilities;
      expect(caps.telemetry, isTrue);
      // Ningún comando está habilitado en esta fase; apagar y
      // bloquear ni siquiera están verificados en el protocolo.
      expect(caps.lights, isFalse);
      expect(caps.tiltBack, isFalse);
      expect(caps.speedAlarms, isFalse);
      expect(caps.pedalMode, isFalse);
      expect(caps.calibration, isFalse);
      expect(caps.motorLock, isFalse);
      expect(caps.powerOff, isFalse);
    });

    test('peticiones iniciales: «V» y «N» de solo lectura', () {
      final adapter = BegodeAdapter();
      final requests = adapter.initialRequests();
      expect(requests.length, 2);
      expect(requests[0], Uint8List.fromList([0x56])); // 'V'
      expect(requests[1], Uint8List.fromList([0x4E])); // 'N'
    });
  });
}
