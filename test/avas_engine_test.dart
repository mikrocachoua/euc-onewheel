import 'package:euc_onewheel/services/avas_engine.dart';
import 'package:euc_onewheel/state/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

AvasOutput _compute({
  bool enabled = true,
  bool connected = true,
  double speed = 25,
  bool alarm = false,
  AvasPreset preset = AvasPreset.deportivo,
  double volume = 0.7,
}) =>
    computeAvas(
      enabled: enabled,
      connected: connected,
      speedKmh: speed,
      alarmActive: alarm,
      preset: preset,
      volume: volume,
    );

void main() {
  group('AVAS · sonido de motor (lógica, sin audio real)', () {
    test('apagado por defecto: sin interruptor, silencio', () {
      final out = _compute(enabled: false);
      expect(out.sounding, isFalse);
      expect(out.volume, 0);
    });

    test('sin rueda conectada no suena aunque esté activado', () {
      expect(_compute(connected: false).sounding, isFalse);
    });

    test('con la rueda detenida no suena', () {
      expect(_compute(speed: 0).sounding, isFalse);
      expect(_compute(speed: -2).sounding, isFalse);
    });

    test('rodando suena, con el volumen configurado', () {
      final out = _compute();
      expect(out.sounding, isTrue);
      expect(out.ducked, isFalse);
      expect(out.volume, closeTo(0.7, 0.001));
    });

    test('el tono sube con la velocidad dentro del rango del preset', () {
      final slow = _compute(speed: 5);
      final fast = _compute(speed: 45);
      expect(fast.frequencyHz, greaterThan(slow.frequencyHz));
      expect(
          slow.frequencyHz, greaterThanOrEqualTo(AvasPreset.deportivo.baseHz));
      expect(fast.frequencyHz, lessThanOrEqualTo(AvasPreset.deportivo.maxHz));
    });

    test('a la velocidad tope el tono llega al máximo del preset', () {
      final out = _compute(speed: avasFullSpeedKmh);
      expect(out.frequencyHz, AvasPreset.deportivo.maxHz);
    });

    test('cada preset tiene su propio rango de tonos', () {
      final electrico = _compute(preset: AvasPreset.electrico, speed: 30);
      final clasico = _compute(preset: AvasPreset.clasico, speed: 30);
      expect(electrico.frequencyHz, greaterThan(clasico.frequencyHz));
    });

    test('con una alarma real, el volumen se agacha casi a silencio', () {
      final out = _compute(alarm: true);
      expect(out.sounding, isTrue);
      expect(out.ducked, isTrue);
      expect(out.volume, closeTo(0.7 * avasDuckFactor, 0.001));
      expect(out.volume, lessThan(0.1));
    });

    test('el backend silencioso registra la última salida', () {
      final backend = SilentAvasBackend();
      final out = _compute();
      backend.apply(out);
      expect(backend.lastOutput.sounding, isTrue);
      backend.stop();
      expect(backend.stopped, isTrue);
      expect(backend.lastOutput.sounding, isFalse);
    });
  });
}
