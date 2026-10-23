import 'package:euc_onewheel/state/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppSettings · valores por defecto (base v2)', () {
    test('tema oscuro deportivo, métrico, AVAS apagado', () {
      final s = AppSettings();
      expect(s.themeChoice, AppThemeChoice.oscuro);
      expect(s.imperial, isFalse);
      expect(s.tempFahrenheit, isFalse);
      expect(s.pressurePsi, isFalse);
      expect(s.avasEnabled, isFalse);
      expect(s.avasPreset, AvasPreset.deportivo);
      expect(s.autoTripResetHours, 6);
      expect(s.demoMode, isFalse);
      expect(s.leaderboards, isTrue);
    });

    test('el panel trae batería, voltaje, potencia y temperatura', () {
      final s = AppSettings();
      expect(
        s.panelIndicators,
        containsAll(<PanelIndicator>[
          PanelIndicator.bateria,
          PanelIndicator.voltaje,
          PanelIndicator.potencia,
          PanelIndicator.temperatura,
        ]),
      );
    });

    test('las cinco alarmas existen con umbrales razonables', () {
      final s = AppSettings();
      expect(s.alarms.keys, containsAll(AlarmKind.values));
      expect(s.alarms[AlarmKind.velocidad]!.value, 30);
      expect(s.alarms[AlarmKind.pwm]!.value, 85);
    });
  });

  group('AppSettings · JSON ida y vuelta', () {
    test('todo lo configurable sobrevive a guardar y recargar', () {
      final s = AppSettings()
        ..themeChoice = AppThemeChoice.claro
        ..imperial = true
        ..tempFahrenheit = true
        ..pressurePsi = true
        ..showIntroTips = false
        ..lockOrientation = true
        ..keepAwake = true
        ..autoGpsRecording = true
        ..autoTripResetHours = 12
        ..panelIndicators = [PanelIndicator.bateria, PanelIndicator.pwm]
        ..panelSize = PanelIndicatorSize.grande
        ..autoVolume = true
        ..avasEnabled = true
        ..avasPreset = AvasPreset.electrico
        ..avasVolume = 0.4
        ..customBeep = true
        ..locationVisibility = VisibilityChoice.amigos
        ..profileVisibility = VisibilityChoice.nadie
        ..enhancedLocationPrecision = true
        ..backgroundLocation = true
        ..leaderboards = false
        ..mapFriendsOnly = true
        ..mapOnlineOnly = true
        ..mapConnectedOnly = true
        ..customDeviceName = 'Mi rueda'
        ..demoMode = true;
      s.alarms[AlarmKind.velocidad] =
          const AlarmThreshold(enabled: false, value: 42);

      final back = AppSettings.fromJson(s.toJson());
      expect(back.themeChoice, AppThemeChoice.claro);
      expect(back.imperial, isTrue);
      expect(back.tempFahrenheit, isTrue);
      expect(back.pressurePsi, isTrue);
      expect(back.showIntroTips, isFalse);
      expect(back.lockOrientation, isTrue);
      expect(back.keepAwake, isTrue);
      expect(back.autoGpsRecording, isTrue);
      expect(back.autoTripResetHours, 12);
      expect(
          back.panelIndicators, [PanelIndicator.bateria, PanelIndicator.pwm]);
      expect(back.panelSize, PanelIndicatorSize.grande);
      expect(back.autoVolume, isTrue);
      expect(back.avasEnabled, isTrue);
      expect(back.avasPreset, AvasPreset.electrico);
      expect(back.avasVolume, 0.4);
      expect(back.customBeep, isTrue);
      expect(back.locationVisibility, VisibilityChoice.amigos);
      expect(back.profileVisibility, VisibilityChoice.nadie);
      expect(back.enhancedLocationPrecision, isTrue);
      expect(back.backgroundLocation, isTrue);
      expect(back.leaderboards, isFalse);
      expect(back.mapFriendsOnly, isTrue);
      expect(back.mapOnlineOnly, isTrue);
      expect(back.mapConnectedOnly, isTrue);
      expect(back.customDeviceName, 'Mi rueda');
      expect(back.demoMode, isTrue);
      expect(back.alarms[AlarmKind.velocidad]!.enabled, isFalse);
      expect(back.alarms[AlarmKind.velocidad]!.value, 42);
    });

    test('un JSON vacío o parcial cae en los valores por defecto', () {
      final back = AppSettings.fromJson(<String, dynamic>{});
      expect(back.themeChoice, AppThemeChoice.oscuro);
      expect(back.avasEnabled, isFalse);
      expect(back.panelIndicators, isNotEmpty);
      expect(back.alarms[AlarmKind.temperatura]!.value, 65);
    });
  });
}
