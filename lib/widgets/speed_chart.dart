import 'package:flutter/material.dart';

import '../theme.dart';

/// Gráfico de línea sencillo: velocidad (km/h) a lo largo del viaje.
/// Se dibuja con CustomPainter, sin dependencias extra.
class SpeedChart extends StatelessWidget {
  const SpeedChart({
    super.key,
    required this.speedsKmh,
    this.height = 130,
    this.maxLabel,
  });

  /// Serie de velocidades en km/h (una por punto GPS con velocidad).
  final List<double> speedsKmh;
  final double height;
  final String? maxLabel;

  @override
  Widget build(BuildContext context) {
    if (speedsKmh.length < 2) {
      return SizedBox(
        height: height,
        child: const Center(
          child: Text(
            'Este viaje no registró velocidades suficientes para el gráfico.',
            style: TextStyle(color: subText, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final maxV = speedsKmh.reduce((a, b) => a > b ? a : b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: funcBlue,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                maxLabel ?? 'máx ${maxV.toStringAsFixed(0)} km/h',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(painter: _ChartPainter(speedsKmh)),
        ),
      ],
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter(this.values);

  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final scale = maxV <= 0 ? 1.0 : maxV * 1.15;

    // Rejilla suave.
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.07)
      ..strokeWidth = 1;
    for (var i = 1; i <= 3; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = size.width * i / (values.length - 1);
      final y = size.height - (values[i] / scale) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    // Relleno bajo la curva.
    final fillPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fillPath,
      Paint()..color = funcBlue.withValues(alpha: 0.13),
    );

    // Línea en degradado azul funcional → cian eléctrico (la
    // familia de la ruta del mapa en la identidad final).
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..shader = routeGradient().createShader(Offset.zero & size);
    canvas.drawPath(path, line);
  }

  @override
  bool shouldRepaint(_ChartPainter old) => old.values != values;
}
