import 'package:flutter/material.dart';

import '../models/wheel_identity.dart';
import '../services/app_log.dart';
import '../services/ble/wheel_command.dart';
import '../services/ble/wheel_connection_controller.dart';
import '../theme.dart';
import 'ui_kit.dart';

/// Tarjeta de **controles de la rueda** (pestaña Dispositivos, con
/// la rueda conectada): muestra SOLO los controles que el adaptador
/// de la marca detectada tiene implementados y verificados, y manda
/// cada comando por la compuerta de seguridad vía el controlador.
///
/// Reglas de interacción:
/// - Luz, LED y volumen (moderados): el toque ES la confirmación.
/// - Beep (bajo): sin confirmación.
/// - Críticos (pedales, velocidad máxima, alarmas, bloqueo,
///   transporte, calibración, apagado): diálogo de confirmación
///   explícita; la compuerta además exige velocidad 0 y telemetría
///   fresca, y bloquea en movimiento sin excepción.
class WheelControlsCard extends StatefulWidget {
  const WheelControlsCard({super.key, required this.controller});

  final WheelConnectionController controller;

  @override
  State<WheelControlsCard> createState() => _WheelControlsCardState();
}

class _WheelControlsCardState extends State<WheelControlsCard> {
  int _tiltBackKmh = 25;
  final List<int> _alarmKmh = [15, 20, 25];
  int _ledMode = 0;
  int _volume = 5;

  WheelConnectionController get _c => widget.controller;

  Future<void> _dispatch(
    WheelCommandRequest request, {
    required bool userConfirmed,
  }) async {
    final verdict = await _c.sendCommand(request, userConfirmed: userConfirmed);
    AppLog.instance.add(verdict.allowed
        ? 'Control enviado: ${request.command.name}'
        : 'Control bloqueado: ${verdict.reason}');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(verdict.allowed
            ? 'Comando enviado a la rueda.'
            : (verdict.reason ?? 'El comando fue bloqueado.')),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Diálogo de confirmación para comandos críticos: sin el «Sí»
  /// explícito del usuario no sale nada hacia la rueda.
  Future<void> _confirmCritical(
    WheelCommandRequest request, {
    required String title,
    required String body,
    String confirmLabel = 'Confirmar',
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _dispatch(request, userConfirmed: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final adapter = _c.adapter;
    if (adapter == null) return const SizedBox.shrink();
    final caps = adapter.capabilities;
    final brand = adapter.brand;
    final moving = _c.telemetry.isMoving;
    // Familia nueva InMotion: máxima y alarma viajan en una sola
    // trama; la tarjeta muestra una sección conjunta en vez de
    // dos editores separados (mandar la alarma sin la máxima la
    // borraría). El tope es el de fábrica cuando está verificado.
    final combinedMaxAlarm =
        brand == WheelBrand.inmotionV2 && adapter.usesCombinedMaxAlarm;
    final factoryCap = adapter.factoryMaxKmh;
    // Encabezado con el modelo real cuando se conoce (p. ej.
    // «Inmotion V9»), no solo la familia del protocolo («InMotion
    // V2»): la familia es el adaptador, el modelo es la rueda.
    final modelLabel =
        _c.telemetry.model ?? _c.identity.model ?? brand.label;

    final unavailable = <String>[
      if (!caps.lights) 'luz',
      if (!caps.beep) 'beep',
      if (!caps.pedalMode) 'modo de pedales',
      if (!caps.tiltBack) 'velocidad máxima (tilt-back)',
      if (!caps.speedAlarms) 'alarmas de velocidad',
      if (!caps.motorLock) 'bloqueo de motor',
      if (!caps.calibration) 'calibración',
      if (!caps.powerOff) 'apagado remoto',
      if (!caps.led) 'modo LED',
      if (!caps.volume) 'volumen',
      if (!caps.transportMode) 'modo transporte',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Controles de la rueda'),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                modelLabel,
                style: const TextStyle(
                  color: funcBlue,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
              if (moving) ...[
                const SizedBox(height: 8),
                const Text(
                  'La rueda está en movimiento: los ajustes críticos '
                  'están bloqueados por seguridad.',
                  style: TextStyle(color: Colors.amber, fontSize: 13),
                ),
              ],
              if (caps.lights) ...[
                const SizedBox(height: 12),
                _label('Luz'),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    _actionChip('Apagada', () => _dispatch(
                        const LightRequest(LightState.off),
                        userConfirmed: true)),
                    _actionChip('Encendida', () => _dispatch(
                        const LightRequest(LightState.on),
                        userConfirmed: true)),
                    if (brand == WheelBrand.kingsong ||
                        brand == WheelBrand.begode)
                      _actionChip('Estrobo', () => _dispatch(
                          const LightRequest(LightState.strobe),
                          userConfirmed: true)),
                  ],
                ),
              ],
              if (caps.beep) ...[
                const SizedBox(height: 12),
                _actionButton(
                  'Beep / claxon de prueba',
                  Icons.campaign_outlined,
                  () => _dispatch(const BeepRequest(), userConfirmed: false),
                ),
              ],
              if (caps.pedalMode) ...[
                const SizedBox(height: 14),
                _label('Modo de pedales'),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    for (var m = 0; m < 3; m++)
                      _actionChip(
                        const ['Duro', 'Medio', 'Suave'][m],
                        () => _confirmCritical(
                          PedalModeRequest(m),
                          title: 'Cambiar el modo de pedales',
                          body: 'La rueda debe estar totalmente detenida. '
                              'El nuevo modo cambia cómo responden los '
                              'pedales al rodar.',
                        ),
                      ),
                  ],
                ),
              ],
              if (caps.tiltBack &&
                  brand != WheelBrand.kingsong &&
                  !combinedMaxAlarm) ...[
                const SizedBox(height: 14),
                _label('Velocidad máxima (tilt-back)'),
                _stepperRow(
                  value: _tiltBackKmh,
                  suffix: 'km/h',
                  max: factoryCap ?? 99,
                  onChanged: (v) => setState(() => _tiltBackKmh = v),
                  onApply: () => _confirmCritical(
                    TiltBackRequest(_tiltBackKmh),
                    title: 'Cambiar la velocidad máxima',
                    body: 'La rueda debe estar totalmente detenida. '
                        'El tilt-back nuevo será $_tiltBackKmh km/h.',
                  ),
                ),
              ],
              if (combinedMaxAlarm) ...[
                const SizedBox(height: 14),
                _label('Velocidad máxima y alarma'),
                if (factoryCap != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Límite de fábrica: $factoryCap km/h. La alarma '
                    'viaja junto con la máxima en un solo comando.',
                    style: const TextStyle(color: subText, fontSize: 13),
                  ),
                ],
                const SizedBox(height: 6),
                _label('Máxima'),
                _stepperRow(
                  value: _tiltBackKmh,
                  suffix: 'km/h',
                  max: factoryCap ?? 99,
                  onChanged: (v) => setState(() {
                    _tiltBackKmh = v;
                    if (_alarmKmh[0] > v) _alarmKmh[0] = v;
                  }),
                ),
                _label('Alarma'),
                _stepperRow(
                  value: _alarmKmh[0],
                  suffix: 'km/h',
                  max: _tiltBackKmh,
                  onChanged: (v) => setState(() => _alarmKmh[0] = v),
                ),
                _applyButton(() => _confirmCritical(
                      SpeedAlarmsRequest(
                        [_alarmKmh[0]],
                        tiltBackKmh: _tiltBackKmh,
                      ),
                      title: 'Cambiar la velocidad máxima y la alarma',
                      body: 'La rueda debe estar totalmente detenida. '
                          'La máxima será $_tiltBackKmh km/h y la '
                          'alarma ${_alarmKmh[0]} km/h.',
                    )),
              ],
              if (brand == WheelBrand.kingsong &&
                  (caps.speedAlarms || caps.tiltBack)) ...[
                const SizedBox(height: 14),
                _label('Alarmas y velocidad máxima'),
                const SizedBox(height: 6),
                _actionButton(
                  'Editar alarmas y máxima…',
                  Icons.speed,
                  _showKingSongSpeedEditor,
                ),
              ],
              if (caps.speedAlarms && brand == WheelBrand.begode) ...[
                const SizedBox(height: 14),
                _label('Alarmas de velocidad (modo)'),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    for (var m = 0; m < 3; m++)
                      _actionChip(
                        const ['Dos', 'Una', 'Apagadas'][m],
                        () => _confirmCritical(
                          AlarmModeRequest(m),
                          title: 'Cambiar las alarmas',
                          body: 'La rueda debe estar totalmente detenida. '
                              'Apagar las alarmas elimina los avisos de '
                              'velocidad de la propia rueda.',
                        ),
                      ),
                  ],
                ),
              ],
              if (caps.speedAlarms &&
                  ((brand == WheelBrand.inmotionV2 && !combinedMaxAlarm) ||
                      brand == WheelBrand.ninebotZ)) ...[
                const SizedBox(height: 14),
                _label(brand == WheelBrand.ninebotZ
                    ? 'Alarmas de velocidad (1ª, 2ª y 3ª)'
                    : 'Alarmas de velocidad (baja y alta)'),
                for (var i = 0;
                    i < (brand == WheelBrand.ninebotZ ? 3 : 2);
                    i++) ...[
                  _stepperRow(
                    value: _alarmKmh[i],
                    suffix: 'km/h',
                    onChanged: (v) => setState(() => _alarmKmh[i] = v),
                  ),
                ],
                _applyButton(() => _confirmCritical(
                      SpeedAlarmsRequest(
                        brand == WheelBrand.ninebotZ
                            ? List.of(_alarmKmh)
                            : _alarmKmh.sublist(0, 2),
                      ),
                      title: 'Cambiar las alarmas de velocidad',
                      body: 'La rueda debe estar totalmente detenida.',
                    )),
              ],
              if (caps.led) ...[
                const SizedBox(height: 14),
                _label('Modo LED'),
                _stepperRow(
                  value: _ledMode,
                  min: 0,
                  max: 9,
                  onChanged: (v) => setState(() => _ledMode = v),
                  onApply: () => _dispatch(LedModeRequest(_ledMode),
                      userConfirmed: true),
                ),
              ],
              if (caps.volume) ...[
                const SizedBox(height: 14),
                _label('Volumen del beeper'),
                _stepperRow(
                  value: _volume,
                  min: 0,
                  max: 9,
                  onChanged: (v) => setState(() => _volume = v),
                  onApply: () => _dispatch(VolumeRequest(_volume),
                      userConfirmed: true),
                ),
              ],
              if (caps.motorLock) ...[
                const SizedBox(height: 14),
                _label('Bloqueo de motor (antirrobo)'),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    _actionChip(
                      'Bloquear',
                      () => _confirmCritical(
                        const MotorLockRequest(true),
                        title: 'Bloquear el motor',
                        body: 'La rueda debe estar totalmente detenida. '
                            'Con el motor bloqueado la rueda no puede '
                            'rodar hasta desbloquearla desde la app.',
                        confirmLabel: 'Bloquear',
                      ),
                    ),
                    _actionChip(
                      'Desbloquear',
                      () => _confirmCritical(
                        const MotorLockRequest(false),
                        title: 'Desbloquear el motor',
                        body: 'La rueda volverá a poder rodar.',
                        confirmLabel: 'Desbloquear',
                      ),
                    ),
                  ],
                ),
              ],
              if (caps.transportMode) ...[
                const SizedBox(height: 14),
                _label('Modo transporte'),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    _actionChip(
                      'Activar',
                      () => _confirmCritical(
                        const TransportModeRequest(true),
                        title: 'Activar el modo transporte',
                        body: 'La rueda debe estar totalmente detenida.',
                      ),
                    ),
                    _actionChip(
                      'Desactivar',
                      () => _dispatch(const TransportModeRequest(false),
                          userConfirmed: true),
                    ),
                  ],
                ),
              ],
              if (caps.calibration) ...[
                const SizedBox(height: 14),
                _actionButton(
                  'Calibrar la rueda…',
                  Icons.straighten,
                  () => _confirmCritical(
                    const CalibrationRequest(),
                    title: 'Calibrar la rueda',
                    body: 'Deja la rueda detenida, nivelada y apoyada, '
                        'sin peso encima. La calibración ajusta su '
                        'referencia de horizontal.',
                    confirmLabel: 'Calibrar',
                  ),
                ),
              ],
              if (caps.powerOff) ...[
                const SizedBox(height: 10),
                _actionButton(
                  'Apagar la rueda…',
                  Icons.power_settings_new,
                  () => _confirmCritical(
                    const PowerOffRequest(),
                    title: 'Apagar la rueda',
                    body: 'La rueda debe estar totalmente detenida. '
                        'Se apagará por completo.',
                    confirmLabel: 'Apagar',
                  ),
                  danger: true,
                ),
              ],
              if (unavailable.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  'Todavía no disponibles en esta marca: '
                  '${unavailable.join(', ')}.',
                  style: const TextStyle(color: subText, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Editor combinado de KingSong: su trama de ajustes lleva las
  /// tres alarmas Y la velocidad máxima juntas (si se manda solo
  /// una parte, se borraría la otra).
  Future<void> _showKingSongSpeedEditor() async {
    final alarms = List<int>.of(_alarmKmh);
    var maxKmh = _tiltBackKmh;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Alarmas y velocidad máxima'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'En KingSong estos valores viajan juntos en una sola '
                'trama: lo que pongas aquí reemplaza los cuatro '
                'valores actuales de la rueda.',
                style: TextStyle(fontSize: 13),
              ),
              for (var i = 0; i < 3; i++)
                _stepperRow(
                  value: alarms[i],
                  suffix: 'km/h · alarma ${i + 1}',
                  onChanged: (v) => setLocal(() => alarms[i] = v),
                ),
              _stepperRow(
                value: maxKmh,
                suffix: 'km/h · máxima',
                onChanged: (v) => setLocal(() => maxKmh = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Aplicar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    setState(() {
      _alarmKmh.setAll(0, alarms);
      _tiltBackKmh = maxKmh;
    });
    await _confirmCritical(
      SpeedAlarmsRequest(alarms, tiltBackKmh: maxKmh),
      title: 'Aplicar los valores',
      body: 'La rueda debe estar totalmente detenida. Se enviarán '
          'las alarmas $alarms km/h y la máxima de $maxKmh km/h.',
    );
  }

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
      );

  Widget _actionChip(String label, VoidCallback onTap) => ActionChip(
        label: Text(label),
        onPressed: onTap,
      );

  Widget _actionButton(
    String label,
    IconData icon,
    VoidCallback onTap, {
    bool danger = false,
  }) =>
      OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: danger
            ? OutlinedButton.styleFrom(foregroundColor: Colors.redAccent)
            : null,
      );

  Widget _applyButton(VoidCallback onTap) => Align(
        alignment: Alignment.centerRight,
        child: FilledButton(onPressed: onTap, child: const Text('Aplicar')),
      );

  /// Fila «− valor sufijo +» con botón Aplicar opcional.
  Widget _stepperRow({
    required int value,
    String? suffix,
    int min = 0,
    int max = 99,
    required ValueChanged<int> onChanged,
    VoidCallback? onApply,
  }) {
    return Row(
      children: [
        IconButton(
          onPressed: value > min ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove_circle_outline),
        ),
        Expanded(
          child: Text(
            suffix == null ? '$value' : '$value $suffix',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
        ),
        IconButton(
          onPressed: value < max ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add_circle_outline),
        ),
        if (onApply != null) ...[
          const SizedBox(width: 4),
          FilledButton(onPressed: onApply, child: const Text('Aplicar')),
        ],
      ],
    );
  }
}
