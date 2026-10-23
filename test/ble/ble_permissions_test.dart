import 'package:euc_onewheel/services/ble/ble_permissions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  group('Permisos BLE · decisión según plataforma y versión', () {
    test('Android 12+ (API 31): scan y connect, SIN ubicación', () {
      final needed = requiredBlePermissions(isAndroid: true, androidSdk: 31);
      expect(
        needed,
        containsAll([
          BleRuntimePermission.bluetoothScan,
          BleRuntimePermission.bluetoothConnect,
        ]),
      );
      expect(needed, isNot(contains(BleRuntimePermission.locationWhenInUse)));
    });

    test('Android actual (API 34/35): tampoco pide ubicación', () {
      for (final sdk in [34, 35]) {
        final needed = requiredBlePermissions(isAndroid: true, androidSdk: sdk);
        expect(needed, isNot(contains(BleRuntimePermission.locationWhenInUse)));
        expect(needed.length, 2);
      }
    });

    test('Android 11 o menor (API 30-): solo ubicación legada', () {
      for (final sdk in [29, 30]) {
        expect(
          requiredBlePermissions(isAndroid: true, androidSdk: sdk),
          [BleRuntimePermission.locationWhenInUse],
        );
      }
    });

    test('fuera de Android no se pide ningún permiso de runtime', () {
      expect(
          requiredBlePermissions(isAndroid: false, androidSdk: null), isEmpty);
      expect(requiredBlePermissions(isAndroid: false, androidSdk: 34), isEmpty);
    });

    test('versión de Android desconocida: se pide todo por seguridad', () {
      final needed = requiredBlePermissions(isAndroid: true, androidSdk: null);
      expect(needed, containsAll(BleRuntimePermission.values));
    });
  });

  group('Permisos BLE · lectura de la versión de Android', () {
    test('extrae el nivel de API del formato del sistema', () {
      expect(parseAndroidSdk('Android 14 (SDK 34)'), 34);
      expect(parseAndroidSdk('Android 12 (SDK 31)'), 31);
      expect(parseAndroidSdk('Android 11 (SDK 30)'), 30);
    });

    test('formato irreconocible devuelve null', () {
      expect(parseAndroidSdk('Android 14'), isNull);
      expect(parseAndroidSdk(''), isNull);
    });
  });

  group('Permisos BLE · resumen de estados', () {
    test('todo concedido (o limitado/provisional) es granted', () {
      expect(
        outcomeFromStatuses(const [
          PermissionStatus.granted,
          PermissionStatus.granted,
        ]),
        BlePermissionOutcome.granted,
      );
      expect(
        outcomeFromStatuses(const [PermissionStatus.limited]),
        BlePermissionOutcome.granted,
      );
      expect(outcomeFromStatuses(const []), BlePermissionOutcome.granted);
    });

    test('una negación simple da denied', () {
      expect(
        outcomeFromStatuses(const [
          PermissionStatus.granted,
          PermissionStatus.denied,
        ]),
        BlePermissionOutcome.denied,
      );
    });

    test('un bloqueo permanente manda sobre las negaciones simples', () {
      expect(
        outcomeFromStatuses(const [
          PermissionStatus.denied,
          PermissionStatus.permanentlyDenied,
        ]),
        BlePermissionOutcome.permanentlyDenied,
      );
      expect(
        outcomeFromStatuses(const [PermissionStatus.restricted]),
        BlePermissionOutcome.permanentlyDenied,
      );
    });
  });
}
