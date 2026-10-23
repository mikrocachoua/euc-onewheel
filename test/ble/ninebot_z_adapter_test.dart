import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';


import 'package:euc_onewheel/models/wheel_identity.dart';
import 'package:euc_onewheel/services/ble/adapters/ninebot_z_adapter.dart';

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

// Vectores reales de una Ninebot Z10 (tal como llegan por BLE,
// en trozos de notificación), con la clave aún sin negociar
// (gamma en ceros: el cifrado es la identidad).
const snChunks = <String>[
  '5AA50E143E04104E334F54433230323054303030',
  '314BFC',
];
const versionChunk = '5AA506143E041A771019180000D1FE';
const keyChunks = <String>[
  '5aa510163e5b010000000000003cc76a7b1c7d91',
  '23de0527fb',
];
const lifeChunks = <String>[
  '5aa520143e04b000000000489800004e009c0a7a',
  '059b97280023016d0472011a1892119c0a7a052a',
  'f8',
];
const bms1SnChunks = <String>[
  '5AA522113E041034395945513138483151303432',
  '33160180258025EC13AF00810100000000000001',
  '256BF8',
];
const bms1LifeChunks = <String>[
  '5AA518113E04300102BF25640011009A162F2E00',
  '2000000000C025BD256200B2FA',
];
const bms1CellsChunks = <String>[
  '5AA520113E0440341006103110381005103010FA',
  '0F06103D104010011034103D1051100000000055',
  'FB',
];
const bms2SnChunks = <String>[
  '5AA522123E041034395945513138483151303432',
  '33160180258025EC13B000810100000000000001',
  '2569F8',
];
const bms2LifeChunks = <String>[
  '5AA518123E043001029C2564000000A0162F2E00',
  '00000000009C259C25620044FB',
];
const bms2CellsChunks = <String>[
  '5AA520123E04401B102C10221024102310211031',
  '1030102F10271026103510321035100000000021',
  'FC',
];

List<bool> feedAll(NinebotZAdapter a, List<String> chunks) =>
    <bool>[for (final c in chunks) a.decode(hex(c))];

/// Cifra una trama en claro con la clave que entrega el vector
/// de clave (gamma 0000000000003cc76a7b1c7d9123de05), como haría
/// la rueda tras negociar: el byte 0 del cuerpo va en claro y
/// cada byte `j ≥ 1` se combina con `gamma[(j − 1) % 16]`.
Uint8List encryptWithKey(String plainWire) {
  const gamma = <int>[
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x3C,
    0xC7,
    0x6A,
    0x7B,
    0x1C,
    0x7D,
    0x91,
    0x23,
    0xDE,
    0x05,
  ];
  final wire = hex(plainWire);
  final out = Uint8List.fromList(wire);
  for (var j = 1; j < out.length - 2; j++) {
    out[j + 2] = (out[j + 2] ^ gamma[(j - 1) % 16]) & 0xFF;
  }
  return out;
}

void main() {
  group('NinebotZAdapter — contrato', () {
    test('marca Ninebot Z y solo telemetría', () {
      final a = NinebotZAdapter();
      expect(a.brand, WheelBrand.ninebotZ);
      expect(a.capabilities.telemetry, isTrue);
      expect(a.capabilities.motorLock, isTrue);
      expect(a.capabilities.calibration, isTrue);
      expect(a.capabilities.tiltBack, isTrue);
      // La luz vía DriveFlags no está verificada y no hay apagado
      // remoto en la referencia: fuera, a propósito.
      expect(a.capabilities.lights, isFalse);
      expect(a.capabilities.powerOff, isFalse);
    });

    test('peticiones iniciales exactas con la gamma en ceros', () {
      final a = NinebotZAdapter();
      final initial = a.initialRequests();
      expect(initial, hasLength(2));
      // Versión BLE: 5A A5 | 01 3E 14 01 68 02 | suma 41 FF.
      expect(hexStr(initial[0]), '5aa5013e1401680241ff');
      // Clave: 5A A5 | 00 3E 16 5B 00 | suma 50 FF.
      expect(hexStr(initial[1]), '5aa5003e165b0050ff');
      expect(a.pollInterval, const Duration(milliseconds: 150));
    });

    test('sin tramas, la telemetría nace neutra y sin BMS', () {
      final a = NinebotZAdapter();
      expect(a.telemetry.speedKmh, 0);
      expect(a.telemetry.batteryPct, isNull);
      expect(a.keyNegotiated, isFalse);
      expect(a.bms1, isNull);
      expect(a.bms2, isNull);
    });
  });

  group('NinebotZAdapter — vectores reales Z10', () {
    test('número de serie: dos trozos, identidad completa', () {
      final a = NinebotZAdapter();
      expect(feedAll(a, snChunks), <bool>[false, false]);
      expect(a.identity.brand, WheelBrand.ninebotZ);
      expect(a.identity.model, 'Ninebot Z');
      expect(a.identity.serial, 'N3OTC2020T0001');
    });

    test('versión de firmware con sus códigos de error', () {
      final a = NinebotZAdapter();
      expect(a.decode(hex(versionChunk)), isFalse);
      expect(a.identity.firmware, '0.7.7');
      expect(a.firmwareErrorCode, 25);
      expect(a.firmwareError2Code, 24);
      expect(a.firmwareErrorText,
          'VGM - Voltaje < 10 V\nVoltaje general > 65 V o < 40 V');
      expect(NinebotZAdapter.errorTextFor(0), 'Sin error');
      expect(NinebotZAdapter.errorTextFor(99), 'Error desconocido');
    });

    test('clave: se instala por origen y comando (parámetro 0x01)', () {
      final a = NinebotZAdapter();
      expect(feedAll(a, keyChunks), <bool>[false, false]);
      expect(a.keyNegotiated, isTrue);
      // Con la clave instalada, las peticiones salen cifradas:
      // solo cambian los bytes que la gamma toca (aquí, el
      // segundo byte de la suma: FF ^ 3C = C3).
      final initial = a.initialRequests();
      expect(hexStr(initial[0]), '5aa5013e1401680241c3');
      expect(hexStr(a.liveDataRequest()), '5aa5013e1401b020dbc2');
    });

    test('tras la clave, el tráfico cifrado se descifra y verifica', () {
      final a = NinebotZAdapter();
      feedAll(a, keyChunks);
      // La trama de datos en vivo, cifrada con la clave
      // negociada (gamma 0000000000003cc76a7b1c7d9123de05).
      const encryptedLife =
          '5aa520143e04b000003cc722e31c7ddf23420f7a059b9728001fc6077f'
          '6e7c8b3b4c149c0a7a052af8';
      expect(a.decode(hex(encryptedLife)), isTrue);
      expect(a.telemetry.speedKmh, 27.16);
      expect(a.telemetry.voltageV, 61.7);
      expect(a.telemetry.batteryPct, 78);
    });

    test('datos en vivo: telemetría completa', () {
      final a = NinebotZAdapter();
      expect(feedAll(a, lifeChunks), <bool>[false, false, true]);
      final t = a.telemetry;
      expect(t.speedKmh, 27.16);
      expect(t.voltageV, 61.7);
      expect(t.currentA, 44.98);
      expect(t.powerW, closeTo(2775.27, 0.01));
      expect(t.tempC, 37.0);
      expect(t.batteryPct, 78);
      expect(t.totalDistanceM, 2660251);
      expect(t.distanceM, 2910);
      expect(t.model, 'Ninebot Z');
      expect(t.pwmPct, isNull); // no viaja en la trama: no se inventa
      expect(a.avgSpeedKmh, 14.02);
      expect(a.operatingTimeSec, 1133);
      expect(a.errorCode, 0);
      expect(a.alarmCode, 0);
    });

    test('una suma corrupta invalida la trama sin tocar el estado', () {
      final a = NinebotZAdapter();
      final corrupted = hex(lifeChunks.join());
      corrupted[corrupted.length - 1] ^= 0xFF;
      expect(a.decode(corrupted), isFalse);
      expect(a.telemetry.speedKmh, 0);
      expect(a.telemetry.batteryPct, isNull);
    });

    test('BMS 1: serie y fabricación', () {
      final a = NinebotZAdapter();
      expect(feedAll(a, bms1SnChunks), <bool>[false, false, false]);
      final bms = a.bms1!;
      expect(bms.serial, '49YEQ18H1Q0423');
      expect(bms.version, '1.1.6');
      expect(bms.factoryCapMah, 9600);
      expect(bms.actualCapMah, 9600);
      expect(bms.fullCycles, 175);
      expect(bms.chargeCount, 385);
      expect(bms.mfgDate, '01.08.2018');
      expect(a.bms2, isNull);
    });

    test('BMS 1: estado', () {
      final a = NinebotZAdapter();
      expect(feedAll(a, bms1LifeChunks), <bool>[false, false]);
      final bms = a.bms1!;
      expect(bms.status, 513);
      expect(bms.remainingCapMah, 9663);
      expect(bms.remainingPct, 100);
      expect(bms.currentA, 0.17);
      expect(bms.voltageV, 57.86);
      expect(bms.temp1C, 27);
      expect(bms.temp2C, 26);
      expect(bms.balanceMap, 8192);
      expect(bms.healthPct, 98);
    });

    test('BMS 1: voltajes de celda', () {
      final a = NinebotZAdapter();
      expect(feedAll(a, bms1CellsChunks), <bool>[false, false, false]);
      expect(a.bms1!.cellsV, <double>[
        4.148,
        4.102,
        4.145,
        4.152,
        4.101,
        4.144,
        4.090,
        4.102,
        4.157,
        4.160,
        4.097,
        4.148,
        4.157,
        4.177,
        0.0,
        0.0,
      ]);
      expect(a.bms1!.cellCount, 14);
    });

    test('BMS 2: serie, estado y celdas', () {
      final a = NinebotZAdapter();
      expect(feedAll(a, bms2SnChunks), <bool>[false, false, false]);
      expect(feedAll(a, bms2LifeChunks), <bool>[false, false]);
      expect(feedAll(a, bms2CellsChunks), <bool>[false, false, false]);
      final bms = a.bms2!;
      expect(bms.serial, '49YEQ18H1Q0423');
      expect(bms.version, '1.1.6');
      expect(bms.fullCycles, 176); // difiere del BMS 1: 175
      expect(bms.remainingCapMah, 9628);
      expect(bms.currentA, 0.0);
      expect(bms.voltageV, 57.92);
      expect(bms.balanceMap, 0);
      expect(bms.healthPct, 98);
      expect(bms.cellsV, <double>[
        4.123,
        4.140,
        4.130,
        4.132,
        4.131,
        4.129,
        4.145,
        4.144,
        4.143,
        4.135,
        4.134,
        4.149,
        4.146,
        4.149,
        0.0,
        0.0,
      ]);
      expect(a.bms1, isNull);
    });
  });

  group('NinebotZAdapter — secuencia de sondeo', () {
    test('pide la clave hasta negociarla y luego avanza por pasos', () {
      final a = NinebotZAdapter();
      // Sin clave: el sondeo insiste en pedirla.
      expect(hexStr(a.pollRequests().single), '5aa5003e165b0050ff');
      feedAll(a, keyChunks);
      // Con clave: serie (cifrada con la gamma: la suma cambia).
      expect(hexStr(a.pollRequests().single), '5aa5013e1401100e8dc3');
      // La respuesta de serie (ya cifrada, como la enviaría la
      // rueda tras negociar) avanza al paso de firmware.
      expect(a.decode(encryptWithKey(snChunks.join())), isFalse);
      expect(a.identity.serial, 'N3OTC2020T0001');
      expect(hexStr(a.pollRequests().single), '5aa5013e14011a068bc3');
    });

    test('sin respuestas, el sondeo no se atasca: avanza solo', () {
      final a = NinebotZAdapter();
      // 11 rondas por paso × 12 pasos bastan para llegar a vivo.
      var last = '';
      for (var i = 0; i < 200; i++) {
        last = hexStr(a.pollRequests().single);
      }
      expect(last, '5aa5013e1401b020dbfe'); // datos en vivo, gamma 0
    });
  });
}
