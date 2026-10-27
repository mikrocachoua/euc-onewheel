import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:euc_onewheel/services/ble/adapters/begode_adapter.dart';
import 'package:euc_onewheel/services/ble/adapters/inmotion_adapter.dart';
import 'package:euc_onewheel/services/ble/adapters/kingsong_adapter.dart';
import 'package:euc_onewheel/services/ble/adapters/ninebot_z_adapter.dart';
import 'package:euc_onewheel/services/ble/adapters/veteran_adapter.dart';
import 'package:euc_onewheel/services/ble/wheel_command.dart';

Uint8List hex(String s) {
  final clean = s.replaceAll(' ', '');
  final out = Uint8List(clean.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

String hexStr(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

List<String> framesOf(List<CommandStep>? steps) =>
    steps!.map((s) => hexStr(s.frame)).toList();

void main() {
  group('KingSong · comandos', () {
    final a = KingSongAdapter();

    test('luz: tramas 0x73 con el modo en data[2]', () {
      expect(framesOf(a.buildCommand(const LightRequest(LightState.on))),
          ['aa55130100000000000000000000000073145a5a']);
      expect(framesOf(a.buildCommand(const LightRequest(LightState.off))),
          ['aa55120100000000000000000000000073145a5a']);
      expect(framesOf(a.buildCommand(const LightRequest(LightState.strobe))),
          ['aa55140100000000000000000000000073145a5a']);
    });

    test('beep 0x88, calibración 0x89 y apagado 0x40', () {
      expect(framesOf(a.buildCommand(const BeepRequest())),
          ['aa55000000000000000000000000000088145a5a']);
      expect(framesOf(a.buildCommand(const CalibrationRequest())),
          ['aa55000000000000000000000000000089145a5a']);
      expect(framesOf(a.buildCommand(const PowerOffRequest())),
          ['aa55000000000000000000000000000040145a5a']);
    });

    test('pedales 0x87: modo, 0xE0 y el 0x15 especial del byte 17', () {
      final steps = a.buildCommand(const PedalModeRequest(1))!;
      expect(steps.single.frame[2], 1);
      expect(steps.single.frame[3], 0xE0);
      expect(steps.single.frame[16], 0x87);
      expect(steps.single.frame[17], 0x15);
    });

    test('alarmas + máxima viajan juntas en la 0x85', () {
      final steps = a.buildCommand(
          const SpeedAlarmsRequest([10, 20, 30], tiltBackKmh: 35))!;
      final f = steps.single.frame;
      expect(f[2], 10);
      expect(f[4], 20);
      expect(f[6], 30);
      expect(f[8], 35);
      expect(f[16], 0x85);
      // Sin la máxima no se construye (borraría el límite vigente).
      expect(a.buildCommand(const SpeedAlarmsRequest([10, 20, 30])), isNull);
      expect(a.buildCommand(const TiltBackRequest(30)), isNull);
    });

    test('bloqueo de motor: no verificado en KingSong, no se ofrece', () {
      expect(a.buildCommand(const MotorLockRequest(true)), isNull);
    });

    test('LED 0x6C con el modo en data[2]', () {
      final steps = a.buildCommand(const LedModeRequest(3))!;
      expect(steps.single.frame[2], 3);
      expect(steps.single.frame[16], 0x6C);
    });
  });

  group('Begode · comandos ASCII', () {
    final a = BegodeAdapter();

    test('luz: letra del modo + «b» de cierre a los 100 ms', () {
      final steps = a.buildCommand(const LightRequest(LightState.on))!;
      expect(framesOf(steps), ['51', '62']); // 'Q', 'b'
      expect(steps[0].delayBefore, Duration.zero);
      expect(steps[1].delayBefore, const Duration(milliseconds: 100));
      expect(framesOf(a.buildCommand(const LightRequest(LightState.off))),
          ['45', '62']); // 'E', 'b'
      expect(framesOf(a.buildCommand(const LightRequest(LightState.strobe))),
          ['54', '62']); // 'T', 'b'
    });

    test('beep directo, sin cierre', () {
      expect(framesOf(a.buildCommand(const BeepRequest())), ['62']);
    });

    test('pedales y modo de alarmas', () {
      expect(framesOf(a.buildCommand(const PedalModeRequest(0))),
          ['68', '62']); // 'h'
      expect(framesOf(a.buildCommand(const PedalModeRequest(2))),
          ['73', '62']); // 's'
      expect(framesOf(a.buildCommand(const AlarmModeRequest(0))),
          ['6f', '62']); // 'o' = dos alarmas
      expect(framesOf(a.buildCommand(const AlarmModeRequest(2))),
          ['69', '62']); // 'i' = apagadas
    });

    test('calibración: «c» y a los 300 ms «y»', () {
      final steps = a.buildCommand(const CalibrationRequest())!;
      expect(framesOf(steps), ['63', '79']);
      expect(steps[1].delayBefore, const Duration(milliseconds: 300));
    });

    test('tilt-back 25: la secuencia temporizada completa', () {
      final steps = a.buildCommand(const TiltBackRequest(25))!;
      // b · W · Y · '2' · '5' · b · b
      expect(framesOf(steps), ['62', '57', '59', '32', '35', '62', '62']);
      expect(steps.map((s) => s.delayBefore.inMilliseconds).toList(),
          [0, 100, 100, 100, 100, 100, 100]);
    });

    test('tilt-back 0: secuencia de «sin límite»', () {
      final steps = a.buildCommand(const TiltBackRequest(0))!;
      expect(framesOf(steps), ['62', '22', '62', '62']); // b " b b
    });

    test('LED y volumen: W + letra + dígito + b', () {
      expect(framesOf(a.buildCommand(const LedModeRequest(4))),
          ['57', '4d', '34', '62']); // W M '4' b
      expect(framesOf(a.buildCommand(const VolumeRequest(7))),
          ['57', '42', '37', '62']); // W B '7' b
    });

    test('apagar y bloquear: no verificados, no se ofrecen', () {
      expect(a.buildCommand(const PowerOffRequest()), isNull);
      expect(a.buildCommand(const MotorLockRequest(true)), isNull);
    });
  });

  group('Veteran · comandos ASCII', () {
    final a = VeteranAdapter();

    test('luz con palabras completas; sin estrobo', () {
      expect(framesOf(a.buildCommand(const LightRequest(LightState.on))),
          [hexStr('SetLightON'.codeUnits)]);
      expect(framesOf(a.buildCommand(const LightRequest(LightState.off))),
          [hexStr('SetLightOFF'.codeUnits)]);
      expect(a.buildCommand(const LightRequest(LightState.strobe)), isNull);
    });

    test('pedales SETx y beep «b» en modelos anteriores a la v3', () {
      expect(framesOf(a.buildCommand(const PedalModeRequest(0))),
          [hexStr('SETh'.codeUnits)]);
      expect(framesOf(a.buildCommand(const PedalModeRequest(2))),
          [hexStr('SETs'.codeUnits)]);
      expect(framesOf(a.buildCommand(const BeepRequest())), ['62']);
    });

    test('lo no verificado no se ofrece', () {
      expect(a.buildCommand(const TiltBackRequest(25)), isNull);
      expect(a.buildCommand(const CalibrationRequest()), isNull);
      expect(a.buildCommand(const MotorLockRequest(true)), isNull);
      expect(a.buildCommand(const PowerOffRequest()), isNull);
    });
  });

  group('InMotion V2 · comandos', () {
    // Respuestas reales de «tipo de vehículo» para fijar el modelo.
    const carTypeV11y = 'aaaa110882010206020101009c';
    const carTypeV12hs = 'aaaa110882010207010103009c';
    const carTypeV11 = 'AAAA110882010206010201009C';
    const versionsV11Old =
        'AAAA111D820622080004030F000602214000010110000602230D00010107000001F3';

    InMotionAdapter adapterFor(String carType, [String? extra]) {
      final a = InMotionAdapter();
      a.decode(hex(carType));
      if (extra != null) a.decode(hex(extra));
      return a;
    }

    test('V11Y: luz con código 0x50', () {
      final a = adapterFor(carTypeV11y);
      expect(framesOf(a.buildCommand(const LightRequest(LightState.on))),
          ['aaaa140360500126']);
    });

    test('V11Y: velocidad máxima 25 km/h (trama combinada de 5 bytes)', () {
      final a = adapterFor(carTypeV11y);
      expect(framesOf(a.buildCommand(const TiltBackRequest(25))),
          ['aaaa14066021c40900009e']);
    });

    test('V11Y: bloqueo, calibración y beep', () {
      final a = adapterFor(carTypeV11y);
      expect(framesOf(a.buildCommand(const MotorLockRequest(true))),
          ['aaaa140360310147']);
      expect(framesOf(a.buildCommand(const CalibrationRequest())),
          ['aaaa1405605201000123']);
      expect(framesOf(a.buildCommand(const BeepRequest())),
          ['aaaa14046051026447']);
    });

    test('V11Y: apagado en dos etapas con espera', () {
      final a = adapterFor(carTypeV11y);
      final steps = a.buildCommand(const PowerOffRequest())!;
      expect(framesOf(steps), ['aaaa110303810090', 'aaaa1102038292']);
      expect(steps[1].delayBefore, const Duration(milliseconds: 600));
    });

    test('V12: luz de tres bytes y alarmas 0x3E', () {
      final a = adapterFor(carTypeV12hs);
      expect(framesOf(a.buildCommand(const LightRequest(LightState.on))),
          ['aaaa14046050010021']);
      expect(framesOf(a.buildCommand(const SpeedAlarmsRequest([20, 30]))),
          ['aaaa1406603ed007b80b28']);
    });

    test('V11 con placa antigua: la luz usa el código 0x40', () {
      final a = adapterFor(carTypeV11, versionsV11Old);
      expect(framesOf(a.buildCommand(const LightRequest(LightState.on))),
          ['aaaa140360400136']);
    });

    test('V9: luz de 2 bytes, claxon playSound y calibración 0x52', () {
      const carTypeV9 = 'aaaa11088201020c0101010095';
      final a = adapterFor(carTypeV9);
      expect(a.factoryMaxKmh, 45);
      expect(a.usesCombinedMaxAlarm, isTrue);
      expect(framesOf(a.buildCommand(const LightRequest(LightState.on))),
          ['aaaa140360500126']);
      expect(framesOf(a.buildCommand(const BeepRequest())),
          ['aaaa14046051180138']);
      expect(framesOf(a.buildCommand(const CalibrationRequest())),
          ['aaaa1405605201000123']);
    });

    test('V9: máxima de 5 bytes y tope de fábrica 45 km/h', () {
      const carTypeV9 = 'aaaa11088201020c0101010095';
      final a = adapterFor(carTypeV9);
      expect(framesOf(a.buildCommand(const TiltBackRequest(25))),
          ['aaaa14066021c40900009e']);
      // 60 km/h se recorta al tope de fábrica (45) en el envío.
      expect(framesOf(a.buildCommand(const TiltBackRequest(60))),
          ['aaaa1406602194110000d6']);
    });

    test('V9: una sola alarma, siempre junto con la máxima', () {
      const carTypeV9 = 'aaaa11088201020c0101010095';
      final a = adapterFor(carTypeV9);
      expect(
          framesOf(a.buildCommand(
              const SpeedAlarmsRequest([30], tiltBackKmh: 25))),
          ['aaaa14066021c409b80b2d']);
      // Sin máxima no hay trama combinada: no se ofrece nada.
      expect(a.buildCommand(const SpeedAlarmsRequest([20, 30])), isNull);
    });
  });

  group('Ninebot Z · comandos (gamma en ceros, antes de negociar)', () {
    final a = NinebotZAdapter();

    test('bloqueo 0x70 con su CRC', () {
      expect(framesOf(a.buildCommand(const MotorLockRequest(true))),
          ['5aa5023e140370010037ff']);
      expect(framesOf(a.buildCommand(const MotorLockRequest(false))),
          ['5aa5023e140370000038ff']);
    });

    test('tilt-back: activa el modo limitado y fija la velocidad', () {
      final steps = a.buildCommand(const TiltBackRequest(20))!;
      expect(framesOf(steps),
          ['5aa5013e1403720136ff', '5aa5023e140374d0075dfe']);
    });

    test('alarmas 1–3 en parámetros consecutivos', () {
      final steps = a.buildCommand(const SpeedAlarmsRequest([15, 20, 25]))!;
      expect(steps, hasLength(3));
      expect(hexStr(steps[0].frame), '5aa5023e14037ddc054afe');
      expect(steps[1].frame[6], 0x7E);
      expect(steps[2].frame[6], 0x7F);
    });

    test('calibración, LED y volumen (nivel desplazado 3 bits)', () {
      expect(framesOf(a.buildCommand(const CalibrationRequest())),
          ['5aa5023e140375010032ff']);
      expect(framesOf(a.buildCommand(const VolumeRequest(5))),
          ['5aa5023e1403f528008bfe']);
      final led = a.buildCommand(const LedModeRequest(2))!;
      expect(led.single.frame[6], 0xC6);
    });

    test('luz: no verificada (DriveFlags), no se ofrece', () {
      expect(a.buildCommand(const LightRequest(LightState.on)), isNull);
      expect(a.buildCommand(const PowerOffRequest()), isNull);
    });
  });
}
