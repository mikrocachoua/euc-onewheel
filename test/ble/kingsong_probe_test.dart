import 'package:euc_onewheel/models/wheel_identity.dart';
import 'package:euc_onewheel/services/ble/adapters/kingsong_adapter.dart';
import 'package:euc_onewheel/services/ble/wheel_connection_controller.dart';
import 'package:euc_onewheel/services/ble/wheel_detector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('el kick de inicio de stream es la trama documentada de 20 bytes',
      () {
    final kick = KingSongAdapter.buildKickRequest();
    expect(kick.length, 20);
    expect(kick[0], 0xAA);
    expect(kick[1], 0x55);
    expect(kick[16], 0x5E);
    expect(kick[17], 0x14);
    expect(kick[18], 0x5A);
    expect(kick[19], 0x5A);
    expect(kick.sublist(2, 16), everyElement(0));
  });

  bool probe({
    String? transport = GattUuid.transportSharedSerial,
    Set<WheelBrand> candidates = const {WheelBrand.kingsong},
    bool brandSniffed = false,
    bool hasAdapter = false,
    int unrecognizedFrames = 0,
  }) =>
      WheelConnectionController.shouldSendKingsongProbe(
        transport: transport,
        candidates: candidates,
        brandSniffed: brandSniffed,
        hasAdapter: hasAdapter,
        unrecognizedFrames: unrecognizedFrames,
      );

  test('serie compartida + KingSong candidata + silencio total: sondea', () {
    expect(probe(), isTrue);
  });

  test('transporte NUS: no sondea (ese caso lo cubre el sondeo V2)', () {
    expect(probe(transport: GattUuid.transportNus), isFalse);
  });

  test('KingSong fuera de las candidatas: no sondea', () {
    expect(
      probe(candidates: const {WheelBrand.begode, WheelBrand.veteran}),
      isFalse,
    );
  });

  test('marca ya olfateada: no sondea', () {
    expect(probe(brandSniffed: true), isFalse);
  });

  test('adaptador ya adjunto: no sondea', () {
    expect(probe(hasAdapter: true), isFalse);
  });

  test('ya llegaron tramas sin reconocer: no sondea', () {
    expect(probe(unrecognizedFrames: 2), isFalse);
  });
}
