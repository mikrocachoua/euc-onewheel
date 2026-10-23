import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

import '../state/app_settings.dart';
import 'avas_engine.dart';
import 'avas_tone_synth.dart';

/// Reproductor de tono mínimo que usa el backend AVAS (interfaz
/// propia para poder probarlo sin el canal de plataforma).
abstract class AvasTonePlayer {
  /// Empieza a sonar [wavBytes] en bucle con el volumen dado.
  Future<void> startLoop(Uint8List wavBytes, double volume);

  /// Ajusta el volumen (0–1) del bucle en curso.
  Future<void> setVolume(double volume);

  /// Ajusta la velocidad de reproducción (1.0 = tono renderizado).
  Future<void> setRate(double rate);

  /// Detiene el sonido.
  Future<void> stop();
}

/// Reproductor real con audioplayers (iOS/Android).
class AudioplayersTonePlayer implements AvasTonePlayer {
  final AudioPlayer _player = AudioPlayer();

  @override
  Future<void> startLoop(Uint8List wavBytes, double volume) async {
    await _player.setReleaseMode(ReleaseMode.loop);
    await _player.setVolume(volume.clamp(0.0, 1.0));
    await _player.setPlaybackRate(1.0);
    await _player.play(BytesSource(wavBytes));
  }

  @override
  Future<void> setVolume(double volume) =>
      _player.setVolume(volume.clamp(0.0, 1.0));

  @override
  Future<void> setRate(double rate) =>
      _player.setPlaybackRate(rate.clamp(0.5, 2.0));

  @override
  Future<void> stop() => _player.stop();
}

/// Backend de audio REAL del AVAS: hace sonar el tono de motor y lo
/// sigue a la velocidad de la rueda.
///
/// Estrategia: el tono se renderiza como WAV a la frecuencia
/// objetivo (redondeada a Hz enteros = bucle sin clics) y suena en
/// bucle; las variaciones pequeñas de frecuencia se absorben con la
/// velocidad de reproducción (±6 %) y las grandes re-renderizando el
/// tono, como mucho cada 300 ms, para no machacar el reproductor en
/// cada tick de telemetría.
class AvasToneBackend implements AvasAudioBackend {
  AvasToneBackend({AvasTonePlayer? player})
      : _player = player ?? AudioplayersTonePlayer();

  final AvasTonePlayer _player;

  bool _playing = false;
  AvasPreset? _preset;
  double _renderedHz = 0;
  DateTime _lastRender = DateTime.fromMillisecondsSinceEpoch(0);

  /// Intervalo mínimo entre re-renderizados del tono.
  static const Duration renderThrottle = Duration(milliseconds: 300);

  @override
  void apply(AvasOutput output, {AvasPreset? preset}) {
    if (!output.sounding || preset == null) {
      _stopIfPlaying();
      return;
    }
    final targetHz = output.frequencyHz;
    if (!_playing || preset != _preset) {
      _start(preset, targetHz, output.volume);
      return;
    }
    _player.setVolume(output.volume);
    if (_renderedHz <= 0) return;
    final drift = (targetHz - _renderedHz).abs() / _renderedHz;
    if (drift > 0.03) {
      final now = DateTime.now();
      if (now.difference(_lastRender) >= renderThrottle) {
        _start(preset, targetHz, output.volume);
      } else {
        _player.setRate((targetHz / _renderedHz).clamp(0.9, 1.1));
      }
    } else {
      _player.setRate((targetHz / _renderedHz).clamp(0.94, 1.06));
    }
  }

  void _start(AvasPreset preset, double hz, double volume) {
    _preset = preset;
    _renderedHz = hz.round().toDouble();
    _lastRender = DateTime.now();
    _playing = true;
    _player.startLoop(
      synthMotorToneWav(freqHz: hz.round()),
      volume,
    );
  }

  void _stopIfPlaying() {
    if (!_playing) return;
    _playing = false;
    _preset = null;
    _renderedHz = 0;
    _player.stop();
  }

  @override
  void stop() => _stopIfPlaying();
}
