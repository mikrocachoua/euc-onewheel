import 'package:intl/intl.dart';

/// "1:07:05" o "07:05" según dure la rodada.
String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

/// "22/10/2026 · 07:45"
String formatDateTime(DateTime dt) =>
    DateFormat('dd/MM/yyyy · HH:mm').format(dt);

/// "22/10/2026"
String formatDate(DateTime dt) => DateFormat('dd/MM/yyyy').format(dt);
