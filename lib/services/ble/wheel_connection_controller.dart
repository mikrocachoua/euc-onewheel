import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/wheel_identity.dart';
import '../../models/wheel_telemetry.dart';
import '../app_log.dart';
import 'adapters/begode_adapter.dart';
import 'adapters/inmotion_adapter.dart';
import 'adapters/kingsong_adapter.dart';
import 'adapters/ninebot_z_adapter.dart';
import 'adapters/veteran_adapter.dart';
import 'adapters/wheel_adapter.dart';
import 'ble_permissions.dart';
import 'ble_service.dart';
import 'safety_gate.dart';
import 'wheel_command.dart';
import 'wheel_detector.dart';

/// Estado del enlace con la rueda, para la UI.
enum WheelLinkState {
  idle,
  scanning,
  connecting,
  connected,
  error,
}

/// Controlador de la conexión con la rueda: orquesta el escaneo, la
/// conexión, la detección de marca (huella GATT + olfateo de la
/// primera trama), la creación del adaptador de la marca y el flujo
/// de telemetría hacia las pantallas.
///
/// También es el dueño de la [SafetyGate]: TODOS los comandos de
/// control salen por [sendCommand], que construye las tramas con el
/// adaptador de la marca y las pasa, una a una y en orden, por la
/// compuerta antes de escribirlas en el enlace.
class WheelConnectionController extends ChangeNotifier {
  WheelConnectionController({
    BleService? bleService,
    BlePermissionService? permissionService,
  })  : ble = bleService ?? BleService(),
        _permissions = permissionService ?? const BlePermissionService() {
    safetyGate = SafetyGate(
      isConnected: () => state == WheelLinkState.connected && ble.isConnected,
      send: (frame) async {
        final link = _link;
        if (link == null) {
          throw const BleException('Sin enlace con la rueda.');
        }
        await link.write(frame);
      },
    );
  }

  /// Servicio BLE subyacente (escaneo/conexión/streams crudos).
  final BleService ble;

  /// Permisos de runtime del escaneo (solo aplican en Android).
  final BlePermissionService _permissions;

  /// Compuerta de seguridad: único punto de salida de comandos.
  late final SafetyGate safetyGate;

  WheelLinkState _state = WheelLinkState.idle;
  String? _errorMessage;
  BlePermissionOutcome? _permissionOutcome;
  List<ScannedWheelDevice> _foundDevices = const [];
  WheelIdentity _identity = const WheelIdentity();
  WheelTelemetry _telemetry = WheelTelemetry.neutral;
  DateTime? _lastLiveAt;
  bool _brandSniffed = false;

  BleLink? _link;
  WheelAdapter? _adapter;
  StreamSubscription<List<ScannedWheelDevice>>? _scanSub;
  StreamSubscription<List<int>>? _frameSub;
  StreamSubscription<WheelTelemetry>? _telemetrySub;
  StreamSubscription<WheelIdentity>? _identitySub;
  StreamSubscription<bool>? _connectionSub;
  Timer? _pollTimer;

  /// Diagnóstico de conexión (build 14): cuántas tramas sin
  /// reconocer se han registrado en esta conexión (tope para no
  /// inundar el registro) y si ya llegó la primera telemetría.
  int _diagUnrecognizedFrames = 0;
  bool _diagFirstLiveLogged = false;

  /// Registra un paso del diagnóstico de conexión en el AppLog
  /// (visible en Soporte → Compartir registros).
  void _diag(String message) => AppLog.instance.add('Diagnóstico: $message');

  /// Primeros bytes de una trama en hexadecimal, para el registro.
  String _hexHead(List<int> frame, [int maxBytes = 16]) {
    final shown = frame.take(maxBytes).map(
        (b) => (b & 0xFF).toRadixString(16).padLeft(2, '0').toUpperCase());
    final suffix = frame.length > maxBytes ? '…' : '';
    return '${shown.join(' ')}$suffix';
  }

  WheelLinkState get state => _state;
  String? get errorMessage => _errorMessage;

  /// Resultado de la última petición de permisos de escaneo: si no
  /// es null ni concedido, la UI ofrece reintentar o abrir ajustes.
  BlePermissionOutcome? get permissionOutcome => _permissionOutcome;

  /// ¿El escaneo quedó bloqueado por un permiso denegado?
  bool get permissionBlocked =>
      _permissionOutcome == BlePermissionOutcome.denied ||
      _permissionOutcome == BlePermissionOutcome.permanentlyDenied;
  List<ScannedWheelDevice> get foundDevices => _foundDevices;
  WheelIdentity get identity => _identity;
  WheelTelemetry get telemetry => _telemetry;

  /// Cuándo llegó la última trama de telemetría en vivo (la
  /// compuerta de seguridad lo exige fresco para comandos críticos).
  DateTime? get lastLiveAt => _lastLiveAt;

  /// ¿Hay una rueda conectada y con adaptador de telemetría activo?
  bool get hasLiveTelemetry => _adapter != null && _lastLiveAt != null;

  /// Adaptador activo de la marca detectada (null si aún no se
  /// detecta o si la marca todavía no tiene adaptador).
  WheelAdapter? get adapter => _adapter;

  /// Envía un comando de control a la rueda conectada.
  ///
  /// El adaptador de la marca construye los pasos (tramas + esperas)
  /// de [request]; cada trama pasa por la compuerta de seguridad con
  /// la telemetría más reciente antes de escribirse. Si la marca no
  /// soporta el comando, o la compuerta bloquea cualquier paso, se
  /// devuelve el veredicto con el motivo y no se envía nada más.
  Future<GateVerdict> sendCommand(
    WheelCommandRequest request, {
    required bool userConfirmed,
  }) async {
    final adapter = _adapter;
    if (adapter == null) {
      return const GateVerdict.block('No hay ninguna rueda conectada.');
    }
    final steps = adapter.buildCommand(request);
    if (steps == null) {
      return const GateVerdict.block(
          'Este control aún no está disponible para esta marca o modelo.');
    }
    for (final step in steps) {
      if (step.delayBefore > Duration.zero) {
        await Future<void>.delayed(step.delayBefore);
      }
      final verdict = await safetyGate.execute(
        command: request.command,
        frame: Uint8List.fromList(step.frame),
        telemetry: adapter.telemetry,
        telemetryAt: _lastLiveAt,
        userConfirmed: userConfirmed,
      );
      if (!verdict.allowed) return verdict;
    }
    // Tras cambiar la máxima o las alarmas, re-leer los ajustes
    // que la rueda tiene guardados: así la tarjeta muestra lo
    // que la rueda realmente aplicó, no solo lo que se envió.
    if (request is TiltBackRequest || request is SpeedAlarmsRequest) {
      final settingsRequest = adapter.settingsRequest;
      final link = _link;
      if (settingsRequest != null && link != null) {
        unawaited(
            Future<void>.delayed(const Duration(milliseconds: 600)).then((_) {
          if (_link != link || _adapter != adapter) return;
          unawaited(link.write(settingsRequest).catchError((_) {}));
        }));
      }
    }
    return const GateVerdict.allow();
  }

  /// Inicia el escaneo de ruedas cercanas.
  ///
  /// Antes de escanear pide los permisos de runtime (en Android 12+,
  /// sin ellos el escaneo no devuelve resultados): si el usuario los
  /// niega, el estado queda en error con el mensaje y el resultado
  /// del permiso, para que la UI ofrezca reintentar o abrir ajustes.
  Future<void> startScan() async {
    if (_state == WheelLinkState.scanning ||
        _state == WheelLinkState.connecting ||
        _state == WheelLinkState.connected) {
      return;
    }
    _errorMessage = null;
    _permissionOutcome = null;
    final outcome = await _permissions.ensureScanPermissions();
    if (outcome != BlePermissionOutcome.granted) {
      _permissionOutcome = outcome;
      _fail(switch (outcome) {
        BlePermissionOutcome.permanentlyDenied =>
          'El permiso de Bluetooth está bloqueado. Actívalo para EUC '
              'OneWheel en los ajustes de la app: Permisos → '
              'Dispositivos cercanos.',
        _ => 'Sin tu permiso de Bluetooth no se puede buscar la rueda. '
            'Toca «Reintentar» y acepta el permiso.',
      });
      return;
    }
    _foundDevices = const [];
    _setState(WheelLinkState.scanning);
    try {
      await _scanSub?.cancel();
      _scanSub = ble.scanResults.listen((devices) {
        _foundDevices = devices;
        notifyListeners();
      });
      await ble.startScan();
    } on BleException catch (e) {
      _fail(e.message);
    } catch (e) {
      _fail('No se pudo iniciar el escaneo: $e');
    }
  }

  /// Detiene el escaneo en curso.
  Future<void> stopScan() async {
    await ble.stopScan();
    await _scanSub?.cancel();
    _scanSub = null;
    if (_state == WheelLinkState.scanning) {
      _setState(WheelLinkState.idle);
    }
  }

  /// Conecta con un dispositivo encontrado y arranca la detección.
  Future<void> connect(ScannedWheelDevice target) async {
    if (_state == WheelLinkState.connecting ||
        _state == WheelLinkState.connected) {
      return;
    }
    _errorMessage = null;
    _setState(WheelLinkState.connecting);
    await _scanSub?.cancel();
    _scanSub = null;
    try {
      final link = await ble.connect(target);
      _link = link;
      _identity = WheelIdentity(
        deviceId: target.deviceId,
        advertisedName: target.name.isNotEmpty ? target.name : null,
      );
      _telemetry = WheelTelemetry.neutral;
      _lastLiveAt = null;
      _brandSniffed = false;
      _diagUnrecognizedFrames = 0;
      _diagFirstLiveLogged = false;
      _connectionSub = ble.connectionChanges.listen((connected) {
        if (!connected) _onLinkLost();
      });
      _frameSub = link.frames.listen(_onFrame, onError: (_) {});
      _diag('Conectando con ${target.name}');
      _diag('Servicios GATT: ${link.serviceUuids.join(', ')}');
      _diag('Características GATT: ${link.characteristicUuids.join(', ')}');
      _diag('Huella: transporte=${link.transport}, '
          'confianza=${link.fingerprint.transportConfidence}, '
          'candidatas=${link.fingerprint.candidates.map((c) => c.name).join(', ')}');
      // InMotion V2 no emite sin que se le pregunte: con huella NUS
      // y nombre de InMotion, el adaptador se adjunta ya para que
      // sus peticiones iniciales provoquen la respuesta de la rueda.
      // Sin esto, la app esperaba una primera trama que nunca llega
      // y la marca quedaba en «Desconocida» (V9-600214BD, build #8).
      final preBrand = WheelDetector.preAttachBrand(
        advertisedName: target.name,
        fingerprint: link.fingerprint,
      );
      if (preBrand != null) {
        _brandSniffed = true;
        _identity = _identity.copyWith(brand: preBrand);
        _diag('Pre-attach: ${preBrand.name}');
        _attachAdapter(preBrand);
      } else {
        _diag('Pre-attach: ninguno');
      }
      if (preBrand == null && link.transport == GattUuid.transportNus) {
        // Sondeo: una InMotion V2 no emite si no se le pregunta,
        // así que sin adaptador nunca llega la primera trama y el
        // olfateo nunca se dispara. La petición de tipo de
        // vehículo provoca la respuesta AA AA que el olfateo ya
        // reconoce y adjunta el adaptador; una Ninebot Z no
        // contesta con esa trama, así que no hay riesgo de
        // adjuntar mal. Red de seguridad para ruedas cuyo nombre
        // o huella no pasaron el pre-attach.
        _diag('Sondeo V2 enviado (NUS sin pre-attach)');
        unawaited(link
            .write(InMotionAdapter.getCarTypeRequest())
            .catchError((_) {}));
      }
      _setState(WheelLinkState.connected);
    } on BleException catch (e) {
      _link = null;
      _fail(e.message);
    } catch (e) {
      _link = null;
      _fail('No se pudo conectar con la rueda: $e');
    }
  }

  /// Abre los ajustes de la app, para activar a mano un permiso de
  /// Bluetooth bloqueado de forma permanente.
  Future<void> openPermissionSettings() => _permissions.openSettings();

  /// Desconecta la rueda actual y limpia el estado.
  Future<void> disconnect() async {
    await _teardownLink();
    await ble.disconnect();
    _identity = const WheelIdentity();
    _telemetry = WheelTelemetry.neutral;
    _lastLiveAt = null;
    _errorMessage = null;
    _permissionOutcome = null;
    _setState(WheelLinkState.idle);
  }

  /// Procesa cada trama cruda: primero huele la marca si aún no se
  /// conoce; después la pasa al adaptador activo.
  void _onFrame(List<int> raw) {
    if (raw.isEmpty) return;
    final frame = raw is Uint8List ? raw : Uint8List.fromList(raw);

    if (!_brandSniffed) {
      final link = _link;
      if (link == null) return;
      final brand = WheelDetector.sniffFirstFrame(
        frame,
        candidates: link.fingerprint.candidates,
        transport: link.transport,
      );
      if (brand == null) {
        if (_diagUnrecognizedFrames < 5) {
          _diag('Trama sin reconocer '
              '(${frame.length} bytes): ${_hexHead(frame)}');
        } else if (_diagUnrecognizedFrames == 5) {
          _diag('Más tramas sin reconocer (se dejan de registrar)');
        }
        _diagUnrecognizedFrames++;
        return;
      }
      _brandSniffed = true;
      _diag('Olfateo: ${brand.name} '
          '(${frame.length} bytes): ${_hexHead(frame)}');
      _identity = _identity.copyWith(brand: brand);
      notifyListeners();
      _attachAdapter(brand);
    }

    final adapter = _adapter;
    if (adapter != null) {
      final isLive = adapter.decode(frame);
      if (isLive) {
        _lastLiveAt = DateTime.now();
        if (!_diagFirstLiveLogged) {
          _diagFirstLiveLogged = true;
          _diag('Primera telemetría en vivo recibida');
        }
      }
    }
  }

  /// Crea el adaptador de la marca detectada (si ya existe), lo
  /// suscribe y le pide sus datos de solo lectura (nombre, serie…).
  void _attachAdapter(WheelBrand brand) {
    final WheelAdapter? adapter = switch (brand) {
      WheelBrand.kingsong => KingSongAdapter(),
      WheelBrand.begode => BegodeAdapter(),
      WheelBrand.veteran => VeteranAdapter(),
      WheelBrand.inmotionV2 => InMotionAdapter(),
      WheelBrand.ninebotZ => NinebotZAdapter(),
      // Ninebot clásico sigue solo detectado: sin vectores de
      // tramas reales con los que verificar su parseo.
      _ => null, // Las demás marcas llegan en sus propias fases.
    };
    if (adapter == null) {
      _diag('Marca ${brand.name} sin adaptador (solo detectada)');
      return;
    }
    _adapter = adapter;
    _telemetrySub = adapter.telemetryStream.listen((t) {
      _telemetry = t;
      notifyListeners();
    });
    _identitySub = adapter.identityStream.listen((id) {
      _identity = _identity.copyWith(
        brand: id.brand,
        model: id.model,
        serial: id.serial,
        firmware: id.firmware,
      );
      notifyListeners();
    });
    final link = _link;
    if (link != null) {
      final initial = adapter.initialRequests();
      _diag('Adaptador ${brand.name} adjuntado; '
          'peticiones iniciales: ${initial.length}');
      for (final request in initial) {
        unawaited(link.write(request).catchError((_) {}));
      }
    }
    // Protocolos que no emiten en continuo (InMotion V2): se
    // repiten sus peticiones de solo lectura mientras dure la
    // conexión, para que la telemetría se mantenga en vivo.
    final interval = adapter.pollInterval;
    if (interval != null) {
      _pollTimer = Timer.periodic(interval, (_) {
        final currentLink = _link;
        if (currentLink == null || _adapter != adapter) return;
        for (final request in adapter.pollRequests()) {
          unawaited(currentLink.write(request).catchError((_) {}));
        }
      });
    }
  }

  /// El enlace se perdió (la rueda se apagó o salió de rango):
  /// se limpia todo SIN enviar ninguna acción a la rueda.
  void _onLinkLost() {
    if (_state != WheelLinkState.connected) return;
    _diag('Enlace perdido');
    unawaited(_teardownLink());
    _telemetry = WheelTelemetry.neutral;
    _lastLiveAt = null;
    _errorMessage = 'Se perdió la conexión con la rueda.';
    _setState(WheelLinkState.error);
  }

  Future<void> _teardownLink() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    await _frameSub?.cancel();
    _frameSub = null;
    await _telemetrySub?.cancel();
    _telemetrySub = null;
    await _identitySub?.cancel();
    _identitySub = null;
    await _connectionSub?.cancel();
    _connectionSub = null;
    await _adapter?.dispose();
    _adapter = null;
    _link = null;
    _brandSniffed = false;
  }

  void _fail(String message) {
    _errorMessage = message;
    _setState(WheelLinkState.error);
  }

  void _setState(WheelLinkState next) {
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_teardownLink());
    unawaited(_scanSub?.cancel());
    unawaited(ble.dispose());
    super.dispose();
  }
}
