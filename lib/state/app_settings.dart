import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

/// Tema visual elegido en Configuración → Aplicación → Apariencia.
enum AppThemeChoice {
  oscuro('Oscuro deportivo'),
  claro('Claro'),
  sistema('Según el sistema'),
  negroPuro('Negro puro');

  const AppThemeChoice(this.label);
  final String label;
}

/// Quién puede ver un dato social (localización / perfil).
enum VisibilityChoice {
  todo('Todo'),
  amigos('Amigos'),
  nadie('Nadie');

  const VisibilityChoice(this.label);
  final String label;
}

/// Indicadores que el panel de conducción puede mostrar. El usuario
/// elige cuáles ver desde «Panel personalizado».
enum PanelIndicator {
  bateria('Batería', '%'),
  voltaje('Voltaje', 'V'),
  corriente('Corriente', 'A'),
  potencia('Potencia', 'W'),
  temperatura('Temperatura', '°C'),
  pwm('PWM', '%'),
  distanciaViaje('Distancia del viaje', 'km'),
  odometro('Odómetro total', 'km');

  const PanelIndicator(this.label, this.unit);
  final String label;
  final String unit;
}

/// Tamaño de los indicadores del panel.
enum PanelIndicatorSize {
  normal('Normal'),
  grande('Grande');

  const PanelIndicatorSize(this.label);
  final String label;
}

/// Tipos de alarma configurable sobre la telemetría en vivo.
enum AlarmKind {
  velocidad('Velocidad', 'km/h'),
  amperaje('Amperaje', 'A'),
  potencia('Potencia', 'W'),
  temperatura('Temperatura', '°C'),
  pwm('PWM', '%');

  const AlarmKind(this.label, this.unit);
  final String label;
  final String unit;
}

/// Umbral de una alarma: activada o no, y a partir de qué valor salta.
class AlarmThreshold {
  const AlarmThreshold({this.enabled = true, required this.value});

  final bool enabled;
  final double value;

  AlarmThreshold copyWith({bool? enabled, double? value}) => AlarmThreshold(
        enabled: enabled ?? this.enabled,
        value: value ?? this.value,
      );

  Map<String, dynamic> toJson() => {'on': enabled, 'v': value};

  factory AlarmThreshold.fromJson(Map<String, dynamic> json) => AlarmThreshold(
        enabled: json['on'] as bool? ?? true,
        value: (json['v'] as num?)?.toDouble() ?? 0,
      );
}

/// Presets del sonido de motor (AVAS): cada uno define su frecuencia
/// base y cómo sube el tono con la velocidad.
enum AvasPreset {
  deportivo('Deportivo', 90, 320),
  clasico('Clásico', 60, 200),
  electrico('Eléctrico', 220, 660),
  personalizado('Personalizado', 120, 400);

  const AvasPreset(this.label, this.baseHz, this.maxHz);
  final String label;

  /// Frecuencia del tono a velocidad cero / máxima, en Hz.
  final double baseHz;
  final double maxHz;
}

/// Ajustes completos de la app (base v2). Se persisten como JSON en
/// el directorio de documentos (`settings.json`) y se notifican con
/// [ChangeNotifier] para que las pantallas reaccionen al instante.
///
/// La (de)serialización es pura y testeable; el archivo solo se toca
/// en [load] y en [_persist].
class AppSettings extends ChangeNotifier {
  AppSettings();

  // — Apariencia y unidades —
  AppThemeChoice themeChoice = AppThemeChoice.oscuro;
  bool imperial = false; // millas en lugar de kilómetros
  bool tempFahrenheit = false; // °F en lugar de °C
  bool pressurePsi = false; // psi en lugar de bar
  bool showIntroTips = true; // consejos al arrancar la app

  // — Pantalla y comportamiento —
  bool lockOrientation = false;
  bool keepAwake = false;

  // — GPS y viajes —
  bool autoGpsRecording = false;
  int autoTripResetHours = 6; // 0 = nunca

  // — Panel personalizado —
  List<PanelIndicator> panelIndicators = const [
    PanelIndicator.bateria,
    PanelIndicator.voltaje,
    PanelIndicator.potencia,
    PanelIndicator.temperatura,
  ];
  PanelIndicatorSize panelSize = PanelIndicatorSize.normal;

  // — Alarmas —
  Map<AlarmKind, AlarmThreshold> alarms = {
    AlarmKind.velocidad: const AlarmThreshold(value: 30),
    AlarmKind.amperaje: const AlarmThreshold(value: 30),
    AlarmKind.potencia: const AlarmThreshold(value: 2000),
    AlarmKind.temperatura: const AlarmThreshold(value: 65),
    AlarmKind.pwm: const AlarmThreshold(value: 85),
  };

  // — Sonido —
  bool autoVolume = false; // el volumen de la música sigue a la velocidad
  bool avasEnabled = false; // sonido de motor (AVAS), apagado por defecto
  AvasPreset avasPreset = AvasPreset.deportivo;
  double avasVolume = 0.7; // 0..1
  bool customBeep = false; // beep personalizado de la app

  // — Privacidad —
  VisibilityChoice locationVisibility = VisibilityChoice.todo;
  VisibilityChoice profileVisibility = VisibilityChoice.todo;
  bool enhancedLocationPrecision = false;
  bool backgroundLocation = false;
  bool leaderboards = true;

  // — Filtros del mapa —
  bool mapFriendsOnly = false;
  bool mapOnlineOnly = false;
  bool mapConnectedOnly = false;

  // — Dispositivo —
  String? customDeviceName; // nombre personalizado de la rueda

  // — Modo demo (sin rueda real: datos de ejemplo en pantalla) —
  bool demoMode = false;

  // ----------------------------------------------------------------

  static const _fileName = 'settings.json';

  /// Carga los ajustes guardados; si no hay archivo o está dañado,
  /// devuelve los valores por defecto. Nunca lanza.
  static Future<AppSettings> load() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_fileName');
      if (!await file.exists()) return AppSettings();
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return AppSettings();
      return AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return AppSettings();
    }
  }

  /// Aplica [change], notifica a la UI y persiste en disco.
  void update(void Function(AppSettings s) change) {
    change(this);
    notifyListeners();
    _persist();
  }

  Future<void> _persist() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_fileName');
      await file.writeAsString(jsonEncode(toJson()));
    } catch (_) {
      // Si el disco falla, los ajustes siguen vivos en memoria.
    }
  }

  Map<String, dynamic> toJson() => {
        'theme': themeChoice.name,
        'imperial': imperial,
        'tempF': tempFahrenheit,
        'psi': pressurePsi,
        'introTips': showIntroTips,
        'lockOrientation': lockOrientation,
        'keepAwake': keepAwake,
        'autoGps': autoGpsRecording,
        'tripResetHours': autoTripResetHours,
        'panel': panelIndicators.map((e) => e.name).toList(),
        'panelSize': panelSize.name,
        'alarms': {
          for (final e in alarms.entries) e.key.name: e.value.toJson(),
        },
        'autoVolume': autoVolume,
        'avasOn': avasEnabled,
        'avasPreset': avasPreset.name,
        'avasVolume': avasVolume,
        'customBeep': customBeep,
        'locVis': locationVisibility.name,
        'profVis': profileVisibility.name,
        'enhancedPrecision': enhancedLocationPrecision,
        'bgLocation': backgroundLocation,
        'leaderboards': leaderboards,
        'mapFriends': mapFriendsOnly,
        'mapOnline': mapOnlineOnly,
        'mapConnected': mapConnectedOnly,
        'deviceName': customDeviceName,
        'demo': demoMode,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final s = AppSettings();
    T enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
      for (final v in values) {
        if (v.name == name) return v;
      }
      return fallback;
    }

    bool flag(String key, bool fallback) => json[key] as bool? ?? fallback;

    s.themeChoice =
        enumByName(AppThemeChoice.values, json['theme'], AppThemeChoice.oscuro);
    s.imperial = flag('imperial', false);
    s.tempFahrenheit = flag('tempF', false);
    s.pressurePsi = flag('psi', false);
    s.showIntroTips = flag('introTips', true);
    s.lockOrientation = flag('lockOrientation', false);
    s.keepAwake = flag('keepAwake', false);
    s.autoGpsRecording = flag('autoGps', false);
    s.autoTripResetHours = (json['tripResetHours'] as num?)?.toInt() ?? 6;
    final panel = json['panel'] as List<dynamic>?;
    if (panel != null && panel.isNotEmpty) {
      s.panelIndicators = [
        for (final name in panel)
          enumByName(PanelIndicator.values, name, PanelIndicator.bateria),
      ];
    }
    s.panelSize = enumByName(PanelIndicatorSize.values, json['panelSize'],
        PanelIndicatorSize.normal);
    final alarmsJson = json['alarms'] as Map<String, dynamic>?;
    if (alarmsJson != null) {
      for (final kind in AlarmKind.values) {
        final raw = alarmsJson[kind.name];
        if (raw is Map<String, dynamic>) {
          s.alarms[kind] = AlarmThreshold.fromJson(raw);
        }
      }
    }
    s.autoVolume = flag('autoVolume', false);
    s.avasEnabled = flag('avasOn', false);
    s.avasPreset =
        enumByName(AvasPreset.values, json['avasPreset'], AvasPreset.deportivo);
    s.avasVolume = (json['avasVolume'] as num?)?.toDouble() ?? 0.7;
    s.customBeep = flag('customBeep', false);
    s.locationVisibility = enumByName(
        VisibilityChoice.values, json['locVis'], VisibilityChoice.todo);
    s.profileVisibility = enumByName(
        VisibilityChoice.values, json['profVis'], VisibilityChoice.todo);
    s.enhancedLocationPrecision = flag('enhancedPrecision', false);
    s.backgroundLocation = flag('bgLocation', false);
    s.leaderboards = flag('leaderboards', true);
    s.mapFriendsOnly = flag('mapFriends', false);
    s.mapOnlineOnly = flag('mapOnline', false);
    s.mapConnectedOnly = flag('mapConnected', false);
    s.customDeviceName = json['deviceName'] as String?;
    s.demoMode = flag('demo', false);
    return s;
  }
}

/// Acceso a los ajustes desde cualquier pantalla del árbol.
class AppSettingsScope extends InheritedNotifier<AppSettings> {
  const AppSettingsScope({
    super.key,
    required AppSettings settings,
    required super.child,
  }) : super(notifier: settings);

  static AppSettings of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<AppSettingsScope>();
    assert(scope != null, 'AppSettingsScope no encontrado en el árbol');
    return scope!.notifier!;
  }
}
