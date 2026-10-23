import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Una sección de la barra de navegación flotante.
class TabItem {
  const TabItem(this.icon, this.selectedIcon, this.label);
  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// Barra de navegación inferior FLOTANTE tipo píldora: vidrio
/// oscuro translúcido despegado de los bordes y la sección activa
/// como LENTE de vidrio azul (degradado celeste → azul funcional →
/// azul profundo, con resplandor interior), icono y texto en tinta
/// blanca. Las inactivas van en gris atenuado, como en la demo.
class FloatingTabBar extends StatelessWidget {
  const FloatingTabBar({
    super.key,
    required this.items,
    required this.index,
    required this.onSelected,
  });

  final List<TabItem> items;
  final int index;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.5 : 0.14),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            decoration: BoxDecoration(
              color: dark
                  ? const Color(0xFF0D1119).withValues(alpha: 0.82)
                  : Colors.white.withValues(alpha: 0.78),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: dark
                    ? [
                        Colors.white.withValues(alpha: 0.10),
                        Colors.white.withValues(alpha: 0.03),
                      ]
                    : [
                        Colors.white.withValues(alpha: 0.55),
                        Colors.white.withValues(alpha: 0.25),
                      ],
              ),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: dark
                    ? Colors.white.withValues(alpha: 0.125)
                    : const Color(0xFFDFE2E8),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
                child: Row(
                  children: [
                    for (var i = 0; i < items.length; i++)
                      Expanded(child: _tab(context, i)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tab(BuildContext context, int i) {
    final item = items[i];
    final active = i == index;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final inactiveColor = dark ? dimText : const Color(0xFF9AA0AA);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onSelected(i),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          // La sección activa es una lente de vidrio azul con la luz
          // funcional brillando en su interior.
          gradient: active
              ? LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF8CB9F5)
                        .withValues(alpha: dark ? 0.22 : 0.35),
                    funcBlue.withValues(alpha: dark ? 0.13 : 0.22),
                    funcBlueDeep.withValues(alpha: dark ? 0.16 : 0.28),
                  ],
                  stops: const [0, 0.55, 1],
                )
              : null,
          border: active
              ? Border.all(color: funcBlue.withValues(alpha: 0.42))
              : null,
          boxShadow: active
              ? [
                  BoxShadow(
                    color: funcBlue.withValues(alpha: 0.30),
                    blurRadius: 14,
                    spreadRadius: -2,
                  ),
                ]
              : null,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              active ? item.selectedIcon : item.icon,
              color: active
                  ? (dark ? Colors.white : const Color(0xFF0B3B73))
                  : inactiveColor,
              size: 25,
            ),
            const SizedBox(height: 2),
            Text(
              item.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                color: active
                    ? (dark ? inkText : const Color(0xFF0B3B73))
                    : inactiveColor,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
