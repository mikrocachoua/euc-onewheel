import 'dart:typed_data';

import '../../models/wheel_telemetry.dart';

/// Comandos que la app puede enviar a la rueda, clasificados por su
/// nivel de riesgo según la regla de seguridad del usuario.
enum WheelCommand {
  powerOff,
  motorLock,
  calibration,
  tiltBack,
  speedAlarms,
  pedalMode,
  gyroAngle,
  transportMode,
  light,
  led,
  volume,
  beep;

  /// Nivel de riesgo del comando:
  /// - **crítico**: altera la dinámica o puede dejar la rueda
  ///   inutilizable/apagada; prohibido en movimiento.
  /// - **moderado**: sin efecto dinámico directo (luz, LED, volumen),
  ///   pero del tipo «set»: exige confirmación explícita.
  /// - **bajo**: beep de prueba; sin confirmación.
  CommandCriticality get criticality => switch (this) {
        WheelCommand.powerOff ||
        WheelCommand.motorLock ||
        WheelCommand.calibration ||
        WheelCommand.tiltBack ||
        WheelCommand.speedAlarms ||
        WheelCommand.pedalMode ||
        WheelCommand.gyroAngle ||
        WheelCommand.transportMode =>
          CommandCriticality.critical,
        WheelCommand.light ||
        WheelCommand.led ||
        WheelCommand.volume =>
          CommandCriticality.moderate,
        WheelCommand.beep => CommandCriticality.low,
      };
}

enum CommandCriticality { critical, moderate, low }

/// Resultado de pasar un comando por la compuerta de seguridad.
class GateVerdict {
  const GateVerdict.allow()
      : allowed = true,
        reason = null;
  const GateVerdict.block(this.reason) : allowed = false;

  final bool allowed;

  /// Por qué se bloqueó (texto para mostrar al usuario); null si pasó.
  final String? reason;
}

/// Registro de auditoría de un comando que SÍ salió hacia la rueda.
class GateLogEntry {
  const GateLogEntry({
    required this.command,
    required this.at,
    required this.speedKmh,
  });

  final WheelCommand command;
  final DateTime at;
  final double speedKmh;
}

/// **Único punto de salida de comandos hacia la rueda.**
///
/// Toda escritura de control (presente o futura) debe pasar por
/// [execute]; nadie más en la app debe escribir comandos en la
/// característica BLE de control. Regla dura del usuario:
///
/// - Los comandos **críticos** (apagar, bloqueo de motor, calibración,
///   tilt-back, alarmas de velocidad, modo de pedales, ángulo gyro y
///   modo transporte) solo salen si la última telemetría válida marca
///   **velocidad = 0**, el dato es **fresco** (< 2 s) y el usuario dio
///   **confirmación explícita**. Si la rueda se mueve, se bloquean
///   por software, sin excepción.
/// - Los comandos **moderados** (luz, LED, volumen) no alteran la
///   dinámica: pueden salir en movimiento, pero igualmente exigen
///   confirmación explícita por ser del tipo «set».
/// - Perder el enlace BLE nunca dispara ninguna acción: la compuerta
///   no tiene efectos secundarios al desconectar; sin enlace, todo
///   comando se bloquea.
class SafetyGate {
  SafetyGate({
    required bool Function() isConnected,
    required Future<void> Function(Uint8List frame) send,
    DateTime Function()? now,
  })  : _isConnected = isConnected,
        _send = send,
        _now = now ?? DateTime.now;

  /// Máxima edad de la telemetría para autorizar un comando crítico.
  static const Duration maxTelemetryAge = Duration(seconds: 2);

  final bool Function() _isConnected;
  final Future<void> Function(Uint8List frame) _send;
  final DateTime Function() _now;
  final List<GateLogEntry> _log = [];

  /// Comandos que la compuerta dejó salir, en orden (auditoría).
  List<GateLogEntry> get log => List.unmodifiable(_log);

  /// Evalúa [command] y, solo si pasa todas las reglas, envía [frame]
  /// por el transporte. Devuelve el veredicto (permitido o el motivo
  /// del bloqueo) sin lanzar excepciones por las reglas de seguridad.
  Future<GateVerdict> execute({
    required WheelCommand command,
    required Uint8List frame,
    required WheelTelemetry telemetry,
    required DateTime? telemetryAt,
    required bool userConfirmed,
  }) async {
    if (!_isConnected()) {
      return const GateVerdict.block(
          'Sin conexión con la rueda: ningún comando puede salir.');
    }

    switch (command.criticality) {
      case CommandCriticality.critical:
        if (telemetryAt == null) {
          return const GateVerdict.block(
              'Aún no hay telemetría de la rueda: comando crítico bloqueado.');
        }
        if (_now().difference(telemetryAt) > maxTelemetryAge) {
          return const GateVerdict.block(
              'La telemetría no es reciente: comando crítico bloqueado.');
        }
        if (telemetry.isMoving) {
          return const GateVerdict.block(
              'La rueda está en movimiento: este comando solo puede '
              'usarse con la rueda totalmente detenida.');
        }
        if (!userConfirmed) {
          return const GateVerdict.block(
              'Este comando requiere tu confirmación explícita.');
        }
      case CommandCriticality.moderate:
        if (!userConfirmed) {
          return const GateVerdict.block(
              'Este comando requiere tu confirmación explícita.');
        }
      case CommandCriticality.low:
        break;
    }

    await _send(frame);
    _log.add(GateLogEntry(
      command: command,
      at: _now(),
      speedKmh: telemetry.speedKmh,
    ));
    return const GateVerdict.allow();
  }
}
