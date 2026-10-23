import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:euc_onewheel/models/wheel_identity.dart';
import 'package:euc_onewheel/models/wheel_telemetry.dart';
import 'package:euc_onewheel/services/ble/adapters/veteran_adapter.dart';

Uint8List hex(String s) {
  final out = Uint8List(s.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(s.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

/// Reloj fijo: en las pruebas de vectores nunca deben pasar más
/// de 100 ms entre decodificaciones (eso reinicia el
/// desempaquetador, como en la referencia).
DateTime fixedNow() => DateTime(2026, 1, 1, 12);

VeteranAdapter newAdapter() => VeteranAdapter(clock: fixedNow);

/// Arma una trama sintética de 36 bytes (len 0x20) con los campos
/// en sus offsets del protocolo; las distancias se codifican con
/// las mitades de 16 bits intercambiadas, como viajan en la rueda.
Uint8List buildFrame({
  int voltageCv = 0,
  int speedRaw = 0,
  int tempRaw = 0,
  int tripM = 0,
  int totalM = 0,
  int phaseRaw = 0,
  int autoOff = 0,
  int verRaw = 0,
  int pedalMode = 0,
  int pitchRaw = 0,
  int pwmRaw = 0,
}) {
  final f = Uint8List(36);
  f[0] = 0xDC;
  f[1] = 0x5A;
  f[2] = 0x5C;
  f[3] = 0x20;
  void w16(int off, int v) {
    f[off] = (v >> 8) & 0xFF;
    f[off + 1] = v & 0xFF;
  }

  void wRev32(int off, int v) {
    f[off] = (v >> 8) & 0xFF;
    f[off + 1] = v & 0xFF;
    f[off + 2] = (v >> 24) & 0xFF;
    f[off + 3] = (v >> 16) & 0xFF;
  }

  w16(4, voltageCv & 0xFFFF);
  w16(6, speedRaw & 0xFFFF);
  wRev32(8, tripM);
  wRev32(12, totalM);
  w16(16, phaseRaw & 0xFFFF);
  w16(18, tempRaw & 0xFFFF);
  w16(20, autoOff);
  w16(28, verRaw);
  w16(30, pedalMode);
  w16(32, pitchRaw & 0xFFFF);
  w16(34, pwmRaw);
  return f;
}

void main() {
  group('tramas sintéticas', () {
    test('Sherman S: telemetría completa y corriente estimada', () {
      final adapter = newAdapter();
      final frame = buildFrame(
        voltageCv: 9500,
        speedRaw: -1111,
        tempRaw: 3599,
        tripM: 3231,
        totalM: 3231,
        phaseRaw: -8322,
        verRaw: 3210,
        pwmRaw: 5000,
      );

      expect(adapter.decode(frame), isTrue);

      final t = adapter.telemetry;
      expect(t.speedKmh, closeTo(-11.11, 1e-9));
      expect(t.voltageV, closeTo(95.0, 1e-9));
      expect(t.tempC, closeTo(35.99, 1e-9));
      expect(t.distanceM, 3231);
      expect(t.totalDistanceM, 3231);
      expect(t.batteryPct, 80);
      expect(t.pwmPct, closeTo(50.0, 1e-9));
      expect(t.model, 'Sherman S');
      // Corriente estimada = PWM × corriente de fase.
      expect(adapter.phaseCurrentA, closeTo(-832.2, 1e-9));
      expect(t.currentA, closeTo(-416.1, 1e-9));
      expect(t.powerW, closeTo(95.0 * -416.1, 1e-6));

      expect(adapter.identity.brand, WheelBrand.veteran);
      expect(adapter.identity.model, 'Sherman S');
      expect(adapter.identity.firmware, '003.2.10');
      expect(adapter.modelVersion, 3);
    });

    test('Patton: curva de 30 celdas y versión de modelo 4', () {
      final adapter = newAdapter();
      final frame = buildFrame(voltageCv: 11500, verRaw: 4210);

      expect(adapter.decode(frame), isTrue);
      expect(adapter.telemetry.batteryPct, 65);
      expect(adapter.telemetry.model, 'Patton');
      expect(adapter.identity.firmware, '004.2.10');
      expect(adapter.modelVersion, 4);
    });
  });

  group('vectores reales de referencia', () {
    test('placa vieja (Sherman, firmware 0)', () {
      final adapter = newAdapter();
      final r1 =
          adapter.decode(hex('DC5A5C2025D600003BF500003BF50000FFDE1399'));
      final r2 = adapter.decode(hex('0DEF0000024602460000000000000000'));

      expect(r1, isFalse);
      expect(r2, isTrue);
      final t = adapter.telemetry;
      expect(t.voltageV, closeTo(96.86, 1e-9));
      expect(t.speedKmh, closeTo(0, 1e-9));
      expect(t.tempC, closeTo(50.17, 1e-9));
      expect(adapter.phaseCurrentA, closeTo(-3.4, 1e-9));
      expect(t.distanceM, 15349);
      expect(t.totalDistanceM, 15349);
      expect(t.batteryPct, 90);
      expect(t.model, 'Sherman');
      expect(adapter.identity.firmware, '000.0.00');
    });

    test('placa nueva (firmware 51)', () {
      final adapter = newAdapter();
      final r1 =
          adapter.decode(hex('DC5A5C20238A0112121A00004D450005064611F2'));
      final r2 = adapter.decode(hex('0E1000000AF00AF0041B000300000000'));

      expect(r1, isFalse);
      expect(r2, isTrue);
      final t = adapter.telemetry;
      expect(t.voltageV, closeTo(90.98, 1e-9));
      expect(t.speedKmh, closeTo(2.74, 1e-9));
      expect(t.tempC, closeTo(45.94, 1e-9));
      expect(adapter.phaseCurrentA, closeTo(160.6, 1e-9));
      expect(t.distanceM, 4634);
      expect(t.totalDistanceM, 347461);
      expect(t.batteryPct, 60);
      expect(adapter.identity.firmware, '001.0.51');
      expect(adapter.autoOffSeconds, 3600);
    });

    test('firmware 58', () {
      final adapter = newAdapter();
      final r1 =
          adapter.decode(hex('dc5a5c2025cd0000071f0000c77800280000110b'));
      final r2 = adapter.decode(hex('0e1000010af00af00422000300140000'));

      expect(r1, isFalse);
      expect(r2, isTrue);
      final t = adapter.telemetry;
      expect(t.voltageV, closeTo(96.77, 1e-9));
      expect(t.tempC, closeTo(43.63, 1e-9));
      expect(adapter.phaseCurrentA, closeTo(0, 1e-9));
      expect(t.distanceM, 1823);
      expect(t.totalDistanceM, 2672504);
      expect(t.batteryPct, 89);
      expect(adapter.pitchDeg, closeTo(0.2, 1e-9));
      expect(adapter.identity.firmware, '001.0.58');
    });

    test('Abrams', () {
      final adapter = newAdapter();
      final r1 =
          adapter.decode(hex('dc5a5c20266d00004aaf00004aaf000000000d9e'));
      final r2 = adapter.decode(hex('0b8800000af00af007d2000300050004'));

      expect(r1, isFalse);
      expect(r2, isTrue);
      final t = adapter.telemetry;
      expect(t.voltageV, closeTo(98.37, 1e-9));
      expect(t.tempC, closeTo(34.86, 1e-9));
      expect(adapter.phaseCurrentA, closeTo(0, 1e-9));
      expect(t.distanceM, 19119);
      expect(t.totalDistanceM, 19119);
      expect(t.batteryPct, 98);
      expect(adapter.pitchDeg, closeTo(0.05, 1e-9));
      expect(t.model, 'Abrams');
      expect(adapter.identity.firmware, '002.0.02');
    });

    test('Abrams 2', () {
      final adapter = newAdapter();
      adapter.decode(hex('dc5a5c20268000004aaf00004aaf000000040ac0'));
      final r2 = adapter.decode(hex('0dff00000af00af007d20003fff80004'));

      expect(r2, isTrue);
      final t = adapter.telemetry;
      expect(t.voltageV, closeTo(98.56, 1e-9));
      expect(t.tempC, closeTo(27.52, 1e-9));
      expect(adapter.phaseCurrentA, closeTo(0.4, 1e-9));
      expect(t.batteryPct, 99);
      expect(adapter.pitchDeg, closeTo(-0.08, 1e-9));
      expect(adapter.identity.firmware, '002.0.02');
    });

    test('Abrams 3', () {
      final adapter = newAdapter();
      adapter.decode(hex('dc5a5c202719022208af000008af00000005102c'));
      final r2 = adapter.decode(hex('0e1000000af00af007d3000100091851'));

      expect(r2, isTrue);
      final t = adapter.telemetry;
      expect(t.speedKmh, closeTo(5.46, 1e-9));
      expect(t.voltageV, closeTo(100.09, 1e-9));
      expect(t.tempC, closeTo(41.40, 1e-9));
      expect(adapter.phaseCurrentA, closeTo(0.5, 1e-9));
      expect(t.distanceM, 2223);
      expect(t.totalDistanceM, 2223);
      expect(t.batteryPct, 100);
      expect(adapter.pitchDeg, closeTo(0.09, 1e-9));
      expect(adapter.identity.firmware, '002.0.03');
    });

    test('Sherman S real (trama de 38 bytes, sin CRC)', () {
      final adapter = newAdapter();
      final r1 =
          adapter.decode(hex('DC5A5C22266200000084000017A2000000000C38'));
      final r2 = adapter.decode(hex('0B03000000C600E40BBD0003188B0000006F'));

      expect(r1, isFalse);
      expect(r2, isTrue);
      final t = adapter.telemetry;
      expect(t.voltageV, closeTo(98.26, 1e-9));
      expect(t.tempC, closeTo(31.28, 1e-9));
      expect(adapter.phaseCurrentA, closeTo(0, 1e-9));
      expect(t.distanceM, 132);
      expect(t.totalDistanceM, 6050);
      expect(t.batteryPct, 97);
      expect(adapter.pitchDeg, closeTo(62.83, 1e-9));
      expect(t.model, 'Sherman S');
      expect(adapter.identity.firmware, '003.0.05');
    });

    test('Patton real (len 38, sin CRC, cierra en un tercer trozo)', () {
      final adapter = newAdapter();
      final r1 =
          adapter.decode(hex('dc5a5c26302b00001fdc00002038000000000d15'));
      final r2 =
          adapter.decode(hex('0a79000000fa01900fa700031b690000006fffff'));
      final r3 = adapter.decode(hex('5678'));

      expect(r1, isFalse);
      expect(r2, isFalse);
      expect(r3, isTrue);
      final t = adapter.telemetry;
      expect(t.voltageV, closeTo(123.31, 1e-9));
      expect(t.tempC, closeTo(33.49, 1e-9));
      expect(t.distanceM, 8156);
      expect(t.totalDistanceM, 8248);
      expect(t.batteryPct, 100);
      expect(adapter.pitchDeg, closeTo(70.17, 1e-9));
      expect(t.model, 'Patton');
      expect(adapter.identity.firmware, '004.0.07');
    });

    test('Patton con CRC32 (formato nuevo)', () {
      final adapter = newAdapter();
      final results = <bool>[
        adapter.decode(hex('dc5a5c452abe00003edc00008562003500000b5c')),
        adapter.decode(hex('0dfe000002bc07d00fac000219fb0000006f0000')),
        adapter.decode(hex('80808080808004000014ffffffffff32ee029109')),
        adapter.decode(hex('df0fd303cb000000006f9a79c2')),
      ];

      expect(results, [false, false, false, true]);
      final t = adapter.telemetry;
      expect(t.voltageV, closeTo(109.42, 1e-9));
      expect(t.tempC, closeTo(29.08, 1e-9));
      expect(t.distanceM, 16092);
      expect(t.totalDistanceM, 3507554);
      expect(t.batteryPct, 42);
      expect(adapter.pitchDeg, closeTo(66.51, 1e-9));
      expect(t.model, 'Patton');
      expect(adapter.identity.firmware, '004.0.12');
    });

    test('tras validar un CRC, una trama vieja sin CRC se rechaza', () {
      final adapter = newAdapter();
      // Primero, una trama del formato nuevo válida (Patton CRC).
      adapter.decode(hex('dc5a5c452abe00003edc00008562003500000b5c'));
      adapter.decode(hex('0dfe000002bc07d00fac000219fb0000006f0000'));
      adapter.decode(hex('80808080808004000014ffffffffff32ee029109'));
      expect(adapter.decode(hex('df0fd303cb000000006f9a79c2')), isTrue);
      expect(adapter.telemetry.voltageV, closeTo(109.42, 1e-9));

      // El latch de CRC queda activo: la trama corta sin CRC de
      // una Sherman S ya no se acepta y la telemetría no cambia.
      final r1 =
          adapter.decode(hex('DC5A5C22266200000084000017A2000000000C38'));
      final r2 = adapter.decode(hex('0B03000000C600E40BBD0003188B0000006F'));
      expect(r1, isFalse);
      expect(r2, isFalse);
      expect(adapter.telemetry.voltageV, closeTo(109.42, 1e-9));
    });

    test('Lynx con CRC32 y paquete SmartBMS', () {
      final adapter = newAdapter();
      final results = <bool>[
        adapter.decode(hex('dc5a5c53391b000006d000000770000000260bcc')),
        adapter.decode(hex('0e08000000fa00c8138c00b4000b014c80c80000')),
        adapter.decode(hex('808080808080010008808080800fee0fee0fee0f')),
        adapter.decode(hex('ee0fef0fe80fef0fef0ff00ff00ff00fea0fef0f')),
        adapter.decode(hex('ef0fefdab22518')),
      ];

      expect(results, [false, false, false, false, true]);
      final t = adapter.telemetry;
      expect(t.voltageV, closeTo(146.19, 1e-9));
      expect(t.tempC, closeTo(30.20, 1e-9));
      expect(adapter.phaseCurrentA, closeTo(3.8, 1e-9));
      expect(t.distanceM, 1744);
      expect(t.totalDistanceM, 1904);
      expect(t.batteryPct, 94);
      expect(adapter.pitchDeg, closeTo(0.11, 1e-9));
      expect(adapter.alertSpeedKmh, closeTo(2.5, 1e-9));
      expect(adapter.tiltBackSpeedKmh, closeTo(2.0, 1e-9));
      expect(t.model, 'Lynx');
      expect(adapter.identity.firmware, '005.0.04');
      // El byte 46 trae el paquete SmartBMS 1: quedó registrado.
      expect(adapter.hasBmsData, isTrue);
    });

    test('Sherman L con CRC32', () {
      final adapter = newAdapter();
      final results = <bool>[
        adapter.decode(hex('dc5a5c53397afffe0aa400000df10000000a0b3d')),
        adapter.decode(hex('0e0e0000037a035217730064000e00b480c80000')),
        adapter.decode(hex('808080808080058080808080800ff30ff50ff50f')),
        adapter.decode(hex('f50ff50fef0ff20ff30ff30ff30ff30fed0ff30f')),
        adapter.decode(hex('f40ff5378c5145')),
      ];

      expect(results, [false, false, false, false, true]);
      final t = adapter.telemetry;
      expect(t.speedKmh, closeTo(-0.02, 1e-9));
      expect(t.voltageV, closeTo(147.14, 1e-9));
      expect(t.tempC, closeTo(28.77, 1e-9));
      expect(adapter.phaseCurrentA, closeTo(1.0, 1e-9));
      expect(t.distanceM, 2724);
      expect(t.totalDistanceM, 3569);
      expect(t.batteryPct, 97);
      expect(adapter.pitchDeg, closeTo(0.14, 1e-9));
      expect(t.model, 'Sherman L');
      expect(adapter.identity.firmware, '006.0.03');
    });

    test('Patton S con CRC32 y SmartBMS (paquete 6)', () {
      final adapter = newAdapter();
      final results = <bool>[
        adapter.decode(hex('dc5a5c532c4c0000615400006406000000000ce0')),
        adapter.decode(hex('01a0000002bc02ee1b5900821a63000080c80000')),
        adapter.decode(hex('808080808080068080808080800ec20ec20ec20e')),
        adapter.decode(hex('c30ec20ebd0ec20ec30ec20ec30ec30ebd0ec30e')),
        adapter.decode(hex('c30ec08edbd62e')),
      ];

      expect(results, [false, false, false, false, true]);
      final t = adapter.telemetry;
      expect(t.voltageV, closeTo(113.40, 1e-9));
      expect(t.tempC, closeTo(32.96, 1e-9));
      expect(t.distanceM, 24916);
      expect(t.totalDistanceM, 25606);
      expect(t.batteryPct, 59);
      expect(adapter.pitchDeg, closeTo(67.55, 1e-9));
      expect(t.model, 'Patton S');
      expect(adapter.identity.firmware, '007.0.01');
      // Paquete 6 = celdas 15–29 del BMS 2 (u16 en el offset 53).
      expect(adapter.bms2CellVoltages[15], closeTo(3.778, 1e-9));
      expect(adapter.detectedCells, 15);
    });

    test('Patton S 2 con SmartBMS (paquete 5, celdas del BMS 2)', () {
      final adapter = newAdapter();
      final results = <bool>[
        adapter.decode(hex('dc5a5c5331490000ceba0002c160000300000b40')),
        adapter.decode(hex('03810000025802581b5a00961bfc000080c80000')),
        adapter.decode(hex('8080808080800500000000801e10591058105910')),
        adapter.decode(hex('5a1059105310591058105a105a105b1055105510')),
        adapter.decode(hex('57105105bf349e')),
      ];

      expect(results, [false, false, false, false, true]);
      final t = adapter.telemetry;
      expect(t.voltageV, closeTo(126.17, 1e-9));
      expect(t.tempC, closeTo(28.80, 1e-9));
      expect(t.distanceM, 183994);
      expect(t.totalDistanceM, 246112);
      expect(t.batteryPct, 100);
      expect(adapter.pitchDeg, closeTo(71.64, 1e-9));
      expect(adapter.identity.firmware, '007.0.02');
      // Paquete 5 = celdas 0–14 del BMS 2 (s16 en el offset 53).
      expect(adapter.hasBmsData, isTrue);
      expect(adapter.bms2CellVoltages[0], closeTo(4.185, 1e-9));
      expect(adapter.bms2CellVoltages[1], closeTo(4.184, 1e-9));
      expect(adapter.detectedCells, 15);
    });

    test('Patton S 3 (trama de 75 bytes con CRC)', () {
      final adapter = newAdapter();
      final results = <bool>[
        adapter.decode(hex('dc5a5c47314d0000ceba0002c160000300000b3f')),
        adapter.decode(hex('03820000025802581b5a00961bf7000080c80000')),
        adapter.decode(hex('8080808080800300000000000000000000000000')),
        adapter.decode(hex('0000000000000000000000b2ce8d4a')),
      ];

      expect(results, [false, false, false, true]);
      final t = adapter.telemetry;
      expect(t.voltageV, closeTo(126.21, 1e-9));
      expect(t.tempC, closeTo(28.79, 1e-9));
      expect(t.distanceM, 183994);
      expect(t.totalDistanceM, 246112);
      expect(t.batteryPct, 100);
      expect(adapter.pitchDeg, closeTo(71.59, 1e-9));
      expect(adapter.identity.firmware, '007.0.02');
      // Paquete 3: temperaturas y celdas altas del BMS 1.
      expect(adapter.hasBmsData, isTrue);
    });
  });

  group('flujo sucio', () {
    test('basura entrelazada: resincroniza y recupera las tramas', () {
      final adapter = newAdapter();
      const chunks = <String>[
        'dc5a5c2024dc02130a0a00001179005200450f47',
        '0e1000000af00af0041d000300000000dc5a5c20',
        '2467020f0a0d0000117c005201070a1900001188',
        '0052ffe10f350e1000000af00af0041d00030000',
        '0000dc5a5c20251501fb0a1c0000118b0052ffe6',
        '0f350e1000000af00af0041d000300000000dc5a',
        '5c2024ef01f70a1f0000118e005200470f350e10',
        '00000af00af0041d000300000000dc5a5c2024fc',
        '01ec0a22000011910052001e0f3e0e1000000af0',
        '0af0041d000300000000dc5a5c2024b601e80a24',
        '000011930052dc5a5c2024e9000052023a0f3e0e',
        '1000000af00af0041d000300000000dc5a5c2023',
        'c302100a5100001100dc5a5c20248702320a5e00',
        '000af00af0041d000300000000dc5a5c20250220',
        '0a9800001207005201cf0f350e1000000af00af0',
        '041d000300000000dc5a5c2023e602250a9b0000',
        '120a005202610f2b0e1000000af00af0041d0003',
        '00000000dc5a5c20241202260a9e0000120d0052',
        '02010f350e1000000af00af0041d000300000000',
        'dc5a5c202405022e0aa100001210005201f70f2b',
      ];
      const expectedResults = <bool>[
        false,
        true,
        false,
        false,
        false,
        true,
        false,
        true,
        false,
        true,
        false,
        false,
        false,
        false,
        false,
        false,
        false,
        true,
        true,
        false,
      ];
      // La velocidad persiste entre decodificaciones (última trama).
      const expectedSpeeds = <double>[
        0,
        5.31,
        5.31,
        5.31,
        5.31,
        5.07,
        5.07,
        5.03,
        5.03,
        4.92,
        4.92,
        4.92,
        4.92,
        4.92,
        4.92,
        4.92,
        4.92,
        5.49,
        5.50,
        5.50,
      ];

      for (var i = 0; i < chunks.length; i++) {
        final result = adapter.decode(hex(chunks[i]));
        expect(result, expectedResults[i], reason: 'trozo ${i + 1}');
        expect(adapter.telemetry.speedKmh, closeTo(expectedSpeeds[i], 1e-9),
            reason: 'velocidad tras el trozo ${i + 1}');
      }
    });

    test('datos corruptos acumulados (bytes 0..29) nunca decodifican', () {
      final adapter = newAdapter();
      for (var n = 1; n <= 30; n++) {
        final data = Uint8List.fromList(List<int>.generate(n, (i) => i));
        expect(adapter.decode(data), isFalse, reason: 'n = $n');
      }
      expect(adapter.telemetry, WheelTelemetry.neutral);
    });

    test('silencio de más de 100 ms: la trama a medias se pierde', () {
      var now = DateTime(2026, 1, 1, 12);
      final adapter = VeteranAdapter(clock: () => now);
      final frame = hex('DC5A5C20238A0112121A00004D450005064611F2'
          '0E1000000AF00AF0041B000300000000');

      expect(adapter.decode(Uint8List.sublistView(frame, 0, 20)), isFalse);
      now = now.add(const Duration(milliseconds: 150));
      // El resto llega tarde: el desempaquetador se reinició.
      expect(adapter.decode(Uint8List.sublistView(frame, 20)), isFalse);
      expect(adapter.telemetry.voltageV, 0);

      now = now.add(const Duration(milliseconds: 10));
      expect(adapter.decode(frame), isTrue);
      expect(adapter.telemetry.voltageV, closeTo(90.98, 1e-9));
    });
  });

  group('base', () {
    test('sin tramas, la telemetría es neutra', () {
      final adapter = newAdapter();
      expect(adapter.telemetry, WheelTelemetry.neutral);
      expect(adapter.identity.brand, WheelBrand.unknown);
      expect(adapter.identity.model, isNull);
      expect(adapter.hasBmsData, isFalse);
      expect(adapter.detectedCells, 0);
    });

    test('capacidades: telemetría + luz, pedales y beep verificados', () {
      final caps = newAdapter().capabilities;
      expect(caps.telemetry, isTrue);
      expect(caps.lights, isTrue);
      expect(caps.pedalMode, isTrue);
      expect(caps.beep, isTrue);
      // El resto no está verificado en la referencia para Veteran.
      expect(caps.tiltBack, isFalse);
      expect(caps.speedAlarms, isFalse);
      expect(caps.calibration, isFalse);
      expect(caps.motorLock, isFalse);
      expect(caps.powerOff, isFalse);
    });

    test('sin peticiones iniciales: la rueda emite en continuo', () {
      expect(newAdapter().initialRequests(), isEmpty);
    });

    test('crc32 coincide con el valor de control estándar', () {
      final digits = '123456789'.codeUnits;
      expect(VeteranAdapter.crc32(digits, 0, digits.length - 1), 0xCBF43926);
    });

    test('modelos, versiones y celdas según la versión de modelo', () {
      expect(VeteranAdapter.modelNameFor(0), 'Sherman');
      expect(VeteranAdapter.modelNameFor(1), 'Sherman');
      expect(VeteranAdapter.modelNameFor(2), 'Abrams');
      expect(VeteranAdapter.modelNameFor(3), 'Sherman S');
      expect(VeteranAdapter.modelNameFor(4), 'Patton');
      expect(VeteranAdapter.modelNameFor(5), 'Lynx');
      expect(VeteranAdapter.modelNameFor(6), 'Sherman L');
      expect(VeteranAdapter.modelNameFor(7), 'Patton S');
      expect(VeteranAdapter.modelNameFor(8), 'Oryx');
      expect(VeteranAdapter.modelNameFor(9), 'Lynx S');
      expect(VeteranAdapter.modelNameFor(42), 'Nosfet Apex');
      expect(VeteranAdapter.modelNameFor(43), 'Nosfet Aero');
      expect(VeteranAdapter.modelNameFor(44), 'Nosfet Aeon');
      expect(VeteranAdapter.modelNameFor(10), 'Unknown');

      expect(VeteranAdapter.versionStringFor(0), '000.0.00');
      expect(VeteranAdapter.versionStringFor(1051), '001.0.51');
      expect(VeteranAdapter.versionStringFor(3210), '003.2.10');
      expect(VeteranAdapter.versionStringFor(5004), '005.0.04');
      expect(VeteranAdapter.versionStringFor(7002), '007.0.02');

      expect(VeteranAdapter.cellsForModelVersion(2), 24);
      expect(VeteranAdapter.cellsForModelVersion(4), 30);
      expect(VeteranAdapter.cellsForModelVersion(7), 30);
      expect(VeteranAdapter.cellsForModelVersion(43), 30);
      expect(VeteranAdapter.cellsForModelVersion(8), 42);
      expect(VeteranAdapter.cellsForModelVersion(5), 36);
      expect(VeteranAdapter.cellsForModelVersion(42), 36);
    });

    test('curvas de batería por familia de voltaje', () {
      // 24 celdas (versiones < 4).
      expect(VeteranAdapter.batteryLevelFor(7935, 2), 0);
      expect(VeteranAdapter.batteryLevelFor(9870, 2), 100);
      expect(VeteranAdapter.batteryLevelFor(9500, 3), 80);
      // 30 celdas (4, 7, 43).
      expect(VeteranAdapter.batteryLevelFor(11500, 4), 65);
      expect(VeteranAdapter.batteryLevelFor(11340, 7), 59);
      // 36 celdas (5, 6, 9, 42, 44).
      expect(VeteranAdapter.batteryLevelFor(14619, 5), 94);
      // 42 celdas (8).
      expect(VeteranAdapter.batteryLevelFor(13886, 8), 0);
      expect(VeteranAdapter.batteryLevelFor(17272, 8), 100);
      // Versión sin curva conocida: 1, como la referencia.
      expect(VeteranAdapter.batteryLevelFor(9000, 10), 1);
    });
  });
}
