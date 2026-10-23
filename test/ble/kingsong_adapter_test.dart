import 'dart:typed_data';

import 'package:euc_onewheel/services/ble/adapters/kingsong_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

/// Vectores de referencia del protocolo KingSong: tramas hex
/// reales capturadas de una rueda y los valores esperados al
/// decodificarlas.
Uint8List hex(String s) {
  final out = Uint8List(s.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(s.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

/// Escribe un campo de 2 bytes con la regla «R» (pareja invertida
/// respecto a big-endian) en la trama.
void putR2(Uint8List frame, int offset, int value) {
  frame[offset] = value & 0xFF;
  frame[offset + 1] = (value >> 8) & 0xFF;
}

/// Escribe un campo de 4 bytes con la regla «R».
void putR4(Uint8List frame, int offset, int value) {
  frame[offset] = (value >> 16) & 0xFF;
  frame[offset + 1] = (value >> 24) & 0xFF;
  frame[offset + 2] = value & 0xFF;
  frame[offset + 3] = (value >> 8) & 0xFF;
}

void main() {
  group('KingSongAdapter · datos reales (KS-S18 de referencia)', () {
    test('nombre/modelo, live, viaje: valores exactos del vector', () {
      final adapter = KingSongAdapter();

      // 1) Trama 0xBB de nombre/modelo.
      final r1 =
          adapter.decode(hex('aa554b532d5331382d30323035000000bb1484fd'));
      expect(r1, isFalse); // Solo la trama live devuelve true.
      expect(adapter.identity.model, 'KS-S18');
      expect(adapter.identity.firmware, '2.05');
      expect(adapter.telemetry.model, 'KS-S18');

      // 2) Trama 0xA9 live.
      final r2 =
          adapter.decode(hex('aa556919030200009f36d700140500e0a9145a5a'));
      expect(r2, isTrue);
      final t = adapter.telemetry;
      expect(t.speedKmh, closeTo(5.15, 1e-9));
      expect(t.voltageV, closeTo(65.05, 1e-9));
      expect(t.currentA, closeTo(2.15, 1e-9));
      expect(t.powerW, closeTo(65.05 * 2.15, 1e-6));
      expect(t.tempC, closeTo(13.0, 1e-9));
      expect(t.totalDistanceM, 13983);
      expect(t.batteryPct, 12); // curva 84 V con el modelo ya conocido
      expect(adapter.pedalMode, 0);

      // 3) Trama 0xB9 de viaje/ventilador.
      final r3 =
          adapter.decode(hex('aa550000090017011502140100004006b9145a5a'));
      expect(r3, isFalse);
      expect(adapter.telemetry.distanceM, 9);
      expect(adapter.telemetry.temp2C, closeTo(16.0, 1e-9));
      expect(adapter.fanStatus, 0);
      expect(adapter.chargingStatus, 0);
    });
  });

  group('KingSongAdapter · trama live sintética', () {
    test('voltaje 60 V, velocidad 111, temperatura 12345, sin modelo', () {
      final adapter = KingSongAdapter();
      final frame = Uint8List(20);
      frame[0] = 0xAA;
      frame[1] = 0x55;
      putR2(frame, 2, 6000); // voltaje: 60.00 V
      putR2(frame, 4, 111); // velocidad: 1.11 km/h
      putR4(frame, 6, 1234567890); // distancia total en metros
      frame[10] = 0xD7; // corriente LE: 215 → 2.15 A
      frame[11] = 0x00;
      putR2(frame, 12, 12345); // temperatura: 123.45 °C
      frame[14] = 2; // modo de pedales…
      frame[15] = 0xE0; // …válido solo si el byte 15 es 0xE0
      frame[16] = 0xA9;
      frame[17] = 0x14;
      frame[18] = 0x5A;
      frame[19] = 0x5A;

      expect(adapter.decode(frame), isTrue);
      final t = adapter.telemetry;
      expect(t.voltageV, closeTo(60.0, 1e-9));
      expect(t.speedKmh, closeTo(1.11, 1e-9));
      expect(t.tempC, closeTo(123.45, 1e-9));
      expect(t.totalDistanceM, 1234567890);
      expect(t.currentA, closeTo(2.15, 1e-9));
      // Sin modelo conocido, curva por defecto de 67.2 V:
      // (6000 − 5000) / 16 = 62 — el valor esperado de referencia.
      expect(t.batteryPct, 62);
      expect(adapter.pedalMode, 2);
    });
  });

  group('KingSongAdapter · robustez', () {
    test('datos corruptos de 0 a 29 bytes nunca decodifican', () {
      final adapter = KingSongAdapter();
      for (var len = 0; len < 30; len++) {
        final junk = Uint8List.fromList(List.generate(len, (i) => i));
        expect(adapter.decode(junk), isFalse, reason: 'len=$len');
      }
    });

    test('cabecera incorrecta o trama truncada se rechaza', () {
      final adapter = KingSongAdapter();
      final wrongHeader = hex('55aa6919030200009f36d700140500e0a9145a5a');
      expect(adapter.decode(wrongHeader), isFalse);
      final truncated = hex('aa5569190302');
      expect(adapter.decode(truncated), isFalse);
    });

    test('el snapshot inicial es neutro', () {
      final adapter = KingSongAdapter();
      expect(adapter.telemetry.speedKmh, 0);
      expect(adapter.telemetry.voltageV, 0);
      expect(adapter.telemetry.batteryPct, isNull);
      expect(adapter.identity.model, isNull);
    });
  });

  group('KingSongAdapter · número de serie (0xB3)', () {
    test('serial de 17 caracteres repartido en la trama', () {
      final adapter = KingSongAdapter();
      const serial = 'King1234567890123';
      final frame = Uint8List(20);
      frame[0] = 0xAA;
      frame[1] = 0x55;
      frame.setRange(2, 16, serial.codeUnits.sublist(0, 14));
      frame[16] = 0xB3;
      frame.setRange(17, 20, serial.codeUnits.sublist(14));
      expect(adapter.decode(frame), isFalse);
      expect(adapter.identity.serial, serial);
    });
  });

  group('KingSongAdapter · peticiones de solo lectura', () {
    test('plantilla de 20 bytes AA 55 … tipo … 14 5A 5A', () {
      final frame = KingSongAdapter.buildReadRequest(0x9B);
      expect(frame.length, 20);
      expect(frame[0], 0xAA);
      expect(frame[1], 0x55);
      expect(frame[16], 0x9B);
      expect(frame[17], 0x14);
      expect(frame[18], 0x5A);
      expect(frame[19], 0x5A);
      final adapter = KingSongAdapter();
      expect(adapter.initialRequests().length, 2);
    });
  });

  group('KingSongAdapter · curvas de batería por modelo', () {
    test('clases de voltaje nominal', () {
      // 84 V (KS-S18): 65.05 V → 12 %
      expect(KingSongAdapter.batteryLevelFor(6505, model: 'KS-S18'), 12);
      // 126 V (KS-S22): (10000 − 9375) / 30 = 20 %
      expect(KingSongAdapter.batteryLevelFor(10000, model: 'KS-S22'), 20);
      // 100.8 V (KS-S19): (8700 − 7500) / 24 = 50 %
      expect(KingSongAdapter.batteryLevelFor(8700, model: 'KS-S19'), 50);
      // Por defecto 67.2 V: extremos de la curva.
      expect(KingSongAdapter.batteryLevelFor(4900), 0);
      expect(KingSongAdapter.batteryLevelFor(6600), 100);
      expect(KingSongAdapter.batteryLevelFor(8350, model: 'KS-16X'), 100);
    });
  });
}
