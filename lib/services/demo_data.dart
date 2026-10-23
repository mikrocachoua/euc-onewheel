import 'dart:async';
import 'dart:math' as math;

import '../models/wheel_telemetry.dart';

/// Simulador de telemetría para el MODO DEMO: sin rueda real, genera
/// valores verosímiles que se mueven (velocidad que sube y baja,
/// batería que se descarga poco a poco) para enseñar el panel, las
/// alarmas y el AVAS tal como se verían rodando.
///
/// Es genérico: no representa a ninguna marca ni modelo concretos.
class DemoTelemetry {
  DemoTelemetry({this.tick = const Duration(milliseconds: 600)});

  final Duration tick;
  final _controller = StreamController<WheelTelemetry>.broadcast();
  Timer? _timer;
  int _ticks = 0;
  double _battery = 46; // % inicial del ejemplo demo
  int _tripM = 0;

  Stream<WheelTelemetry> get stream => _controller.stream;
  bool get running => _timer != null;

  void start() {
    if (_timer != null) return;
    _emit();
    _timer = Timer.periodic(tick, (_) => _emit());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void _emit() {
    _ticks++;
    final t = _ticks * tick.inMilliseconds / 1000.0;
    // Velocidad: onda suave entre 0 y ~34 km/h, con pausas a cero.
    final wave = math.sin(t / 7) * 0.5 + 0.5; // 0..1
    final speed = (wave * 34).clamp(0, 60).toDouble();
    _tripM += (speed / 3.6 * (tick.inMilliseconds / 1000)).round();
    _battery = math.max(5, _battery - (speed > 1 ? 0.01 : 0));
    final voltage = 58 + (_battery / 100) * 26; // 58–84 V según carga
    final current = speed <= 0.5 ? 0.4 : 2 + speed * 0.55;
    final power = voltage * current;
    final pwm = (speed / 60 * 100).clamp(0, 98).toDouble();
    _controller.add(WheelTelemetry(
      speedKmh: speed,
      voltageV: voltage,
      currentA: current,
      powerW: power,
      batteryPct: _battery.round(),
      tempC: 31 + wave * 9,
      pwmPct: pwm,
      distanceM: _tripM,
      totalDistanceM: 1284500 + _tripM,
    ));
  }

  Future<void> dispose() async {
    stop();
    await _controller.close();
  }
}

/// Un dispositivo Bluetooth de ejemplo para la lista del modo demo:
/// representa el entorno típico de una casa, no una rueda concreta.
class DemoDevice {
  const DemoDevice(this.name, {this.isWheel = false});
  final String name;
  final bool isWheel;
}

/// Ejemplos del entorno para la lista «ENCONTRADO» en modo demo.
const List<DemoDevice> demoEnvironmentDevices = [
  DemoDevice('Mi rueda (demo)', isWheel: true),
  DemoDevice('MacBook Pro'),
  DemoDevice('Sala'),
  DemoDevice('TV Recámara principal'),
  DemoDevice('Audífonos inalámbricos'),
];
