import 'package:euc_onewheel/models/wheel_identity.dart';
import 'package:euc_onewheel/services/ble/ble_service.dart';
import 'package:euc_onewheel/services/ble/wheel_detector.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  BleLink linkWithUuids({
    Set<String> services = const {},
    Set<String> chars = const {},
  }) {
    return BleLink(
      device: BluetoothDevice.fromId('diag-test'),
      transport: GattUuid.transportSharedSerial,
      fingerprint: const GattFingerprint(
        candidates: {WheelBrand.kingsong},
        transport: GattUuid.transportSharedSerial,
      ),
      frames: const Stream<List<int>>.empty(),
      write: (_, {bool withoutResponse = false}) async {},
      serviceUuids: services,
      characteristicUuids: chars,
    );
  }

  test('BleLink conserva los UUID GATT crudos para el diagnóstico', () {
    final link = linkWithUuids(
      services: {
        '0000ffe0-0000-1000-8000-00805f9b34fb',
        '0000fff0-0000-1000-8000-00805f9b34fb',
      },
      chars: {'0000ffe1-0000-1000-8000-00805f9b34fb'},
    );
    expect(link.serviceUuids.length, 2);
    expect(
      link.serviceUuids,
      contains('0000fff0-0000-1000-8000-00805f9b34fb'),
    );
    expect(
      link.characteristicUuids,
      contains('0000ffe1-0000-1000-8000-00805f9b34fb'),
    );
  });

  test('BleLink sin UUID arranca con conjuntos vacíos', () {
    final link = linkWithUuids();
    expect(link.serviceUuids, isEmpty);
    expect(link.characteristicUuids, isEmpty);
  });

  test('Huella tipo S22 (ffe0/ffe1 + fff0) deja a KingSong candidata', () {
    final fingerprint = WheelDetector.fromGatt(
      serviceUuids: {
        '0000ffe0-0000-1000-8000-00805f9b34fb',
        '0000fff0-0000-1000-8000-00805f9b34fb',
      },
      characteristicUuids: {
        '0000ffe1-0000-1000-8000-00805f9b34fb',
      },
    );
    expect(fingerprint.transport, GattUuid.transportSharedSerial);
    expect(fingerprint.candidates, contains(WheelBrand.kingsong));
  });

  test('Huella NUS con serial heredado (tipo V11Y) sigue siendo V2', () {
    final fingerprint = WheelDetector.fromGatt(
      serviceUuids: {
        '6e400001-b5a3-f393-e0a9-e50e24dcca9e',
        '0000ffe0-0000-1000-8000-00805f9b34fb',
      },
      characteristicUuids: {
        '6e400002-b5a3-f393-e0a9-e50e24dcca9e',
        '6e400003-b5a3-f393-e0a9-e50e24dcca9e',
        '0000ffe1-0000-1000-8000-00805f9b34fb',
      },
    );
    expect(fingerprint.transport, GattUuid.transportNus);
    expect(fingerprint.candidates, contains(WheelBrand.inmotionV2));
  });
}
