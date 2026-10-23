import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'wheel_detector.dart';

/// Un dispositivo visto durante el escaneo BLE.
class ScannedWheelDevice {
  const ScannedWheelDevice({
    required this.device,
    required this.deviceId,
    required this.name,
    required this.rssi,
    required this.advertisedServiceUuids,
  });

  /// Dispositivo de flutter_blue_plus (para conectar).
  final BluetoothDevice device;

  /// Id del periférico (dirección MAC en Android, UUID en iOS).
  final String deviceId;

  /// Nombre anunciado; puede venir vacío si la rueda no lo publica.
  final String name;

  /// Potencia de la señal (dBm, negativo; más cerca de 0 = más cerca).
  final int rssi;

  /// Servicios que el dispositivo anuncia en su publicidad BLE.
  final List<String> advertisedServiceUuids;

  /// Nombre para mostrar: el anunciado o un genérico con el id.
  String get displayName => name.isNotEmpty
      ? name
      : 'Dispositivo BLE (${deviceId.substring(0, deviceId.length > 8 ? 8 : deviceId.length)}…)';
}

/// Enlace BLE ya establecido con una rueda: transporte serie listo,
/// notificaciones activas y huella GATT calculada.
class BleLink {
  const BleLink({
    required this.device,
    required this.transport,
    required this.fingerprint,
    required this.frames,
    required this.write,
  });

  final BluetoothDevice device;

  /// Transporte serie elegido (ver [GattUuid.transport*]).
  final String transport;

  /// Huella GATT del dispositivo (marcas candidatas).
  final GattFingerprint fingerprint;

  /// Tramas crudas que llegan por la característica de notificación.
  final Stream<List<int>> frames;

  /// Escritura cruda en la característica de escritura del transporte.
  final Future<void> Function(List<int> data, {bool withoutResponse}) write;
}

/// Error de la capa BLE con mensaje listo para mostrar al usuario.
class BleException implements Exception {
  const BleException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Envoltorio de flutter_blue_plus: escaneo, conexión/desconexión y
/// streams de estado. No conoce protocolos de marca: entrega tramas
/// crudas y acepta escrituras crudas en el transporte serie.
///
/// OJO: este servicio escribe bytes crudos SOLO a petición del
/// controlador (peticiones de solo lectura de los adaptadores) y, en
/// el futuro, de la compuerta de seguridad — ningún comando de
/// control debe escribirse saltándose safety_gate.dart.
class BleService {
  BleService();

  BluetoothDevice? _device;
  StreamSubscription<BluetoothConnectionState>? _connectionSub;
  final StreamController<bool> _connectedController =
      StreamController<bool>.broadcast();
  bool _connected = false;

  /// Estado del adaptador Bluetooth del teléfono (on/off…).
  Stream<BluetoothAdapterState> get adapterState =>
      FlutterBluePlus.adapterState;

  /// Estado actual del adaptador Bluetooth.
  BluetoothAdapterState get adapterStateNow => FlutterBluePlus.adapterStateNow;

  /// ¿Hay escaneo en curso?
  Stream<bool> get isScanning => FlutterBluePlus.isScanning;

  /// ¿Hay una rueda conectada ahora mismo?
  bool get isConnected => _connected && (_device?.isConnected ?? false);

  /// Cambios de conexión del enlace actual.
  Stream<bool> get connectionChanges => _connectedController.stream;

  /// Resultados del escaneo, ya mapeados a [ScannedWheelDevice].
  Stream<List<ScannedWheelDevice>> get scanResults =>
      FlutterBluePlus.scanResults.map(
        (results) => results.map((r) {
          final adv = r.advertisementData;
          return ScannedWheelDevice(
            device: r.device,
            deviceId: r.device.remoteId.str,
            name: adv.advName.isNotEmpty ? adv.advName : r.device.platformName,
            rssi: r.rssi,
            advertisedServiceUuids:
                adv.serviceUuids.map((g) => g.toString()).toList(),
          );
        }).toList(),
      );

  /// Inicia el escaneo de ruedas cercanas.
  Future<void> startScan({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
      throw const BleException(
          'El Bluetooth del teléfono está apagado: actívalo para buscar tu rueda.');
    }
    await FlutterBluePlus.startScan(timeout: timeout);
  }

  /// Detiene el escaneo en curso.
  Future<void> stopScan() => FlutterBluePlus.stopScan();

  /// Conecta con [target], descubre sus servicios, elige el
  /// transporte serie según la huella GATT, pide MTU grande en
  /// Android (las KingSong serie F emiten tramas BMS > 20 bytes) y
  /// activa las notificaciones.
  Future<BleLink> connect(
    ScannedWheelDevice target, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    await stopScan();
    final device = target.device;
    try {
      await device.connect(
        license: License.nonprofit,
        timeout: timeout,
        mtu: 512,
      );
    } catch (e) {
      throw BleException('No se pudo conectar con la rueda: $e');
    }
    _device = device;
    _setConnected(true);
    _connectionSub = device.connectionState.listen((state) {
      _setConnected(state == BluetoothConnectionState.connected);
    });

    final List<BluetoothService> services;
    try {
      services = await device.discoverServices();
    } catch (e) {
      await disconnect();
      throw BleException('No se pudieron leer los servicios BLE: $e');
    }

    final serviceUuids = <String>{};
    final charUuids = <String>{};
    BluetoothCharacteristic? byUuid(String serviceUuid, String charUuid) {
      for (final s in services) {
        if (normalizeUuid(s.uuid.toString()) != serviceUuid) continue;
        for (final c in s.characteristics) {
          if (normalizeUuid(c.uuid.toString()) == charUuid) return c;
        }
      }
      return null;
    }

    for (final s in services) {
      serviceUuids.add(s.uuid.toString());
      for (final c in s.characteristics) {
        charUuids.add(c.uuid.toString());
      }
    }
    final fingerprint = WheelDetector.fromGatt(
      serviceUuids: serviceUuids,
      characteristicUuids: charUuids,
    );

    BluetoothCharacteristic? notifyChar;
    BluetoothCharacteristic? writeChar;
    switch (fingerprint.transport) {
      case GattUuid.transportSharedSerial:
        notifyChar = byUuid(GattUuid.serialService, GattUuid.serialChar);
        writeChar = notifyChar;
      case GattUuid.transportInmotionClassic:
        notifyChar = byUuid(GattUuid.serialService, GattUuid.inmotionReadChar);
        writeChar =
            byUuid(GattUuid.inmotionWriteService, GattUuid.inmotionWriteChar);
      case GattUuid.transportNus:
        notifyChar = byUuid(GattUuid.nusService, GattUuid.nusTxChar);
        writeChar = byUuid(GattUuid.nusService, GattUuid.nusRxChar);
      default:
        notifyChar = null;
        writeChar = null;
    }
    if (notifyChar == null || writeChar == null) {
      await disconnect();
      throw const BleException(
          'Este dispositivo no expone un transporte serie de rueda compatible.');
    }

    try {
      await notifyChar.setNotifyValue(true);
    } catch (e) {
      await disconnect();
      throw BleException('No se pudieron activar las notificaciones: $e');
    }

    final notify = notifyChar;
    final write = writeChar;
    return BleLink(
      device: device,
      transport: fingerprint.transport!,
      fingerprint: fingerprint,
      frames: notify.onValueReceived,
      write: (data, {bool withoutResponse = false}) =>
          write.write(data, withoutResponse: withoutResponse),
    );
  }

  /// Desconecta la rueda actual (sin disparar ninguna acción sobre
  /// ella: perder el enlace nunca envía comandos).
  Future<void> disconnect() async {
    await _connectionSub?.cancel();
    _connectionSub = null;
    final device = _device;
    _device = null;
    _setConnected(false);
    if (device != null && device.isConnected) {
      await device.disconnect();
    }
  }

  void _setConnected(bool value) {
    if (_connected == value) return;
    _connected = value;
    if (!_connectedController.isClosed) _connectedController.add(value);
  }

  /// Libera recursos del servicio.
  Future<void> dispose() async {
    await disconnect();
    await _connectedController.close();
  }
}
