import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';
import 'ui_kit.dart';

/// Medidor circular grande de velocidad, la JOYA de la identidad:
/// un tubo de vidrio azulado sobre un pozo con luz ambiental, y
/// dentro del tubo brilla la luz roja de la marca con profundidad
/// real (halo difuso → borde rojo oscuro → cuerpo en degradado
/// oscuro → vivo → salmón → núcleo casi blanco). La cifra central
/// va en degradado blanco → plata; ninguna letra es roja.
class SpeedGauge extends StatelessWidget {
  const SpeedGauge({
    super.key,
    required this.speed,
    required this.unitLabel,
    this.maxSpeed = 60,
    this.size = 240,
    this.alarm = false,
  });

  /// Velocidad ya convertida a la unidad elegida por el usuario.
  final double speed;
  final String unitLabel;

  /// Velocidad que llena el arco completo.
  final double maxSpeed;
  final double size;

  /// Si hay una alarma activa, el halo de la luz se intensifica.
  final bool alarm;

  @override
  Widget build(BuildContext context) {
    final fraction = (speed.abs() / maxSpeed).clamp(0.0, 1.0);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _GaugePainter(
          fraction: fraction,
          alarm: alarm,
          dark: Theme.of(context).brightness == Brightness.dark,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SilverGradientText(
                speed.abs().round().toString(),
                style: TextStyle(
                  fontSize: size * 0.34,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
              Text(
                unitLabel.toUpperCase(),
                style: TextStyle(
                  color: subText,
                  fontSize: size * 0.052,
                  letterSpacing: 2.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'VELOCIDAD',
                style: TextStyle(
                  color: subText,
                  fontSize: 11,
                  letterSpacing: 2.2,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter(
      {required this.fraction, required this.alarm, required this.dark});

  final double fraction;
  final bool alarm;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.43;
    const startAngle = math.pi * 0.75; // 135°: abajo a la izquierda
    const sweepTotal = math.pi * 1.5; // 270° de arco, como la demo
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Pozo del medidor: luz ambiental azulada arriba que se apaga
    // hacia los bordes.
    final well = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0, -0.2),
        radius: 0.68,
        colors: dark
            ? [
                const Color(0xFF82AAF0).withValues(alpha: 0.12),
                const Color(0xFF82AAF0).withValues(alpha: 0.03),
                Colors.black.withValues(alpha: 0.18),
              ]
            : [
                Colors.white.withValues(alpha: 0.6),
                const Color(0xFF82AAF0).withValues(alpha: 0.05),
                Colors.black.withValues(alpha: 0.05),
              ],
        stops: const [0, 0.68, 1],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawCircle(center, size.width * 0.49, well);

    // Tubo de cristal vacío: banda translúcida azulada gruesa…
    final glassTube = Paint()
      ..color = dark
          ? const Color(0xFFAAC3E6).withValues(alpha: 0.22)
          : const Color(0xFFC7D3E4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.085;
    canvas.drawArc(rect, startAngle, sweepTotal, false, glassTube);
    // …y su pista interior.
    final track = Paint()
      ..color = dark ? surfaceTrack : const Color(0xFFD9DDE4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.05;
    canvas.drawArc(rect, startAngle, sweepTotal, false, track);

    // Marcas (ticks) atenuadas alrededor del arco.
    final tickPaint = Paint()
      ..color = dimText.withValues(alpha: dark ? 0.9 : 0.6)
      ..strokeWidth = size.width * 0.008
      ..strokeCap = StrokeCap.round;
    const tickCount = 27;
    for (var i = 0; i <= tickCount; i++) {
      final a = startAngle + sweepTotal * i / tickCount;
      final r1 = radius + size.width * 0.062;
      final r2 = radius + size.width * 0.082;
      canvas.drawLine(
        center + Offset(math.cos(a) * r1, math.sin(a) * r1),
        center + Offset(math.cos(a) * r2, math.sin(a) * r2),
        tickPaint,
      );
    }

    if (fraction > 0) {
      final sweep = sweepTotal * fraction;
      // Luz roja DENTRO del tubo, en capas de profundidad:
      // 1) halo difuso que tiñe el cristal…
      final halo = Paint()
        ..color = brandRed.withValues(alpha: alarm ? 0.5 : 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.11
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
      canvas.drawArc(rect, startAngle, sweep, false, halo);
      // 2) borde oscuro de la luz…
      final edge = Paint()
        ..color = brandRedEdge
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.07
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(rect, startAngle, sweep, false, edge);
      // 3) cuerpo luminoso en degradado (oscuro → vivo → salmón)…
      final body = Paint()
        ..shader = const LinearGradient(
          begin: Alignment.bottomLeft,
          end: Alignment.topRight,
          colors: [brandRedDeep, brandRed, brandRedLight],
          stops: [0, 0.45, 1],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.05
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(rect, startAngle, sweep, false, body);
      // 4) núcleo casi blanco: la luz más intensa, en el centro.
      final core = Paint()
        ..color = gaugeCore.withValues(alpha: 0.95)
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.02
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(rect, startAngle, sweep, false, core);
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.fraction != fraction || old.alarm != alarm || old.dark != dark;
}

/// Anillo de progreso pequeño (p. ej. para la batería del panel).
class RingIndicator extends StatelessWidget {
  const RingIndicator({
    super.key,
    required this.fraction,
    required this.centerText,
    this.size = 64,
    this.color = evCyan,
  });

  final double fraction; // 0..1
  final String centerText;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: fraction.clamp(0.0, 1.0),
            strokeWidth: 7,
            backgroundColor: surfaceTrack,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
          Text(
            centerText,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
