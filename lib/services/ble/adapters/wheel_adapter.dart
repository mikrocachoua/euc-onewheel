import 'dart:async';
import 'dart:typed_data';

import '../../../models/wheel_capabilities.dart';
import '../../../models/wheel_identity.dart';
import '../../../models/wheel_telemetry.dart';
import '../wheel_command.dart';

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

  /// Velocidad máxima de fábrica del modelo detectado, en km/h, o
  /// `null` si no está verificada para ese modelo. La tarjeta la usa
  /// como tope del stepper y el adaptador como guarda en el envío:
  /// ningún comando de máxima o alarma puede superar este valor.
  /// Solo se publica con dato verificado, nunca estimado.
  int? get factoryMaxKmh => null;

  /// `true` si máxima y alarma viajan en una sola trama combinada
  /// (familia nueva InMotion: V9, V11Y, V13, V14, V12S). La tarjeta
  /// muestra entonces una sección conjunta en vez de dos editores
  /// separados, porque mandar la alarma sin la máxima la borraría.
  bool get usesCombinedMaxAlarm => false;

  /// Petición de solo lectura para pedir los ajustes actuales de
  /// la rueda (máxima, alarmas…), o `null` si la marca no la
  /// tiene verificada. No es un comando de control: no pasa por
  /// la compuerta. El controlador la manda al conectar y tras
  /// cambiar la máxima o las alarmas, para re-leer lo guardado.
  Uint8List? get settingsRequest => null;

  /// Máxima y alarma que la rueda REPORTA tener guardadas, en
  /// km/h, o `null` si aún no llega ninguna trama de ajustes.
  /// Son la verdad de la rueda, no lo que el usuario escribió en
  /// los steppers: la tarjeta las muestra tal cual para verificar
  /// que un cambio sí se guardó. No hace falta un stream propio:
  /// la tarjeta se reconstruye con cada tick de telemetría (en
  /// V2 el sondeo corre cada 300 ms), así que aparecen solas.
  double? get reportedMaxKmh => null;
  double? get reportedAlarmKmh => null;

  /// Tramas de **solo lectura** a repetir mientras dure la
  /// conexión, para los protocolos que no emiten en continuo y
  /// solo responden cuando se les pregunta (p. ej. InMotion V2).
  /// El controlador las envía cada [pollInterval]. Vacío si la
  /// marca emite en continuo y no necesita sondeo.
  List<Uint8List> pollRequests();

  /// Intervalo entre rondas de [pollRequests]; `null` si la
  /// marca no necesita sondeo.
  Duration? get pollInterval;

  /// Construye los pasos (tramas + esperas) para ejecutar [request]
  /// en esta marca, o `null` si el comando no está implementado o no
  /// está verificado para ella. NUNCA escribe por sí mismo: el
  /// controlador pasa cada trama por la compuerta de seguridad antes
  /// de enviarla (la compuerta es el único punto de salida).
  List<CommandStep>? buildCommand(WheelCommandRequest request);

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

  /// Sin tope verificado por omisión (cada marca lo publica cuando
  /// tiene dato verificado; ver WheelAdapter.factoryMaxKmh).
  @override
  int? get factoryMaxKmh => null;

  /// Sin trama combinada por omisión (solo la familia nueva
  /// InMotion la usa; ver WheelAdapter.usesCombinedMaxAlarm).
  @override
  bool get usesCombinedMaxAlarm => false;

  /// Sin petición de ajustes por omisión (cada marca la publica
  /// cuando la tiene verificada; ver WheelAdapter.settingsRequest).
  @override
  Uint8List? get settingsRequest => null;

  /// Sin ajustes reportados por omisión.
  @override
  double? get reportedMaxKmh => null;
  @override
  double? get reportedAlarmKmh => null;

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

  /// Por omisión, ningún comando de control: cada adaptador
  /// implementa solo los que tiene verificados para su marca.
  @override
  List<CommandStep>? buildCommand(WheelCommandRequest request) => null;

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
