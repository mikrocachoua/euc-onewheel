import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:euc_onewheel/services/avas_engine.dart';
import 'package:euc_onewheel/services/avas_tone_backend.dart';
import 'package:euc_onewheel/services/avas_tone_synth.dart';
import 'package:euc_onewheel/state/app_settings.dart';

/// Reproductor falso: registra las llamadas del backend.
class FakeTonePlayer implements AvasTonePlayer {
  final List<Uint8List> started = [];
  final List<double> volumes = [];
  final List<double> rates = [];
  int stopCalls = 0;

  @override
  Future<void> startLoop(Uint8List wavBytes, double volume) async {
    started.add(wavBytes);
    volumes.add(volume);
  }

  @override
  Future<void> setVolume(double volume) async => volumes.add(volume);

  @override
  Future<void> setRate(double rate) async => rates.add(rate);

  @override
  Future<void> stop() async => stopCalls++;
}

AvasOutput out(double hz, {double volume = 0.7}) => AvasOutput(
      sounding: true,
      frequencyHz: hz,
      volume: volume,
      ducked: false,
    );

void main() {
  group('synthMotorToneWav', () {
    test('WAV PCM válido: cabecera, tamaño y 1 s a 22050 Hz', () {
      final wav = synthMotorToneWav(freqHz: 100);
      expect(wav.length, 44 + 22050 * 2);
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
      final bd = ByteData.sublistView(wav);
      expect(bd.getUint32(24, Endian.little), 22050); // sample rate
      expect(bd.getUint16(34, Endian.little), 16); // bits por muestra
    });

    test('la señal es periódica con la frecuencia pedida (cruces por cero)',
        () {
      const freq = 120;
      final wav = synthMotorToneWav(freqHz: freq);
      final bd = ByteData.sublistView(wav);
      var crossings = 0;
      var prev = bd.getInt16(44, Endian.little);
      for (var i = 1; i < 22050; i++) {
        final s = bd.getInt16(44 + i * 2, Endian.little);
        if ((prev < 0 && s >= 0) || (prev >= 0 && s < 0)) crossings++;
        prev = s;
      }
      // Fundamental + armónicos: los cruces dominantes son los del
      // fundamental, 2 por ciclo → ~2 × freq, con tolerancia amplia.
      expect(crossings, greaterThan((freq * 2 * 0.8).round()));
      expect(crossings, lessThan((freq * 2 * 1.6).round()));
    });

    test('amplitud dentro de rango (sin saturación digital)', () {
      final wav = synthMotorToneWav(freqHz: 90);
      final bd = ByteData.sublistView(wav);
      var maxAbs = 0;
      for (var i = 0; i < 22050; i++) {
        final s = bd.getInt16(44 + i * 2, Endian.little).abs();
        if (s > maxAbs) maxAbs = s;
      }
      expect(maxAbs, lessThan(32767));
      expect(maxAbs, greaterThan(15000)); // suena de verdad
    });

    test('el bucle empalma: la señal cierra el ciclo en t = 1 s', () {
      // Con frecuencia entera, el último tramo vuelve hacia el valor
      // inicial (0): la última muestra es pequeña en valor absoluto.
      final wav = synthMotorToneWav(freqHz: 200);
      final bd = ByteData.sublistView(wav);
      final last = bd.getInt16(44 + 22049 * 2, Endian.little).abs();
      expect(last, lessThan(6000));
    });
  });

  group('AvasToneBackend', () {
    test('al sonar arranca el bucle con el tono del preset', () {
      final player = FakeTonePlayer();
      final backend = AvasToneBackend(player: player);
      backend.apply(out(90), preset: AvasPreset.deportivo);
      expect(player.started, hasLength(1));
      expect(player.started.single.length, 44 + 22050 * 2);
      expect(player.volumes.first, 0.7);
    });

    test('silencio → detiene; y sin preset no suena', () {
      final player = FakeTonePlayer();
      final backend = AvasToneBackend(player: player);
      backend.apply(out(90), preset: AvasPreset.clasico);
      backend.apply(AvasOutput.silent, preset: AvasPreset.clasico);
      expect(player.stopCalls, 1);
      backend.apply(out(90)); // sin preset: no debe sonar
      expect(player.started, hasLength(1));
    });

    test('cambio de preset re-renderiza; deriva pequeña usa la velocidad',
        () {
      final player = FakeTonePlayer();
      final backend = AvasToneBackend(player: player);
      backend.apply(out(60), preset: AvasPreset.clasico);
      backend.apply(out(200), preset: AvasPreset.electrico);
      expect(player.started, hasLength(2)); // re-render por preset
      // Misma sesión, deriva del 1 %: no re-renderiza, ajusta rate.
      backend.apply(out(202), preset: AvasPreset.electrico);
      expect(player.started, hasLength(2));
      expect(player.rates, isNotEmpty);
    });

    test('stop() detiene el bucle en curso', () {
      final player = FakeTonePlayer();
      final backend = AvasToneBackend(player: player);
      backend.apply(out(120), preset: AvasPreset.personalizado);
      backend.stop();
      expect(player.stopCalls, 1);
    });
  });
}
