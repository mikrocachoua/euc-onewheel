import 'package:flutter/material.dart';

import '../theme.dart';

/// Pestaña Rueda: marcas compatibles con EUC OneWheel, los controles de
/// la rueda (diseño definitivo, habilitados en la fase 2) y la
/// información de la app. La app es abierta a las principales marcas:
/// en la fase 2 el Bluetooth detectará automáticamente marca y modelo
/// de la rueda que se conecte y podrá operarla (protocolos InMotion,
/// KingSong, Begode/Gotway, Veteran/LeaperKim y Ninebot).
class WheelScreen extends StatelessWidget {
  const WheelScreen({super.key});

  static const _brands = [
    (Icons.electric_bolt, 'InMotion'),
    (Icons.speed, 'KingSong'),
    (Icons.bolt, 'Begode (Gotway)'),
    (Icons.shield_outlined, 'Veteran (LeaperKim)'),
    (Icons.electric_scooter, 'Ninebot'),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Marcas compatibles',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text(
            'EUC OneWheel es abierta: no está amarrada a una sola marca '
            'ni a un solo modelo.',
            style: TextStyle(color: Colors.white60, fontSize: 13.5),
          ),
          const SizedBox(height: 16),
          _brandsCard(),
          const SizedBox(height: 16),
          _controlsCard(),
          const SizedBox(height: 16),
          _phase2Card(),
          const SizedBox(height: 16),
          _aboutCard(),
        ],
      ),
    );
  }

  Widget _brandsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            for (final (icon, name) in _brands)
              ListTile(
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: brandRed.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: brandRed),
                ),
                title: Text(
                  name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: const Text(
                  'Soporte Bluetooth en la fase 2',
                  style: TextStyle(color: Colors.white54, fontSize: 12.5),
                ),
                trailing: const Icon(
                  Icons.bluetooth_disabled,
                  size: 18,
                  color: Colors.white38,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Controles típicos de la rueda con su diseño definitivo, pero
  /// deshabilitados: se activan en la fase 2 al conectar una rueda, y
  /// cada uno dependerá de lo que el protocolo de la marca permita.
  Widget _controlsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.tune, color: brandRed, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Controles de la rueda',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    border: Border.all(color: brandRed),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'FASE 2',
                    style: TextStyle(
                      color: brandRed,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Disponible en la fase 2, al conectar una rueda. Los '
              'controles que se activen dependerán de lo que el protocolo '
              'de cada marca y modelo permita.',
              style: TextStyle(color: Colors.white54, fontSize: 12.5),
            ),
            const Divider(height: 26),
            const SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: Icon(Icons.lightbulb_outline),
              title: Text('Luces'),
              subtitle: Text('Encender / apagar'),
              value: false,
              onChanged: null,
            ),
            _sliderControl(
              icon: Icons.speed,
              title: 'Velocidad de tilt-back',
              valueLabel: '25 km/h',
              value: 0.45,
            ),
            _safetyLegend(),
            _sliderControl(
              icon: Icons.notifications_active_outlined,
              title: 'Alarma de velocidad',
              valueLabel: '30 km/h',
              value: 0.55,
            ),
            _safetyLegend(),
            const SizedBox(height: 4),
            const Row(
              children: [
                Icon(Icons.pedal_bike, color: Colors.white54),
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
              onSelectionChanged: null,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(height: 6),
            _safetyLegend(),
            const SizedBox(height: 6),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.compass_calibration_outlined),
              title: const Text('Calibración'),
              subtitle: const Text('Nivelar los pedales de la rueda'),
              trailing: OutlinedButton(
                onPressed: null,
                child: const Text('Calibrar'),
              ),
            ),
            _safetyLegend(),
            const SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: Icon(Icons.lock_outline),
              title: Text('Bloqueo del motor'),
              subtitle: Text('Bloqueo antirrobo de la rueda'),
              value: false,
              onChanged: null,
            ),
            _safetyLegend(),
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
            _safetyLegend(),
          ],
        ),
      ),
    );
  }

  /// Leyenda de seguridad para los controles peligrosos: por la regla
  /// de seguridad de la app, solo pueden usarse con la rueda detenida.
  Widget _safetyLegend() {
    return const Padding(
      padding: EdgeInsets.only(left: 4, bottom: 8),
      child: Row(
        children: [
          Icon(Icons.shield_outlined, size: 13, color: Color(0xFFFFB020)),
          SizedBox(width: 5),
          Text(
            'Solo con la rueda detenida',
            style: TextStyle(
              color: Color(0xFFFFB020),
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sliderControl({
    required IconData icon,
    required String title,
    required String valueLabel,
    required double value,
  }) {
    return Column(
      children: [
        Row(
          children: [
            Icon(icon, color: Colors.white54),
            const SizedBox(width: 12),
            Expanded(
              child: Text(title,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            Text(valueLabel,
                style: const TextStyle(color: Colors.white54)),
          ],
        ),
        Slider(value: value, onChanged: null),
      ],
    );
  }

  Widget _phase2Card() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: brandRed.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: brandRed.withValues(alpha: 0.3)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bluetooth, color: brandRed, size: 20),
              SizedBox(width: 8),
              Text(
                'Fase 2 · Bluetooth multimarca',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            'En la siguiente fase la app se enlazará por Bluetooth con tu '
            'rueda y detectará automáticamente su marca y modelo '
            '(multiprotocolo: InMotion, KingSong, Begode/Gotway, '
            'Veteran/LeaperKim y Ninebot). Leerá la telemetría en vivo '
            'para el Panel y además podrá OPERAR la rueda desde el '
            'teléfono — luces, tilt-back, alarmas, modo de pedales, '
            'calibración y bloqueo — con los comandos que el protocolo '
            'de cada marca exponga. '
            'En esta v1 las pantallas ya están construidas y el GPS de '
            'las rodadas es 100 % real.',
            style: TextStyle(color: Colors.white70, fontSize: 13.5),
          ),
        ],
      ),
    );
  }

  Widget _aboutCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Image.asset(
                'assets/logo.jpg',
                width: 84,
                height: 84,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'EUC OneWheel',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            const Text(
              'Versión 1.0.0',
              style: TextStyle(color: Colors.white60, fontSize: 13),
            ),
            const SizedBox(height: 12),
            const Text(
              'Una sola app para salir a rodar con cualquier rueda: graba '
              'tus rutas con GPS, guarda tu historial con el resumen '
              'completo de cada rodada y prepárate para controlar tu '
              'rueda por Bluetooth.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 13.5),
            ),
          ],
        ),
      ),
    );
  }
}
