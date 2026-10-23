/// Registro sencillo de eventos de la app (en memoria), para la
/// función «Compartir registros» de Soporte: qué pasó, cuándo, y el
/// texto listo para compartir con el resumen de auditoría de la
/// compuerta de seguridad si se le pasa.
class AppLog {
  AppLog._();
  static final AppLog instance = AppLog._();

  final List<String> _entries = [];

  /// Máximo de entradas guardadas (las más viejas se descartan).
  static const int maxEntries = 200;

  void add(String event) {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    _entries
        .add('${two(now.hour)}:${two(now.minute)}:${two(now.second)} · $event');
    if (_entries.length > maxEntries) {
      _entries.removeRange(0, _entries.length - maxEntries);
    }
  }

  List<String> get entries => List.unmodifiable(_entries);

  /// Texto completo del registro para compartir.
  String exportText({String? extra}) {
    final buffer = StringBuffer()
      ..writeln('EUC OneWheel — registro de la app')
      ..writeln('Generado: ${DateTime.now().toIso8601String()}')
      ..writeln('');
    if (_entries.isEmpty) {
      buffer.writeln('(sin eventos en esta sesión)');
    } else {
      for (final e in _entries) {
        buffer.writeln(e);
      }
    }
    if (extra != null && extra.isNotEmpty) {
      buffer
        ..writeln('')
        ..writeln(extra);
    }
    return buffer.toString();
  }

  void clear() => _entries.clear();
}
