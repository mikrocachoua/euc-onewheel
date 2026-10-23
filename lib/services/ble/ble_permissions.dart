import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

/// Resultado de pedir los permisos de runtime para escanear por BLE.
enum BlePermissionOutcome {
  /// Todo concedido (o no hacía falta pedir nada): se puede escanear.
  granted,

  /// El usuario lo negó, pero se le puede volver a pedir.
  denied,

  /// Denegado de forma permanente (o restringido por el sistema):
  /// el diálogo ya no aparece; solo se arregla en los ajustes.
  permanentlyDenied,
}

/// Permiso de runtime que el escaneo BLE puede necesitar en Android.
enum BleRuntimePermission {
  bluetoothScan,
  bluetoothConnect,
  locationWhenInUse,
}

/// Nivel de API a partir del cual Android usa los permisos nuevos
/// de Bluetooth (Android 12, API 31).
const int _androidBluetoothPermissionsSdk = 31;

/// Decisión pura: qué permisos de runtime hay que pedir para poder
/// escanear por BLE.
///
/// - Fuera de Android no se pide nada: en iOS el permiso de Bluetooth
///   se gestiona solo con el Info.plist.
/// - Android 12+ (API 31): BLUETOOTH_SCAN + BLUETOOTH_CONNECT. La
///   ubicación NO se pide: el manifiesto declara el escaneo con
///   `neverForLocation` (los resultados no se usan para ubicar).
/// - Android 11 o menor: los permisos clásicos de Bluetooth son de
///   instalación, pero el sistema sí exige la ubicación en tiempo de
///   ejecución para entregar resultados de escaneo BLE.
/// - Si la versión no se pudo determinar, se pide todo: es preferible
///   un permiso de más a un escaneo que nunca devuelve resultados.
List<BleRuntimePermission> requiredBlePermissions({
  required bool isAndroid,
  required int? androidSdk,
}) {
  if (!isAndroid) return const [];
  if (androidSdk == null) {
    return const [
      BleRuntimePermission.bluetoothScan,
      BleRuntimePermission.bluetoothConnect,
      BleRuntimePermission.locationWhenInUse,
    ];
  }
  if (androidSdk >= _androidBluetoothPermissionsSdk) {
    return const [
      BleRuntimePermission.bluetoothScan,
      BleRuntimePermission.bluetoothConnect,
    ];
  }
  return const [BleRuntimePermission.locationWhenInUse];
}

/// Extrae el nivel de API de [Platform.operatingSystemVersion], cuyo
/// formato en Android es p. ej. "Android 14 (SDK 34)". Devuelve null
/// si no se reconoce el formato.
int? parseAndroidSdk(String operatingSystemVersion) {
  final match = RegExp(r'\(SDK (\d+)\)').firstMatch(operatingSystemVersion);
  if (match == null) return null;
  return int.tryParse(match.group(1)!);
}

/// Resume una lista de estados de permiso en un solo resultado:
/// basta un bloqueo permanente para que todo quede permanente, y
/// basta una negación simple para que quede denegado.
BlePermissionOutcome outcomeFromStatuses(Iterable<PermissionStatus> statuses) {
  var outcome = BlePermissionOutcome.granted;
  for (final status in statuses) {
    if (status.isGranted || status.isLimited || status.isProvisional) {
      continue;
    }
    if (status.isPermanentlyDenied || status.isRestricted) {
      return BlePermissionOutcome.permanentlyDenied;
    }
    outcome = BlePermissionOutcome.denied;
  }
  return outcome;
}

/// Puerta de permisos de runtime del escaneo BLE.
///
/// Sin estos permisos, en Android 12+ el escaneo arranca pero no
/// devuelve ni un solo resultado (el hueco que cierra esta clase).
/// En iOS no hace nada: ahí el permiso se pide solo vía Info.plist.
class BlePermissionService {
  const BlePermissionService();

  /// Pide los permisos que apliquen según la plataforma y la versión
  /// de Android, mostrando el diálogo del sistema si hace falta.
  Future<BlePermissionOutcome> ensureScanPermissions() async {
    final needed = requiredBlePermissions(
      isAndroid: Platform.isAndroid,
      androidSdk: Platform.isAndroid
          ? parseAndroidSdk(Platform.operatingSystemVersion)
          : null,
    );
    if (needed.isEmpty) return BlePermissionOutcome.granted;
    final statuses = await needed.map(_asPermission).toList().request();
    return outcomeFromStatuses(statuses.values);
  }

  /// Abre los ajustes de la app, para que el usuario active a mano
  /// un permiso bloqueado de forma permanente.
  Future<void> openSettings() => openAppSettings();

  Permission _asPermission(BleRuntimePermission permission) {
    return switch (permission) {
      BleRuntimePermission.bluetoothScan => Permission.bluetoothScan,
      BleRuntimePermission.bluetoothConnect => Permission.bluetoothConnect,
      BleRuntimePermission.locationWhenInUse => Permission.locationWhenInUse,
    };
  }
}
