import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';


import 'package:euc_onewheel/models/wheel_identity.dart';
import 'package:euc_onewheel/services/ble/adapters/inmotion_adapter.dart';

Uint8List hex(String s) {
  final clean = s.replaceAll(' ', '');
  final out = Uint8List(clean.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

String hexStr(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

// Tramas de identidad comunes (respuestas reales del protocolo).
const carTypeV11 = 'AAAA110882010206010201009C';
const carTypeV11y = 'aaaa110882010206020101009c';
const carTypeV12hs = 'aaaa110882010207010103009c';
const carTypeV12pro = 'aaaa110882010207030101009c';
const carTypeV13 = 'aaaa1108820102080101010091';
const carTypeV14s = 'aaaa1108820102090201010093';
const carTypeV9 = 'aaaa11088201020c0101010095';
const carTypeV12s = 'aaaa11088201020b0101010092';
const versionsV11Old =
    'AAAA111D820622080004030F000602214000010110000602230D00010107000001F3';

void main() {
  group('InMotionAdapter — contrato', () {
    test('marca InMotion V2, telemetría y controles verificados', () {
      final a = InMotionAdapter();
      expect(a.brand, WheelBrand.inmotionV2);
      expect(a.capabilities.telemetry, isTrue);
      expect(a.capabilities.lights, isTrue);
      expect(a.capabilities.powerOff, isTrue);
      expect(a.capabilities.motorLock, isTrue);
      expect(a.capabilities.calibration, isTrue);
      expect(a.capabilities.tiltBack, isTrue);
      expect(a.capabilities.transportMode, isTrue);
    });

    test('peticiones iniciales y de sondeo: tramas exactas', () {
      final a = InMotionAdapter();
      final initial = a.initialRequests();
      expect(initial, hasLength(7));
      // getCarType: AA AA | 11 02 02 01 | XOR 10.
      expect(hexStr(initial[0]), 'aaaa1102020110');
      // getSerialNumber y getVersions comparten cabecera MainInfo.
      expect(hexStr(initial[1]), 'aaaa1102020213');
      expect(hexStr(initial[2]), 'aaaa1102020617');
      // getStatistics: AA AA | 14 01 11 | XOR 04.
      expect(hexStr(initial[4]), 'aaaa14011104');
      // getRealTimeData: AA AA | 14 01 04 | XOR 11.
      expect(hexStr(initial[5]), 'aaaa14010411');
      // getSettings (build #13): AA AA | 14 02 20 20 | XOR 16.
      expect(hexStr(initial[6]), 'aaaa1402202016');
      expect(hexStr(a.settingsRequest!), 'aaaa1402202016');
      // El sondeo repite batería, estadísticas y tiempo real.
      expect(a.pollInterval, const Duration(milliseconds: 300));
      final poll = a.pollRequests();
      expect(poll, hasLength(3));
      expect(hexStr(poll[2]), 'aaaa14010411');
    });

    test('sin tramas, la telemetría nace neutra y sin modelo', () {
      final a = InMotionAdapter();
      expect(a.telemetry.speedKmh, 0);
      expect(a.telemetry.batteryPct, isNull);
      expect(a.modelName, isNull);
      expect(a.protocolVersion, 0);
      expect(a.reportedMaxKmh, isNull);
      expect(a.reportedAlarmKmh, isNull);
    });

    test('trama de ajustes: reporta máxima y alarma guardadas', () {
      final a = InMotionAdapter();
      // Respuesta de ajustes: flags 14, comando 20, datos de 36
      // bytes (máxima 45.00 en 1, alarma 30.00 en 3, resto ceros).
      final data = List<int>.filled(36, 0);
      data[1] = 0x94;
      data[2] = 0x11; // 0x1194 = 4500 → 45.00 km/h.
      data[3] = 0xB8;
      data[4] = 0x0B; // 0x0BB8 = 3000 → 30.00 km/h.
      final frame = InMotionAdapter.buildMessage(
          flags: 0x14, command: 0x20, data: data);
      expect(a.decode(frame), isFalse); // No es telemetría en vivo.
      expect(a.reportedMaxKmh, 45.0);
      expect(a.reportedAlarmKmh, 30.0);
    });

    test('trama de ajustes truncada no publica valores', () {
      final a = InMotionAdapter();
      final frame = InMotionAdapter.buildMessage(
          flags: 0x14, command: 0x20, data: const [0x00, 0x94, 0x11]);
      a.decode(frame);
      expect(a.reportedMaxKmh, isNull);
      expect(a.reportedAlarmKmh, isNull);
    });
  });

  group('InMotionAdapter — V11 (placa anterior a 1.4)', () {
    test('secuencia completa real: identidad y telemetría', () {
      final a = InMotionAdapter();
      final results = <bool>[
        a.decode(hex(carTypeV11)), // tipo de vehículo
        a.decode(hex(
            'AAAA11178202313438304341313232323037303032420000000000FD')), // serie
        a.decode(hex(versionsV11Old)), // versiones
        a.decode(hex(
            'AAAA141AA0207C15C800106464140000000058020000006400001500100010')), // ajustes
        a.decode(hex(
            'AAAA142B900001142614000000803E498AE00FB209D109CEB000C7DF010000BE720000AB1300008F040000AB0600004C')), // cmd 0x10
        a.decode(hex(
            'AAAA141991E86C000066191C002DB2040064E60000974D050000C7DF01A4')), // totales
        a.decode(hex(
            'AAAA143184E61EEB0561094A11AE04A004DF01402958CBB000CE004A010000D4FF7C15641900000000492B00000000000000000000C6')), // tiempo real
      ];
      expect(results, [false, false, false, false, false, false, true]);

      expect(a.identity.model, 'Inmotion V11');
      expect(a.identity.serial, '1480CA122207002B');
      expect(a.identity.firmware, 'Main:1.1.64 Drv:3.4.8 BLE:1.1.13');
      expect(a.protocolVersion, 1); // Main 1.1.64 < 1.4

      final t = a.telemetry;
      expect(t.model, 'Inmotion V11');
      expect(t.speedKmh, 24.01);
      expect(t.voltageV, 79.10);
      expect(t.currentA, 15.15);
      expect(t.powerW, 1198.0);
      expect(t.batteryPct, 88);
      expect(t.tempC, 27.0);
      expect(t.temp2C, 30.0);
      expect(t.distanceM, 4790);
      expect(t.totalDistanceM, 278800);
      expect(a.torqueNm, 44.26);
      expect(a.motorPowerW, 1184.0);
      expect(a.pitchDeg, 3.3);
      expect(a.rollDeg, -0.44);
      expect(a.dynamicSpeedLimitKmh, 55.00);
      expect(a.dynamicCurrentLimitA, 65.00);
      expect(a.remainMileageM, 105600);
      expect(a.cpuTempC, -176);
      expect(a.imuTempC, -176);
    });

    test('trama con escapes A5 AA y A5 A5 (modelo ya fijado)', () {
      final a = InMotionAdapter();
      a.decode(hex(carTypeV11));
      final ok = a.decode(hex(
          'aaaa1431843020a5a50068025207870080009400882c5fc4b000d7001000f4ff2b037c1564190000d9d9492b00000000000000000000a5a5'));
      expect(ok, isTrue);
      final t = a.telemetry;
      expect(t.speedKmh, 6.16);
      expect(t.voltageV, 82.40);
      expect(t.currentA, 1.65);
      expect(t.powerW, 135.0);
      expect(t.batteryPct, 95);
      expect(t.tempC, 20.0);
      expect(t.temp2C, 39.0);
      expect(t.distanceM, 1480);
      expect(a.torqueNm, 18.74);
      expect(a.motorPowerW, 128.0);
      expect(a.pitchDeg, 0.16);
      expect(a.rollDeg, 8.11);
      expect(a.cpuTempC, 41);
      expect(a.imuTempC, 41);
    });

    test('firmware nuevo con PWM (protocolo 1)', () {
      final a = InMotionAdapter();
      a.decode(hex(carTypeV11));
      a.decode(hex(versionsV11Old)); // fija protocolo 1
      expect(a.protocolVersion, 1);
      final ok = a.decode(hex(
          'aaaa143384411f8e03a5a506e90bd80242021600122a5acbb000cc002a0000000bfd7c1564190000d4d1ff09490a0000000000000000000010'));
      expect(ok, isTrue);
      final t = a.telemetry;
      expect(t.speedKmh, 17.01);
      expect(t.voltageV, 80.01);
      expect(t.currentA, 9.1);
      expect(t.powerW, 728.0);
      expect(t.batteryPct, 90);
      expect(t.tempC, 27.0);
      expect(t.temp2C, 28.0);
      expect(t.distanceM, 220);
      expect(a.torqueNm, 30.49);
      expect(a.motorPowerW, 578.0);
      expect(a.pitchDeg, 0.42);
      expect(a.rollDeg, -7.57);
    });

    test('segunda trama con escapes (protocolo 1)', () {
      final a = InMotionAdapter();
      a.decode(hex(carTypeV11));
      a.decode(hex(versionsV11Old));
      final ok = a.decode(hex(
          'aaaa143184a5aa1e8100640b1301650059001504a0234cc0b000ce00180000007c007c1564190000d1d3492b00000000000000000000a5a5'));
      expect(ok, isTrue);
      final t = a.telemetry;
      expect(t.speedKmh, 29.16);
      expect(t.voltageV, 78.50);
      expect(t.currentA, 1.29);
      expect(t.powerW, 101.0);
      expect(t.batteryPct, 76);
      expect(t.tempC, 16.0);
      expect(t.temp2C, 30.0);
      expect(t.distanceM, 10450);
      expect(a.torqueNm, 2.75);
      expect(a.motorPowerW, 89.0);
      expect(a.pitchDeg, 0.24);
      expect(a.rollDeg, 1.24);
    });

    test('sin modelo conocido, el tiempo real cae al layout V11 clásico', () {
      final a = InMotionAdapter();
      final ok = a.decode(hex(
          'AAAA143184E61EEB0561094A11AE04A004DF01402958CBB000CE004A010000D4FF7C15641900000000492B00000000000000000000C6'));
      expect(ok, isTrue);
      expect(a.telemetry.speedKmh, 24.01);
      expect(a.telemetry.model, isNull);
    });
  });

  group('InMotionAdapter — V11 placa 1.4+ (protocolo 2)', () {
    test('versiones 1.4.0 fijan el protocolo 2 y el layout nuevo', () {
      final a = InMotionAdapter();
      a.decode(hex(carTypeV11));
      final rVer = a.decode(hex(
          'aaaa111d820622000003040300070221000004011a000602230d00010107000001b9'));
      expect(rVer, isFalse);
      expect(a.identity.firmware, 'Main:1.4.0 Drv:4.3.0 BLE:1.1.13');
      expect(a.protocolVersion, 2);

      final ok = a.decode(hex(
          'aaaa1445842d1d10000000efff070000000000000000002b0300000000000000008a149612e02e8813641900000000cbb000cccad1000028000000000049140000000000000000000021'));
      expect(ok, isTrue);
      final t = a.telemetry;
      expect(t.speedKmh, 0.0);
      expect(t.voltageV, 74.69);
      expect(t.currentA, 0.16);
      expect(t.powerW, 0.0);
      expect(t.batteryPct, 53);
      expect(t.tempC, 27.0);
      expect(t.temp2C, 28.0);
      expect(t.distanceM, 0);
      expect(a.torqueNm, -0.17);
      expect(a.dynamicSpeedLimitKmh, 50.00);
      expect(a.dynamicCurrentLimitA, 65.00);
    });

    test('versiones de una V12 con el modelo aún en V11', () {
      final a = InMotionAdapter();
      a.decode(hex(carTypeV11));
      final r = a.decode(hex(
          'aaaa111d820622790002042000060221040005017d000602233700010203000402bb'));
      expect(r, isFalse);
      expect(a.identity.firmware, 'Main:1.5.4 Drv:4.2.121 BLE:2.1.55');
    });
  });

  group('InMotionAdapter — V12', () {
    test('secuencia completa real (V12 HS, primera trama en vivo)', () {
      final a = InMotionAdapter();
      final results = <bool>[
        a.decode(hex(carTypeV12hs)),
        a.decode(
            hex('aaaa11178202413033313135353133303030393733300000000000fb')),
        a.decode(hex(
            'aaaa111d820622700002042000060221180004017d000602232400010203000402bc')),
        a.decode(hex(
            'aaaa142b900001082608000000c1b55622330000000000cdceb0ce0000000000000000000000000000000008000000ce')),
        a.decode(hex(
            'aaaa1419916350000074471800d1140400c68e00007d350200b0ce000039')),
        a.decode(hex(
            'aaaa144384cd26090000000e00040000000000000000000000eafb000062009d2450463b1b581b000000000000cdce00ced1d0b03d2828000000004900000000000000000000008c')),
      ];
      expect(results, [false, false, false, false, false, true]);
      expect(a.identity.model, 'Inmotion V12 HS');
      expect(a.identity.serial, 'A031155130009730');
      expect(a.identity.firmware, 'Main:1.4.24 Drv:4.2.112 BLE:2.1.36');
      final t = a.telemetry;
      expect(t.speedKmh, 0.0);
      expect(t.voltageV, 99.33);
      expect(t.currentA, 0.09);
      // 1 %: así lo reporta esta rueda con su firmware (la
      // referencia lo documenta como fallo del firmware viejo).
      expect(t.batteryPct, 1);
      expect(t.tempC, 29.0);
      expect(t.temp2C, 30.0);
      expect(t.totalDistanceM, 205790);
      expect(a.torqueNm, 0.14);
      expect(a.rollDeg, -10.46);
      expect(a.dynamicSpeedLimitKmh, 69.71);
      expect(a.dynamicCurrentLimitA, 70.00);
      expect(a.cpuTempC, 33);
      expect(a.imuTempC, 32);
    });

    test('secuencia completa real (V12 HS, rodando)', () {
      final a = InMotionAdapter();
      a.decode(hex(carTypeV12hs));
      a.decode(hex('aaaa11178202413033313135353133303030393733300000000000fb'));
      a.decode(hex(
          'aaaa111d820622700002042000060221180004017d000602232400010203000402bc'));
      a.decode(
          hex('aaaa1419916350000074471800d1140400c68e00007d350200b0ce000039'));
      final ok = a.decode(hex(
          'aaaa144384ae24600479135909c61536085a0b00003f000000eb003700a5aa21b61f50463b1b581b000000000000ddd900dfe5e4b0f9646400000000490800000000000000000000dd'));
      expect(ok, isTrue);
      final t = a.telemetry;
      expect(t.speedKmh, 49.85);
      expect(t.voltageV, 93.90);
      expect(t.currentA, 11.20);
      expect(t.powerW, 2102.0);
      expect(t.batteryPct, 86);
      expect(t.tempC, 45.0);
      expect(t.temp2C, 41.0);
      expect(t.distanceM, 550);
      expect(t.totalDistanceM, 205790);
      expect(a.torqueNm, 23.93);
      expect(a.motorPowerW, 2906.0);
      expect(a.pitchDeg, 0.63);
      expect(a.rollDeg, 2.35);
    });

    test('datos 3 y 4 con el modelo ya fijado', () {
      final a = InMotionAdapter();
      a.decode(hex(carTypeV12hs));
      var ok = a.decode(hex(
          'aaaa14438415273500930496014b0535003a0000008d000000fdfe010010271c255046581b581b000000000000ceca00cfd1d0b08d646400000000490000000000000000000000bc'));
      expect(ok, isTrue);
      var t = a.telemetry;
      expect(t.speedKmh, 11.71);
      expect(t.voltageV, 100.05);
      expect(t.currentA, 0.53);
      expect(t.powerW, 53.0);
      expect(t.batteryPct, 100);
      expect(t.distanceM, 10);
      expect(a.torqueNm, 4.06);
      expect(a.pitchDeg, 1.41);
      expect(a.rollDeg, -2.59);

      ok = a.decode(hex(
          'aaaa1443842627090000000000060000000000000000000000b3fd000010271c255046581b581b000000000000ceca00ced0cfb048282800000000490000000000000000000000ef'));
      expect(ok, isTrue);
      t = a.telemetry;
      expect(t.speedKmh, 0.0);
      expect(t.voltageV, 100.22);
      expect(t.batteryPct, 100);
      expect(a.rollDeg, -5.89);
    });

    test('secuencia completa real (V12 Pro)', () {
      final a = InMotionAdapter();
      final results = <bool>[
        a.decode(hex(carTypeV12pro)),
        a.decode(
            hex('aaaa11178202413033313138333135303031333832340000000000f7')),
        a.decode(hex(
            'aaaa111d820622120005060300080221100007016b00080223420001020000050281')),
        a.decode(hex(
            'aaaa142ca0200000000006030008e0151815111600004038114b6464010028646428b80b45450000000000000db0000067')),
        a.decode(hex(
            'aaaa142b90000140264f000000c5708649380000000000c8c8b0c8000000000000000000000000000000001a000000a7')),
        a.decode(hex(
            'aaaa141991e12603006567dd00f6f117001cf40400954f1300b0c80000ca')),
        a.decode(hex(
            'aaaa144384b7261100000085ff5c00000000000000fcff0000eafe000076266d26803ee015581b000000000000c8c800c9b0c7b0b700000000000049000000000000000000000081')),
      ];
      expect(results, [false, false, false, false, false, false, true]);
      expect(a.identity.model, 'Inmotion V12 PRO');
      expect(a.identity.serial, 'A031183150013824');
      expect(a.identity.firmware, 'Main:1.7.16 Drv:6.5.18 BLE:2.1.66');
      final t = a.telemetry;
      expect(t.speedKmh, 0.0);
      expect(t.voltageV, 99.11);
      expect(t.currentA, 0.17);
      expect(t.batteryPct, 98);
      expect(t.tempC, 24.0);
      expect(t.temp2C, 24.0);
      expect(t.totalDistanceM, 2065610);
      expect(a.torqueNm, -1.23);
      expect(a.pitchDeg, -0.04);
      expect(a.rollDeg, -2.78);
      expect(a.dynamicSpeedLimitKmh, 56.00);
    });
  });

  group('InMotionAdapter — V13 y V14', () {
    test('secuencia completa real (V13)', () {
      final a = InMotionAdapter();
      final results = <bool>[
        a.decode(hex(carTypeV13)),
        a.decode(
            hex('aaaa111782024130333131364231383030303130343600000000008a')),
        a.decode(hex(
            'aaaa112f8206223a000005030008022115000002cf000802230a0002020000050224070001010200010125070001010200010172')),
        a.decode(hex(
            'aaaa142b9000010126010000004390a7d5010251000701cdcec9d000000000080000000000000004000000070000006c')),
        a.decode(hex(
            'aaaa1419915e010000b7660000500900008c0600002d8b0000c9d000007e')),
        a.decode(hex(
            'aaaa145984092f3807000036003735000025130f27b108111d4203b00664fee703050000000000f225e225204e28233421401f401f204e401f709400000000cdccc9d1b0d10000b0286400000000004910000000000000001800000000b3')),
      ];
      expect(results, [false, false, false, false, false, true]);
      expect(a.identity.model, 'Inmotion V13');
      expect(a.identity.serial, 'A03116B180001046');
      expect(a.identity.firmware, 'Main:2.0.21 Drv:5.0.58 BLE:2.2.10');
      final t = a.telemetry;
      expect(t.speedKmh, 136.23);
      expect(t.voltageV, 120.41);
      expect(t.currentA, 18.48);
      expect(t.powerW, 2225.0);
      expect(t.batteryPct, 97);
      expect(t.tempC, 29.0);
      expect(t.temp2C, 28.0);
      expect(t.distanceM, 4901);
      expect(t.totalDistanceM, 3500);
      expect(a.torqueNm, 74.41);
      expect(a.motorPowerW, 1712.0);
      expect(a.pitchDeg, 0.54);
      expect(a.rollDeg, -4.12);
      expect(a.dynamicSpeedLimitKmh, 90.00);
      expect(a.dynamicCurrentLimitA, 80.00);
    });

    test('secuencia completa real (V14 50S)', () {
      final a = InMotionAdapter();
      final results = <bool>[
        a.decode(hex(carTypeV14s)),
        a.decode(
            hex('aaaa1117820241303332313743304230303131323245000000000084')),
        a.decode(hex(
            'aaaa11418206223c00060503000802212800000301000902230100000208000201240200000501000204260200000501000204250200000501000204270200000501000204eb')),
        a.decode(hex(
            'aaaa142b9000011d261d00000044c5895e2c08ac049205d0d1cbd0510000001e0f0000fc010000070100003401000051')),
        a.decode(hex(
            'aaaa1419911d9c000059293800d01106007134010097110600cbd051001c')),
        a.decode(hex(
            'aaaa1459847c334000000000002c0800009900430866004f002700efff6400bfff5e0000000000a5aa26a4261027581b581b401f401f401f401fb88800000000cdcfcad0b0d00000b0cc640000000000491000000000000000000000000064')),
      ];
      expect(results, [false, false, false, false, false, true]);
      expect(a.identity.model, 'Inmotion V14 50S');
      expect(a.identity.serial, 'A03217C0B001122E');
      expect(a.identity.firmware, 'Main:3.0.40 Drv:5.6.60 BLE:2.0.1');
      final t = a.telemetry;
      expect(t.speedKmh, 20.92);
      expect(t.voltageV, 131.80);
      expect(t.currentA, 0.64);
      expect(t.powerW, 102.0);
      expect(t.batteryPct, 99);
      expect(t.tempC, 29.0);
      expect(t.temp2C, 31.0);
      expect(t.distanceM, 940);
      expect(t.totalDistanceM, 399650);
      expect(a.torqueNm, 1.53);
      expect(a.motorPowerW, 79.0);
      expect(a.pitchDeg, 0.39);
      expect(a.rollDeg, -0.17);
      expect(a.dynamicSpeedLimitKmh, 70.00);
      expect(a.dynamicCurrentLimitA, 80.00);
    });
  });

  group('InMotionAdapter — familia nueva (V11Y, V9, V12S)', () {
    test('secuencia completa real (V11Y)', () {
      final a = InMotionAdapter();
      final results = <bool>[
        a.decode(hex(carTypeV11y)),
        a.decode(
            hex('aaaa1117820241303332313831304430303130303139000000000083')),
        a.decode(hex(
            'aaaa112f8206220800030603000802213400050201000902230300030108000201240d00010101000101250d00010101000101ac')),
        a.decode(hex(
            'aaaa1428a0200410100e401f401f0000006464323232000000005802000a28645a280000144001040100250d92')),
        a.decode(hex(
            'aaaa142b9000011f261f0000004456569ac5024c005400ccc5d0cb030000003e000000000000002000000073000000f5')),
        a.decode(hex(
            'aaaa141991c82e0000266708008d62000091e400005e720300d0cb03009e')),
        a.decode(hex(
            'aaaa145984941e11000000000087000000090104020000000000006502000000000300000000004b20451fe02e0410100e401f401fa816a816c05d00000000ccc5cecdb0cd0000b0c36400000000004900000000000000000000000000fe')),
      ];
      expect(results, [false, false, false, false, false, false, true]);
      expect(a.identity.model, 'Inmotion V11y');
      expect(a.identity.serial, 'A0321810D0010019');
      expect(a.identity.firmware, 'Main:2.5.52 Drv:6.3.8 BLE:1.3.3');
      final t = a.telemetry;
      expect(t.speedKmh, 1.35);
      expect(t.voltageV, 78.28);
      expect(t.currentA, 0.17);
      expect(t.batteryPct, 81);
      expect(t.tempC, 28.0);
      expect(t.temp2C, 21.0);
      expect(t.distanceM, 30);
      expect(t.totalDistanceM, 119760);
      expect(a.torqueNm, 2.65);
      expect(a.pitchDeg, 0.0);
      expect(a.rollDeg, 6.13);
      expect(a.dynamicSpeedLimitKmh, 41.00);
      expect(a.dynamicCurrentLimitA, 58.00);
      expect(a.imuTempC, 29);
    });

    test('secuencia completa real (V9)', () {
      final a = InMotionAdapter();
      final results = <bool>[
        a.decode(hex(carTypeV9)),
        a.decode(
            hex('aaaa11178202413134323139353041303030343635460000000000fd')),
        a.decode(hex(
            'aaaa11388206222800040719000802212600080101000902230a0004010a0002012401000102010001012501000102010001012f0500050101000000b8')),
        a.decode(hex(
            'aaaa142ca0202a000000071900089411a00f9511000058020064641a020a28646428d0071e32010001012501053015009c')),
        a.decode(hex(
            'aaaa142b900001162617000000c59d4980520367003100cdc9c9c9060000005d0000000000000044000000ca010000cf')),
        a.decode(hex(
            'aaaa14199191620000c1a216008bc301006ffe000037890200ffffd5fe55')),
        a.decode(hex(
            'aaaa1457843e1e0c000000000000000000afffc30000000000ffffd7fe000000000600000000009a17191670178510a00f401f401fa00fa00f983a00000000cdc900ceb0cec8ceb03a6400000000004900000000000000000000003f')),
      ];
      expect(results, [false, false, false, false, false, false, true]);
      expect(a.identity.model, 'Inmotion V9');
      expect(a.identity.serial, 'A1421950A000465F');
      expect(a.identity.firmware, 'Main:1.8.38 Drv:7.4.40 BLE:1.4.10');
      final t = a.telemetry;
      expect(t.speedKmh, 0.0);
      expect(t.voltageV, 77.42);
      expect(t.currentA, 0.12);
      expect(t.batteryPct, 58);
      expect(t.tempC, 29.0);
      expect(t.temp2C, 25.0);
      expect(t.distanceM, 60);
      expect(t.totalDistanceM, 252330);
      expect(a.torqueNm, -0.81);
      expect(a.pitchDeg, -0.01);
      expect(a.rollDeg, -2.97);
      expect(a.dynamicSpeedLimitKmh, 42.29);
      expect(a.dynamicCurrentLimitA, 40.00);
    });

    test('secuencia completa real (V12S)', () {
      final a = InMotionAdapter();
      final results = <bool>[
        a.decode(hex(carTypeV12s)),
        a.decode(
            hex('aaaa1117820241313432313934303730303333353943000000000084')),
        a.decode(hex(
            'aaaa11418206220e0011060300080221380008016b000802232a0003010a0002012400000301040000002508000101040000002e18000001000000012f050005010100000087')),
        a.decode(hex(
            'aaaa142ca0200000000006030008581b581bb80b0000580210646415020a28646428d0073232040000002508053014008e')),
        a.decode(hex(
            'aaaa142b900001252626000000050629d50000000000008282828200000000000000000000000000000000090000007d')),
        a.decode(hex(
            'aaaa1419911d81000080711c00bd92020019000100cd2002008282000037')),
        a.decode(hex(
            'aaaa145784b520010000000000000000000000000000000000d7e40000d7e400000000000000002427f026e02e581b581b401f401f581b581b786900000000cdce00ceb0cbccceb0216403000000000000000000000000000000001b')),
      ];
      expect(results, [false, false, false, false, false, false, true]);
      expect(a.identity.model, 'Inmotion V12S');
      expect(a.identity.serial, 'A14219407003359C');
      expect(a.identity.firmware, 'Main:1.8.56 Drv:6.17.14 BLE:1.3.42');
      final t = a.telemetry;
      expect(t.speedKmh, 0.0);
      expect(t.voltageV, 83.73);
      expect(t.currentA, 0.01);
      expect(t.batteryPct, 100);
      expect(t.tempC, 29.0);
      expect(t.temp2C, 30.0);
      expect(t.totalDistanceM, 330530);
      expect(a.torqueNm, 0.0);
      expect(a.pitchDeg, -69.53);
      expect(a.rollDeg, 0.0);
      expect(a.imuTempC, 27);
    });
  });

  group('InMotionAdapter — ajustes y robustez', () {
    test('ajustes no son telemetría; el dato principal sí (V13)', () {
      final a = InMotionAdapter();
      final results = <bool>[
        a.decode(hex(carTypeV13)),
        a.decode(hex(
            'AAAA1428A02028233421401F401F5A00006464302C21000000005802000A28645A2800005500010410000000EB')),
        a.decode(hex(
            'AAAA1459845E2F0F000000F8FF00000000CC11750000000000C900E9FFC8000000000000000000FB20FB1F204E28233421401F401F204E401F709400000000CACCC9CAB0C80000B092000000000000491000000000000000000000000093')),
      ];
      expect(results, [false, false, true]);
    });

    test('ajustes no son telemetría; el dato principal sí (V11)', () {
      final a = InMotionAdapter();
      final results = <bool>[
        a.decode(hex(carTypeV11)),
        a.decode(hex(
            'AAAA141EA02018155000106464130000000040380000006461501500141001000000E9')),
        a.decode(hex(
            'AAAA144584631CF6FF000053004E0000000000000051006AFD4F0000000000000023102F0EFD075214641900000000CEB000CED5D3000028000000000049140000000000000000000027')),
      ];
      expect(results, [false, false, true]);
    });

    test('ajustes no son telemetría; el dato principal sí (V11Y)', () {
      final a = InMotionAdapter();
      final results = <bool>[
        a.decode(hex(carTypeV11y)),
        a.decode(hex(
            'AAAA1428A020FC080807401F401F000000474764321F000000005802000A28645A2800001000040400002D1845')),
        a.decode(hex(
            'AAAA145984671E0D000000000000000000EFFF2B000000000000003704000000000000000000006B192D18E02E9411A00F401F401FA816A816C05D00000000CAC9C7CAB0C90000B070640000000000490012000000000000000000000003')),
      ];
      expect(results, [false, false, true]);
    });

    test('una trama partida en trozos se recompone igual', () {
      const frame =
          'AAAA143184E61EEB0561094A11AE04A004DF01402958CBB000CE004A010000D4FF7C15641900000000492B00000000000000000000C6';
      final whole = InMotionAdapter();
      whole.decode(hex(carTypeV11));
      expect(whole.decode(hex(frame)), isTrue);

      final split = InMotionAdapter();
      split.decode(hex(carTypeV11));
      final bytes = hex(frame);
      var last = true;
      for (var i = 0; i < bytes.length; i += 7) {
        final end = i + 7 > bytes.length ? bytes.length : i + 7;
        last = split.decode(Uint8List.sublistView(bytes, i, end));
        if (end < bytes.length) expect(last, isFalse);
      }
      expect(last, isTrue);
      expect(split.telemetry, whole.telemetry);
    });

    test('suma incorrecta: la trama se descarta sin tocar el snapshot', () {
      final a = InMotionAdapter();
      a.decode(hex(carTypeV11));
      final bad = hex(
          'AAAA143184E61EEB0561094A11AE04A004DF01402958CBB000CE004A010000D4FF7C15641900000000492B00000000000000000000C7');
      expect(a.decode(bad), isFalse);
      expect(a.telemetry.speedKmh, 0);
      // Y la siguiente trama buena sigue entrando.
      final good = hex(
          'AAAA143184E61EEB0561094A11AE04A004DF01402958CBB000CE004A010000D4FF7C15641900000000492B00000000000000000000C6');
      expect(a.decode(good), isTrue);
      expect(a.telemetry.speedKmh, 24.01);
    });

    test('basura antes de la cabecera no impide resincronizar', () {
      final a = InMotionAdapter();
      final junk = Uint8List.fromList([0x01, 0x02, 0xAA, 0x10, 0xFF]);
      expect(a.decode(junk), isFalse);
      a.decode(hex(carTypeV11));
      final ok = a.decode(hex(
          'AAAA143184E61EEB0561094A11AE04A004DF01402958CBB000CE004A010000D4FF7C15641900000000492B00000000000000000000C6'));
      expect(ok, isTrue);
      expect(a.telemetry.voltageV, 79.10);
    });

    test('dos tramas en una sola notificación se procesan ambas', () {
      final a = InMotionAdapter();
      final both = Uint8List.fromList([
        ...hex(carTypeV11),
        ...hex('AAAA141991E86C000066191C002DB2040064E60000974D050000C7DF01A4'),
      ]);
      expect(a.decode(both), isFalse); // ninguna es de tiempo real
      expect(a.identity.model, 'Inmotion V11');
      expect(a.telemetry.totalDistanceM, 278800);
    });

    test('trama de baterías: packs y carga quedan en los getters', () {
      final a = InMotionAdapter();
      // Trama construida con los offsets del protocolo: pack 1
      // 84.00 V / temp 25, pack 2 83.50 V / temp 26, carga
      // 90.00 V / 1.50 A.
      final data = Uint8List(20);
      void w16(int off, int v) {
        data[off] = v & 0xFF;
        data[off + 1] = (v >> 8) & 0xFF;
      }

      w16(0, 8400);
      data[4] = 25;
      w16(8, 8350);
      data[12] = 26;
      w16(16, 9000);
      w16(18, 150);
      final frame =
          InMotionAdapter.buildMessage(flags: 0x14, command: 0x05, data: data);
      expect(a.decode(frame), isFalse); // no es telemetría en vivo
      expect(a.pack1VoltageV, 84.0);
      expect(a.pack1Temp, 25);
      expect(a.pack2VoltageV, 83.5);
      expect(a.pack2Temp, 26);
      expect(a.chargeVoltageV, 90.0);
      expect(a.chargeCurrentA, 1.5);
    });
  });
}
