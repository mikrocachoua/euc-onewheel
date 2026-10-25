import 'package:euc_onewheel/models/wheel_identity.dart';
import 'package:euc_onewheel/services/ble/wheel_detector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WheelDetector · huella GATT', () {
    test('transporte compartido ffe0/ffe1 con fff0: familia completa', () {
      final fp = WheelDetector.fromGatt(
        serviceUuids: {GattUuid.serialService, GattUuid.kingsongExtraService},
        characteristicUuids: {GattUuid.serialChar},
      );
      expect(fp.transport, GattUuid.transportSharedSerial);
      expect(fp.candidates, contains(WheelBrand.kingsong));
      expect(fp.candidates, contains(WheelBrand.begode));
      expect(fp.candidates, contains(WheelBrand.veteran));
    });

    test('módulo BLE nuevo de Begode (1d14d6ee) descarta KingSong', () {
      final fp = WheelDetector.fromGatt(
        serviceUuids: {
          GattUuid.serialService,
          GattUuid.gotwayNewModuleService,
        },
        characteristicUuids: {GattUuid.serialChar},
      );
      expect(fp.transport, GattUuid.transportSharedSerial);
      expect(fp.candidates, isNot(contains(WheelBrand.kingsong)));
      expect(fp.candidates, contains(WheelBrand.begode));
    });

    test('InMotion clásico: ffe4 para leer y ffe9 para escribir', () {
      final fp = WheelDetector.fromGatt(
        serviceUuids: {
          GattUuid.serialService,
          GattUuid.inmotionWriteService,
        },
        characteristicUuids: {
          GattUuid.inmotionReadChar,
          GattUuid.inmotionWriteChar,
        },
      );
      expect(fp.transport, GattUuid.transportInmotionClassic);
      expect(fp.candidates, {WheelBrand.inmotion});
    });

    test('NUS: InMotion V2 o Ninebot Z', () {
      final fp = WheelDetector.fromGatt(
        serviceUuids: {GattUuid.nusService},
        characteristicUuids: {GattUuid.nusRxChar, GattUuid.nusTxChar},
      );
      expect(fp.transport, GattUuid.transportNus);
      expect(fp.candidates,
          containsAll([WheelBrand.inmotionV2, WheelBrand.ninebotZ]));
    });

    test('sin transporte conocido no hay candidatos', () {
      final fp = WheelDetector.fromGatt(
        serviceUuids: {'0000180a-0000-1000-8000-00805f9b34fb'},
        characteristicUuids: const {},
      );
      expect(fp.transport, isNull);
      expect(fp.candidates, {WheelBrand.unknown});
    });

    test('los UUID cortos se normalizan a 128 bits', () {
      expect(normalizeUuid('FFE0'), GattUuid.serialService);
      expect(normalizeUuid('ffe1'), GattUuid.serialChar);
      final fp = WheelDetector.fromGatt(
        serviceUuids: {'ffe0', 'fff0'},
        characteristicUuids: {'ffe1'},
      );
      expect(fp.transport, GattUuid.transportSharedSerial);
    });
  });

  group('WheelDetector · olfateo de la primera trama', () {
    const sharedCandidates = {
      WheelBrand.kingsong,
      WheelBrand.begode,
      WheelBrand.veteran,
      WheelBrand.ninebot,
    };

    test('AA 55 → KingSong', () {
      expect(
        WheelDetector.sniffFirstFrame([0xAA, 0x55, 0x69, 0x19],
            candidates: sharedCandidates,
            transport: GattUuid.transportSharedSerial),
        WheelBrand.kingsong,
      );
    });

    test('55 AA → Begode en el transporte compartido', () {
      expect(
        WheelDetector.sniffFirstFrame([0x55, 0xAA, 0x00, 0x00],
            candidates: sharedCandidates,
            transport: GattUuid.transportSharedSerial),
        WheelBrand.begode,
      );
    });

    test('DC 5A 5C → Veteran', () {
      expect(
        WheelDetector.sniffFirstFrame([0xDC, 0x5A, 0x5C, 0x26],
            candidates: sharedCandidates,
            transport: GattUuid.transportSharedSerial),
        WheelBrand.veteran,
      );
    });

    test('5A A5 → Ninebot Z en NUS', () {
      expect(
        WheelDetector.sniffFirstFrame([0x5A, 0xA5, 0x06, 0x3E],
            candidates: const {WheelBrand.inmotionV2, WheelBrand.ninebotZ},
            transport: GattUuid.transportNus),
        WheelBrand.ninebotZ,
      );
    });

    test('AA AA → InMotion V2 en NUS, clásico en su transporte', () {
      expect(
        WheelDetector.sniffFirstFrame([0xAA, 0xAA, 0x14, 0x04],
            candidates: const {WheelBrand.inmotionV2, WheelBrand.ninebotZ},
            transport: GattUuid.transportNus),
        WheelBrand.inmotionV2,
      );
      expect(
        WheelDetector.sniffFirstFrame([0xAA, 0xAA, 0x11, 0x20],
            candidates: const {WheelBrand.inmotion},
            transport: GattUuid.transportInmotionClassic),
        WheelBrand.inmotion,
      );
    });

    test('trama desconocida o demasiado corta no detecta nada', () {
      expect(
        WheelDetector.sniffFirstFrame([0x01, 0x02, 0x03],
            candidates: sharedCandidates,
            transport: GattUuid.transportSharedSerial),
        isNull,
      );
      expect(
        WheelDetector.sniffFirstFrame([0xAA],
            candidates: sharedCandidates,
            transport: GattUuid.transportSharedSerial),
        isNull,
      );
    });
  });

  group('WheelDetector · pre-clasificación InMotion V2', () {
    GattFingerprint nusFingerprint() => WheelDetector.fromGatt(
          serviceUuids: {GattUuid.nusService},
          characteristicUuids: {GattUuid.nusRxChar, GattUuid.nusTxChar},
        );

    test('V9-600214BD real: NUS + nombre V9 → InMotion V2', () {
      expect(
        WheelDetector.preAttachBrand(
          advertisedName: 'V9-600214BD',
          fingerprint: nusFingerprint(),
        ),
        WheelBrand.inmotionV2,
      );
    });

    test('otros modelos V (V11Y, V12, V14) también pre-clasifican', () {
      for (final name in ['V11Y-123456', 'V12-ABCDEF', 'V14-000001']) {
        expect(
          WheelDetector.preAttachBrand(
            advertisedName: name,
            fingerprint: nusFingerprint(),
          ),
          WheelBrand.inmotionV2,
        );
      }
    });

    test('nombre «INMOTION …» pre-clasifica aunque no empiece por V', () {
      expect(
        WheelDetector.preAttachBrand(
          advertisedName: 'INMOTION V13',
          fingerprint: nusFingerprint(),
        ),
        WheelBrand.inmotionV2,
      );
    });

    test('nombre de otra marca, vacío o sin NUS no pre-clasifica', () {
      expect(
        WheelDetector.preAttachBrand(
          advertisedName: 'KS-16X',
          fingerprint: nusFingerprint(),
        ),
        isNull,
      );
      expect(
        WheelDetector.preAttachBrand(
          advertisedName: '',
          fingerprint: nusFingerprint(),
        ),
        isNull,
      );
      final shared = WheelDetector.fromGatt(
        serviceUuids: {GattUuid.serialService},
        characteristicUuids: {GattUuid.serialChar},
      );
      expect(
        WheelDetector.preAttachBrand(
          advertisedName: 'V9-600214BD',
          fingerprint: shared,
        ),
        isNull,
      );
    });
  });
}
