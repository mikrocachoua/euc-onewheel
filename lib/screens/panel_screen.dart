import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/wheel_capabilities.dart';
import '../models/wheel_identity.dart';
import '../models/wheel_telemetry.dart';
import '../services/alarm_engine.dart';
import '../services/app_log.dart';
import '../services/avas_engine.dart';
import '../services/avas_tone_backend.dart';
import '../services/ble/wheel_connection_controller.dart';
import '../services/demo_data.dart';
import '../state/app_settings.dart';
import '../theme.dart';
import '../utils/units.dart';
import '../widgets/speed_gauge.dart';
import '../widgets/ui_kit.dart';
import '../widgets/wheel_controls_card.dart';

/// Panel de conducción de EUC OneWheel (base v2): medidor circular
/// grande de velocidad, indicadores personalizables (batería,
/// voltaje, corriente, potencia, temperatura, PWM, distancias),
/// avisos de alarmas configurables y los controles de la rueda.
///
/// La telemetría puede venir de tres fuentes, en este orden:
/// 1. Una rueda real conectada por Bluetooth (su adaptador de marca).
/// 2. El modo demo (valores simulados, genéricos).
/// 3. Nada: vista «Sin rueda conectada» con el medidor preparado.
///
/// Los controles de la rueda solo se habilitan cuando el adaptador
/// de la marca conectada implementa el comando Y la compuerta de
/// seguridad lo autoriza (rueda detenida + confirmación explícita).
/// Con rueda conectada el panel muestra la tarjeta de controles
/// reales; sin rueda o en modo demo muestra la explicación
/// correspondiente.
class PanelScreen extends StatefulWidget {
  const PanelScreen({
    super.key,
    this.controller,
    this.settings,
    this.bottomPadding = 24,
  });

  final WheelConnectionController? controller;
  final AppSettings? settings;

  /// Espacio inferior del contenido (al ir sobre la barra flotante
  /// se pasa `tabBarClearance`; como página independiente, 24).
  final double bottomPadding;

  @override
  State<PanelScreen> createState() => _PanelScreenState();
}

class _PanelScreenState extends State<PanelScreen> {
  late final AppSettings _fallback = AppSettings();
  AppSettings get _settings => widget.settings ?? _fallback;

  final DemoTelemetry _demo = DemoTelemetry();
  StreamSubscription<WheelTelemetry>? _demoSub;
  WheelTelemetry? _demoTelemetry;
  final AvasAudioBackend _avasBackend = AvasToneBackend();
  Set<AlarmKind> _soundedAlarms = {};

  @override
  void initState() {
    super.initState();
    _syncDemo();
  }

  @override
  void didUpdateWidget(PanelScreen old) {
    super.didUpdateWidget(old);
    _syncDemo();
  }

  @override
  void dispose() {
    _demoSub?.cancel();
    _demo.dispose();
    _avasBackend.stop();
    super.dispose();
  }

  void _syncDemo() {
    final wantDemo = _settings.demoMode;
    if (wantDemo && _demoSub == null) {
      _demoSub = _demo.stream.listen((t) {
        if (mounted) setState(() => _demoTelemetry = t);
      });
      _demo.start();
    } else if (!wantDemo && _demoSub != null) {
      _demoSub?.cancel();
      _demoSub = null;
      _demo.stop();
      _demoTelemetry = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    return ListenableBuilder(
      listenable: Listenable.merge([if (ctrl != null) ctrl, _settings]),
      builder: (context, _) {
        _syncDemo();
        final connectedLive = ctrl != null &&
                ctrl.state == WheelLinkState.connected &&
                ctrl.adapter != null
            ? ctrl.telemetry
            : null;
        if (connectedLive != null) {
          return _content(context, connectedLive, demo: false);
        }
        if (_settings.demoMode) {
          return _content(context, _demoTelemetry, demo: true);
        }
        return _content(context, null, demo: false);
      },
    );
  }

  Widget _content(BuildContext context, WheelTelemetry? live,
      {required bool demo}) {
    final settings = _settings;
    final alarms = live == null
        ? const <ActiveAlarm>[]
        : evaluateAlarms(live, settings.alarms);
    _reactToAlarms(alarms, live, demo);
    final speedDisplay = live == null
        ? 0.0
        : displaySpeed(live.speedKmh, imperial: settings.imperial);

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, 12, 16, widget.bottomPadding),
        children: [
          _header(context, demo),
          const SizedBox(height: 14),
          _wheelCard(live, demo),
          if (alarms.isNotEmpty) ...[
            const SizedBox(height: 12),
            _alarmBanner(alarms),
          ],
          const SizedBox(height: 18),
          Center(
            child: SpeedGauge(
              speed: speedDisplay,
              unitLabel: speedUnit(imperial: settings.imperial),
              size: settings.panelSize == PanelIndicatorSize.grande ? 264 : 238,
              alarm: alarms.isNotEmpty,
            ),
          ),
          const SizedBox(height: 18),
          _indicatorsGrid(live),
          const SizedBox(height: 16),
          _controlsSection(live, demo),
          const SizedBox(height: 12),
          _modeNote(live, demo),
        ],
      ),
    );
  }

  /// Reacciones a las alarmas: un aviso sonoro breve al dispararse
  /// una alarma nueva y el «ducking» del sonido de motor (AVAS) para
  /// que nunca tape a las alarmas reales.
  void _reactToAlarms(
      List<ActiveAlarm> alarms, WheelTelemetry? live, bool demo) {
    final kinds = alarms.map((a) => a.kind).toSet();
    final fresh = kinds.difference(_soundedAlarms);
    if (fresh.isNotEmpty && live != null) {
      SystemSound.play(SystemSoundType.alert);
      AppLog.instance.add(
          'Alarma en el panel: ${alarms.map((a) => a.kind.label).join(', ')}');
    }
    _soundedAlarms = kinds;
    final output = computeAvas(
      enabled: _settings.avasEnabled,
      connected: live != null,
      speedKmh: live?.speedKmh ?? 0,
      alarmActive: alarms.isNotEmpty,
      preset: _settings.avasPreset,
      volume: _settings.avasVolume,
    );
    _avasBackend.apply(output, preset: _settings.avasPreset);
  }

  Widget _header(BuildContext context, bool demo) {
    // El panel se abre como página empujada desde Dispositivos:
    // sin botón de regreso visible no había forma de volver
    // (reportado en la V9, build #8). Solo aparece cuando la ruta
    // puede cerrarse; como raíz no se muestra.
    final canPop = Navigator.of(context).canPop();
    return Row(
      children: [
        if (canPop) ...[
          CircleIconButton(
            icon: Icons.arrow_back_ios_new,
            tooltip: 'Volver',
            onTap: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 12),
        ],
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.asset('assets/logo.jpg',
              width: 52, height: 52, fit: BoxFit.cover),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('EUC OneWheel',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.onSurface,
                  )),
              Text('Panel de conducción',
                  style: TextStyle(color: subText, fontSize: 13)),
            ],
          ),
        ),
        if (demo) const PillBadge('Demo', color: safetyAmber),
      ],
    );
  }

  Widget _wheelCard(WheelTelemetry? live, bool demo) {
    if (live == null) {
      return SurfaceCard(
        glassBlur: true,
        child: Row(
          children: [
            const GlassIconTile(icon: Icons.bluetooth_disabled),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Sin rueda conectada',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  SizedBox(height: 4),
                  Text(
                    'Conecta tu rueda por Bluetooth en la pestaña '
                    'Dispositivos: la app detecta automáticamente su '
                    'marca y modelo, sea InMotion, KingSong, '
                    'Begode/Gotway, Veteran/LeaperKim o Ninebot, y este '
                    'panel mostrará su telemetría en vivo.',
                    style: TextStyle(color: subText, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    final ctrl = widget.controller;
    final identity = ctrl?.identity;
    final customName = _settings.customDeviceName;
    final title = demo
        ? (customName ?? 'Rueda de demostración')
        : (customName ??
            live.model ??
            identity?.model ??
            (identity != null && identity.brand != WheelBrand.unknown
                ? identity.brand.label
                : 'Rueda conectada'));
    return SurfaceCard(
      glassBlur: true,
      child: Row(
        children: [
          const GlassIconTile(icon: Icons.bluetooth_connected),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  demo
                      ? 'Modo demo: valores simulados para explorar la app'
                      : 'Conectada por Bluetooth · telemetría en vivo',
                  style: const TextStyle(color: subText, fontSize: 13),
                ),
              ],
            ),
          ),
          if (live.batteryPct != null)
            RingIndicator(
              fraction: live.batteryPct! / 100,
              centerText: '${live.batteryPct}%',
              size: 54,
              color: live.batteryPct! <= 20 ? brandRed : evCyan,
            ),
        ],
      ),
    );
  }

  Widget _alarmBanner(List<ActiveAlarm> alarms) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [brandRedDeep, brandRed],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: brandRedLight.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: brandRed.withValues(alpha: 0.4),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: Colors.white, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              alarms.map((a) => a.message).join(' · '),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _indicatorsGrid(WheelTelemetry? live) {
    final settings = _settings;
    final large = settings.panelSize == PanelIndicatorSize.grande;
    final indicators = settings.panelIndicators;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: large ? 1.55 : 1.85,
      ),
      itemCount: indicators.length,
      itemBuilder: (context, i) => _indicatorCard(indicators[i], live, large),
    );
  }

  /// Color de acento por indicador: el cian «energía EV» solo para
  /// los datos de energía (batería, voltaje, corriente, potencia);
  /// el resto, gris plata sobrio. El rojo vive solo dentro del tubo
  /// del velocímetro y en las alertas críticas.
  Color _indicatorColor(PanelIndicator indicator) => switch (indicator) {
        PanelIndicator.bateria ||
        PanelIndicator.voltaje ||
        PanelIndicator.corriente ||
        PanelIndicator.potencia =>
          evCyan,
        _ => subText,
      };

  Widget _indicatorCard(
      PanelIndicator indicator, WheelTelemetry? live, bool large) {
    final settings = _settings;
    final (icon, value, sub) = _indicatorData(indicator, live, settings);
    return SurfaceCard(
      padding: const EdgeInsets.all(14),
      // FittedBox a la baja: si una cifra larga o una fuente grande
      // no cabe en la celda, se reduce un punto en vez de desbordar.
      // (Sin hijos flex dentro: FittedBox da ancho sin cota y un
      // Expanded ahí rompería el layout.)
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: _indicatorColor(indicator)),
                const SizedBox(width: 6),
                Text(
                  indicator.label,
                  style: const TextStyle(color: subText, fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: large ? 30 : 25,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (sub != null)
              Text(sub, style: const TextStyle(color: subText, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  (IconData, String, String?) _indicatorData(
      PanelIndicator indicator, WheelTelemetry? live, AppSettings s) {
    if (live == null) return (_iconFor(indicator), '—', null);
    return switch (indicator) {
      PanelIndicator.bateria => (
          Icons.battery_full,
          live.batteryPct != null ? '${live.batteryPct} %' : '—',
          null
        ),
      PanelIndicator.voltaje => (
          Icons.electric_bolt,
          '${live.voltageV.toStringAsFixed(1)} V',
          null
        ),
      PanelIndicator.corriente => (
          Icons.bolt,
          '${live.currentA.toStringAsFixed(1)} A',
          null
        ),
      PanelIndicator.potencia => (
          Icons.power,
          '${live.powerW.round()} W',
          null
        ),
      PanelIndicator.temperatura => (
          Icons.thermostat,
          '${displayTemp(live.tempC, fahrenheit: s.tempFahrenheit).toStringAsFixed(0)} ${tempUnit(fahrenheit: s.tempFahrenheit)}',
          live.temp2C != null
              ? 'Motor: ${displayTemp(live.temp2C!, fahrenheit: s.tempFahrenheit).toStringAsFixed(0)} ${tempUnit(fahrenheit: s.tempFahrenheit)}'
              : null
        ),
      PanelIndicator.pwm => (
          Icons.waves,
          live.pwmPct != null ? '${live.pwmPct!.toStringAsFixed(0)} %' : '—',
          live.pwmPct == null ? 'No reportado por esta rueda' : null
        ),
      PanelIndicator.distanciaViaje => (
          Icons.route,
          '${displayDistanceKm(live.distanceM / 1000, imperial: s.imperial).toStringAsFixed(2)} ${distanceUnit(imperial: s.imperial)}',
          null
        ),
      PanelIndicator.odometro => (
          Icons.pin_outlined,
          '${displayDistanceKm(live.totalDistanceM / 1000, imperial: s.imperial).toStringAsFixed(1)} ${distanceUnit(imperial: s.imperial)}',
          null
        ),
    };
  }

  IconData _iconFor(PanelIndicator indicator) => switch (indicator) {
        PanelIndicator.bateria => Icons.battery_full,
        PanelIndicator.voltaje => Icons.electric_bolt,
        PanelIndicator.corriente => Icons.bolt,
        PanelIndicator.potencia => Icons.power,
        PanelIndicator.temperatura => Icons.thermostat,
        PanelIndicator.pwm => Icons.waves,
        PanelIndicator.distanciaViaje => Icons.route,
        PanelIndicator.odometro => Icons.pin_outlined,
      };

  /// Controles de la rueda: con rueda conectada se muestra la
  /// tarjeta de controles reales; sin rueda o en modo demo, la
  /// explicación correspondiente. Cada comando pasa por la
  /// compuerta de seguridad en el momento de usarlo.
  Widget _controlsSection(WheelTelemetry? live, bool demo) {
    final ctrl = widget.controller;
    // Con rueda real conectada y telemetría en vivo, el panel usa
    // la tarjeta de controles reales (la misma de Dispositivos).
    // La sección anterior era un marcador: sus botones no mandaban
    // nada (los deslizadores tenían manejadores vacíos, Calibrar y
    // Apagar siempre deshabilitados) y su texto decía que ningún
    // comando estaba implementado aunque el adaptador sí los
    // implementa (V9, build #9: la tarjeta mostraba ese texto con
    // la rueda conectada y telemetría en vivo).
    if (!demo && live != null && ctrl != null) {
      return WheelControlsCard(controller: ctrl);
    }
    final capabilities = demo
        ? WheelCapabilities.none
        : (ctrl?.adapter?.capabilities ?? WheelCapabilities.none);
    final explanation = demo
        ? 'En modo demo los controles están inactivos: no hay una '
            'rueda real a la que enviar comandos.'
        : live == null
            ? 'Conecta tu rueda para ver sus controles. Cada marca y '
                'modelo expone comandos distintos; solo se activan los '
                'que su adaptador ya implementa.'
            : 'Los comandos de esta marca aún no están implementados '
                'en su adaptador: por seguridad, ningún control envía '
                'nada a la rueda todavía.';
    return SurfaceCard(
      glassBlur: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.tune, color: funcBlue, size: 21),
              SizedBox(width: 8),
              Expanded(
                child: Text('Controles de la rueda',
                    style:
                        TextStyle(fontWeight: FontWeight.w800, fontSize: 16.5)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(explanation,
              style: const TextStyle(color: subText, fontSize: 13)),
          const Divider(height: 26),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.lightbulb_outline),
            title: const Text('Luces'),
            subtitle: const Text('Encender / apagar'),
            value: false,
            onChanged: capabilities.lights ? (_) {} : null,
          ),
          _disabledSlider(
            icon: Icons.speed,
            title: 'Velocidad de tilt-back',
            valueLabel: '25 km/h',
            enabled: capabilities.tiltBack,
            critical: true,
          ),
          _disabledSlider(
            icon: Icons.notifications_active_outlined,
            title: 'Alarma de velocidad de la rueda',
            valueLabel: '30 km/h',
            enabled: capabilities.speedAlarms,
            critical: true,
          ),
          const SizedBox(height: 6),
          const Row(
            children: [
              Icon(Icons.pedal_bike, color: subText),
              SizedBox(width: 12),
              Text('Modo de pedales',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'suave', label: Text('Suave')),
              ButtonSegment(value: 'medio', label: Text('Medio')),
              ButtonSegment(value: 'duro', label: Text('Duro')),
            ],
            selected: const {'medio'},
            onSelectionChanged: capabilities.pedalMode ? (_) {} : null,
          ),
          _safetyLegend(capabilities.pedalMode),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.compass_calibration_outlined),
            title: const Text('Calibración'),
            subtitle: const Text('Nivelar los pedales de la rueda'),
            trailing: const OutlinedButton(
              onPressed: null,
              child: Text('Calibrar'),
            ),
          ),
          _safetyLegend(capabilities.calibration),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.lock_outline),
            title: const Text('Bloqueo del motor'),
            subtitle: const Text('Bloqueo antirrobo de la rueda'),
            value: false,
            onChanged: capabilities.motorLock ? (_) {} : null,
          ),
          _safetyLegend(capabilities.motorLock),
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.power_settings_new),
            title: Text('Apagar la rueda'),
            subtitle: Text('Apagado remoto del equipo'),
            trailing: OutlinedButton(
              onPressed: null,
              child: Text('Apagar'),
            ),
          ),
          _safetyLegend(capabilities.powerOff),
        ],
      ),
    );
  }

  Widget _disabledSlider({
    required IconData icon,
    required String title,
    required String valueLabel,
    required bool enabled,
    required bool critical,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: subText),
            const SizedBox(width: 12),
            Expanded(
              child: Text(title,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            Text(valueLabel, style: const TextStyle(color: subText)),
          ],
        ),
        Slider(value: 0.45, onChanged: enabled ? (_) {} : null),
        if (critical) _safetyLegend(enabled),
      ],
    );
  }

  /// Leyenda de la regla de seguridad para los comandos críticos:
  /// siempre en ámbar, el color de seguridad de la identidad.
  Widget _safetyLegend(bool enabled) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final amber = dark ? safetyAmber : const Color(0xFFD97E06);
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Row(
        children: [
          Icon(Icons.shield_outlined, size: 13, color: amber),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              'Solo con la rueda detenida y tu confirmación '
              '(compuerta de seguridad)',
              style: TextStyle(
                color: amber,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeNote(WheelTelemetry? live, bool demo) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: dark ? iconTileGradient() : null,
        color: dark ? null : const Color(0xFFEAF1FA),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: dark
              ? Colors.white.withValues(alpha: 0.10)
              : const Color(0xFFD3E0F2),
        ),
      ),
      child: Row(
        children: [
          Icon(
            live == null
                ? Icons.gps_fixed
                : (demo ? Icons.science_outlined : Icons.bluetooth_connected),
            color: funcBlue,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              live == null
                  ? 'El GPS de la pestaña Viajes ya graba rodadas reales. '
                      'Activa el modo demo en Configuración → Aplicación '
                      'para explorar este panel con datos simulados.'
                  : demo
                      ? 'Estás viendo datos simulados del modo demo. '
                          'Conecta tu rueda en Dispositivos para ver su '
                          'telemetría real.'
                      : 'Telemetría real de tu rueda por Bluetooth. El GPS '
                          'de la pestaña Viajes sigue grabando tus rodadas.',
              style: TextStyle(
                fontSize: 13,
                color: dark ? inkText : const Color(0xFF2A3242),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
