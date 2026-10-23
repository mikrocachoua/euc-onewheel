import 'dart:math' as math;
import 'dart:typed_data';

/// Sintetiza el tono de motor del AVAS como un WAV PCM de 16 bits de
/// 1 segundo, listo para sonar en bucle.
///
/// La frecuencia pedida se redondea a un entero de Hz: con una
/// duración de exactamente 1 s, el fundamental y todos sus armónicos
/// completan un número entero de ciclos, así que el bucle empalma
/// sin clics ni saltos. El timbre es un zumbido de motor: fundamental
/// + armónicos decrecientes (2º, 3º y 4º).
Uint8List synthMotorToneWav({required int freqHz, int sampleRate = 22050}) {
  final freq = freqHz <= 0 ? 1 : freqHz;
  final frames = sampleRate; // 1 segundo
  final data = Int16List(frames);
  const harmonics = <double>[1.0, 0.55, 0.30, 0.16];
  var norm = 0.0;
  for (final h in harmonics) {
    norm += h;
  }
  for (var i = 0; i < frames; i++) {
    final t = i / sampleRate;
    var s = 0.0;
    for (var k = 0; k < harmonics.length; k++) {
      s += harmonics[k] * math.sin(2 * math.pi * freq * (k + 1) * t);
    }
    s = s / norm * 0.8;
    data[i] = (s * 32767).round().clamp(-32768, 32767);
  }

  final bytes = BytesBuilder();
  void u16(int v) => bytes.add([v & 0xFF, (v >> 8) & 0xFF]);
  void u32(int v) => bytes.add([
        v & 0xFF,
        (v >> 8) & 0xFF,
        (v >> 16) & 0xFF,
        (v >> 24) & 0xFF,
      ]);
  void ascii(String s) => bytes.add(s.codeUnits);

  final dataBytes = frames * 2;
  ascii('RIFF');
  u32(36 + dataBytes);
  ascii('WAVE');
  ascii('fmt ');
  u32(16); // tamaño del subchunk fmt
  u16(1); // PCM
  u16(1); // mono
  u32(sampleRate);
  u32(sampleRate * 2); // byte rate
  u16(2); // block align
  u16(16); // bits por muestra
  ascii('data');
  u32(dataBytes);
  final pcm = Uint8List(dataBytes);
  for (var i = 0; i < frames; i++) {
    final v = data[i];
    pcm[i * 2] = v & 0xFF;
    pcm[i * 2 + 1] = (v >> 8) & 0xFF;
  }
  bytes.add(pcm);
  return bytes.toBytes();
}
