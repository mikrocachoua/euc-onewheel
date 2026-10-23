import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../widgets/ui_kit.dart';

/// Encabezado estándar de las pantallas de Configuración: botón
/// circular de retroceso y título centrado sobre el fondo cockpit.
class SettingsScaffold extends StatelessWidget {
  const SettingsScaffold({
    super.key,
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: [
              Row(
                children: [
                  CircleIconButton(
                    icon: Icons.arrow_back_ios_new,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  Expanded(child: Center(child: ScreenTitle(title))),
                  const SizedBox(width: 48),
                ],
              ),
              const SizedBox(height: 16),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

/// Tarjeta blanca que agrupa filas de ajustes con divisores.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) rows.add(const Divider(height: 1));
      rows.add(children[i]);
    }
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Column(children: rows),
    );
  }
}

/// Fila de ajuste con selector de opciones (abre una hoja con las
/// opciones y marca la actual).
class ChoiceTile<T> extends StatelessWidget {
  const ChoiceTile({
    super.key,
    required this.title,
    this.subtitle,
    required this.valueLabel,
    required this.options,
    required this.current,
    required this.onChanged,
  });

  final String title;
  final String? subtitle;
  final String valueLabel;
  final List<(T, String)> options;
  final T current;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      title: Text(title,
          style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!,
              style: const TextStyle(color: subText, fontSize: 13.5)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(valueLabel,
              style: const TextStyle(
                  color: subText, fontSize: 15, fontWeight: FontWeight.w600)),
          const Icon(Icons.expand_more, color: funcBlue),
        ],
      ),
      onTap: () async {
        final picked = await showModalBottomSheet<T>(
          context: context,
          builder: (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (value, label) in options)
                  ListTile(
                    title: Text(label),
                    trailing: value == current
                        ? const Icon(Icons.check, color: funcBlue)
                        : null,
                    onTap: () => Navigator.of(ctx).pop(value),
                  ),
              ],
            ),
          ),
        );
        if (picked != null) onChanged(picked);
      },
    );
  }
}
