import 'dart:async';
import 'dart:typed_data';

import '../../../models/wheel_capabilities.dart';
import '../../../models/wheel_identity.dart';
import '../../../models/wheel_telemetry.dart';

/// Interfaz común de los adaptadores por marca.
///
/// Un adaptador sabe decodificar las tramas crudas de su protocolo
/// hacia [WheelTelemetry] e identidad de la rueda. La escritura de
/// comandos NO vive aquí: todo comando debe salir por la compuerta
/// de seguridad (safety_gate.dart), que es el único punto de salida.
abstract class WheelAdapter {
  /// Marca que este adaptador atiende.
  WheelBrand get brand;

  /// Capacidades ya implementadas de este adaptador.
  WheelCapabilities get capabilities;

  /// Último snapshot de telemetría decodificado.
  WheelTelemetry get telemetry;

  /// Identidad conocida de la rueda (se completa con las tramas).
  WheelIdentity get identity;

  /// Avisa cuándo cambia el snapshot de telemetría.
  Stream<WheelTelemetry> get telemetryStream;

  /// Avisa cuándo cambia la identidad (modelo, serie, firmware).
  Stream<WheelIdentity> get identityStream;

  /// Alimenta una trama cruda recibida por BLE.
  ///
  /// Devuelve `true` si la trama era de **telemetría en vivo** del
  /// protocolo (el controlador la usa para marcar el dato como
  /// fresco ante la compuerta de seguridad); `false` si era otra
  /// trama válida (nombre, serie, ajustes…) o si no se reconoció.
  bool decode(Uint8List frame);

  /// Tramas de **solo lectura** que conviene pedir al conectar
  /// (nombre/modelo, número de serie…). No son comandos de control:
  /// no pasan por la compuerta de seguridad.
  List<Uint8List> initialRequests();

  /// Tramas de **solo lectura** a repetir mientras dure la
  /// conexión, para los protocolos que no emiten en continuo y
  /// solo responden cuando se les pregunta (p. ej. InMotion V2).
  /// El controlador las envía cada [pollInterval]. Vacío si la
  /// marca emite en continuo y no necesita sondeo.
  List<Uint8List> pollRequests();

  /// Intervalo entre rondas de [pollRequests]; `null` si la
  /// marca no necesita sondeo.
  Duration? get pollInterval;

  /// Libera los streams del adaptador al desconectar.
  Future<void> dispose();
}

/// Base con la maquinaria común de streams para los adaptadores.
abstract class BaseWheelAdapter implements WheelAdapter {
  final StreamController<WheelTelemetry> _telemetryController =
      StreamController<WheelTelemetry>.broadcast();
  final StreamController<WheelIdentity> _identityController =
      StreamController<WheelIdentity>.broadcast();

  WheelTelemetry _telemetry = WheelTelemetry.neutral;
  WheelIdentity _identity = const WheelIdentity();

  @override
  WheelTelemetry get telemetry => _telemetry;

  @override
  WheelIdentity get identity => _identity;

  @override
  Stream<WheelTelemetry> get telemetryStream => _telemetryController.stream;

  @override
  Stream<WheelIdentity> get identityStream => _identityController.stream;

  /// Actualiza el snapshot y lo emite solo si cambió.
  void updateTelemetry(WheelTelemetry next) {
    if (next == _telemetry) return;
    _telemetry = next;
    if (!_telemetryController.isClosed) _telemetryController.add(next);
  }

  /// Por omisión, la marca emite en continuo: sin sondeo.
  @override
  List<Uint8List> pollRequests() => const <Uint8List>[];

  @override
  Duration? get pollInterval => null;

  /// Actualiza la identidad y la emite solo si cambió.
  void updateIdentity(WheelIdentity next) {
    if (next == _identity) return;
    _identity = next;
    if (!_identityController.isClosed) _identityController.add(next);
  }

  @override
  Future<void> dispose() async {
    await _telemetryController.close();
    await _identityController.close();
  }
}
