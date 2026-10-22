import 'package:flutter/material.dart';

import '../theme.dart';

/// Pantalla principal de EUC OneWheel con su panel de telemetría
/// avanzado: estado de la rueda, velocímetro grande y tarjetas de
/// telemetría.
/// En la v1 la telemetría es una pantalla preparada: el Bluetooth real
/// con la rueda llega en la fase 2. El GPS real vive en la pestaña Rodar.
class PanelScreen extends StatelessWidget {
  const PanelScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _header(),
          const SizedBox(height: 16),
          _wheelCard(context),
          const SizedBox(height: 24),
          _speedGauge(context),
          const SizedBox(height: 24),
          _statsGrid(context),
          const SizedBox(height: 16),
          _phaseNote(context),
        ],
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.asset(
            'assets/logo.jpg',
            width: 52,
            height: 52,
            fit: BoxFit.cover,
          ),
        ),
        const SizedBox(width: 12),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'EUC OneWheel',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            Text(
              'Tu compañera de rodadas',
              style: TextStyle(color: Colors.white60, fontSize: 13),
            ),
          ],
        ),
      ],
    );
  }

  Widget _wheelCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: brandRed.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.bluetooth_disabled, color: brandRed),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sin rueda conectada',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'La conexión Bluetooth real con tu rueda llega en la '
                    'fase 2: la app detectará automáticamente su marca y '
                    'modelo. Mientras tanto, graba tus rodadas con el GPS '
                    'real del teléfono en la pestaña Rodar.',
                    style: TextStyle(color: Colors.white60, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _speedGauge(BuildContext context) {
    return Center(
      child: Container(
        width: 230,
        height: 230,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF16161A),
          border: Border.all(color: brandRed, width: 5),
          boxShadow: [
            BoxShadow(
              color: brandRed.withValues(alpha: 0.35),
              blurRadius: 28,
              spreadRadius: 2,
            ),
          ],
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '0',
              style: TextStyle(fontSize: 84, fontWeight: FontWeight.w800),
            ),
            Text(
              'km/h',
              style: TextStyle(color: Colors.white60, fontSize: 16),
            ),
            SizedBox(height: 6),
            Text(
              'VELOCIDAD',
              style: TextStyle(
                color: brandRed,
                fontSize: 11,
                letterSpacing: 2,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statsGrid(BuildContext context) {
    const items = [
      (Icons.battery_full, 'Batería'),
      (Icons.electric_bolt, 'Voltaje'),
      (Icons.power, 'Potencia'),
      (Icons.thermostat, 'Temperatura'),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.9,
      children: [
        for (final (icon, label) in items)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Icon(icon, size: 18, color: brandRed),
                      const SizedBox(width: 6),
                      Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '—',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _phaseNote(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: brandRed.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: brandRed.withValues(alpha: 0.3)),
      ),
      child: const Row(
        children: [
          Icon(Icons.gps_fixed, color: brandRed),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Fase 1: el GPS de la pestaña Rodar ya es 100 % real. '
              'La telemetría de esta pantalla se activa en la fase 2, '
              'cuando llegue el Bluetooth.',
              style: TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
