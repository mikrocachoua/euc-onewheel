import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../state/app_settings.dart';
import '../theme.dart';

/// ¿Está activo el tema «Negro puro»? Lectura segura del alcance de
/// ajustes: sin alcance (pruebas de widgets sueltos) devuelve false.
bool isPureBlackTheme(BuildContext context) {
  final scope = context.dependOnInheritedWidgetOfExactType<AppSettingsScope>();
  return scope?.notifier?.themeChoice == AppThemeChoice.negroPuro;
}

/// Fondo de pantalla completa de EUC OneWheel: grafito azulado
/// profundo con resplandores ambientales azulados muy sutiles
/// arriba (la «luz» que los paneles de vidrio refractan). En tema
/// claro, grisáceo suave; en «Negro puro», negro absoluto.
class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (!dark) {
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFE9EBEF), Color(0xFFF5F6F9)],
          ),
        ),
        child: child,
      );
    }
    if (isPureBlackTheme(context)) {
      return Container(color: Colors.black, child: child);
    }
    return Stack(
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [cockpitBg, cockpitBgTop],
            ),
          ),
        ),
        Positioned(
          top: -130,
          left: -70,
          child: _glowBlob(const Color(0xFF82AAE6), 0.08, 340),
        ),
        Positioned(
          top: -120,
          right: -60,
          child: _glowBlob(evCyan, 0.07, 320),
        ),
        child,
      ],
    );
  }

  Widget _glowBlob(Color color, double alpha, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withValues(alpha: alpha),
            color.withValues(alpha: 0),
          ],
        ),
      ),
    );
  }
}

/// Panel de VIDRIO en capas (la superficie de la identidad final):
/// degradado base grafito azulado + velo de cristal con
/// iridiscencia sutil azul/violeta, borde fino luminoso, brillo
/// especular en el borde superior, resplandor interior azul abajo
/// y sombra profunda. Con [blur] se aplica desenfoque del fondo
/// (solo en paneles clave, por rendimiento).
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.radius = cardRadius,
    this.blur = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool blur;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final black = dark && isPureBlackTheme(context);
    Widget panel = Container(
      decoration: BoxDecoration(
        gradient: cardBaseGradient(dark: dark, pureBlack: black),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: dark
              ? Colors.white.withValues(alpha: black ? 0.10 : 0.125)
              : const Color(0xFFDFE2E8),
        ),
        boxShadow: glassShadow(dark: dark),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(
          children: [
            // Velo de cristal con iridiscencia.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: glassSheenGradient(dark: dark, pureBlack: black),
                ),
              ),
            ),
            // Resplandor interior azul en el borde inferior.
            if (dark)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  height: 30,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        const Color(0xFF5A8CFF).withValues(alpha: 0.10),
                        const Color(0xFF5A8CFF).withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            Padding(padding: padding, child: child),
          ],
        ),
      ),
    );
    // Brillo especular: una línea de luz fina en el borde superior.
    panel = Stack(
      children: [
        panel,
        Positioned(
          top: 0,
          left: radius * 0.8,
          right: radius * 0.8,
          child: Container(
            height: 1.4,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white.withValues(alpha: 0),
                  Colors.white.withValues(alpha: dark ? 0.55 : 0.9),
                  Colors.white.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ),
      ],
    );
    if (blur) {
      panel = BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: panel,
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: panel,
    );
  }
}

/// Tarjeta de superficie redondeada (vidrio en capas): la pieza
/// básica de todo el diseño final.
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.margin,
    this.onTap,
    this.glassBlur = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;

  /// Si es true, el vidrio desenfoca el fondo (paneles clave).
  final bool glassBlur;

  @override
  Widget build(BuildContext context) {
    final panel = GlassPanel(
      padding: padding,
      blur: glassBlur,
      child: child,
    );
    Widget result = panel;
    if (margin != null) {
      result = Padding(padding: margin!, child: result);
    }
    if (onTap == null) return result;
    return InkWell(
      borderRadius: BorderRadius.circular(cardRadius),
      onTap: onTap,
      child: result,
    );
  }
}

/// Baldosa de icono en vidrio azul (150°): cian suave → azul
/// funcional → azul intenso, con el icono en azul funcional. Es la
/// baldosa de la demo para Bluetooth, menús y tarjetas de acceso.
class GlassIconTile extends StatelessWidget {
  const GlassIconTile({
    super.key,
    required this.icon,
    this.size = 48,
    this.iconSize = 24,
    this.radius = 14,
  });

  final IconData icon;
  final double size;
  final double iconSize;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: iconTileGradient(),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: funcBlue.withValues(alpha: 0.22),
            blurRadius: 12,
            spreadRadius: -3,
          ),
        ],
      ),
      child: Icon(icon, color: funcBlue, size: iconSize),
    );
  }
}

/// Texto con el degradado de las CIFRAS GRANDES (blanco → plata en
/// oscuro; grafito → negro en claro). Para titulares numéricos.
class SilverGradientText extends StatelessWidget {
  const SilverGradientText(this.text, {super.key, required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) =>
          numberGradient(dark: dark).createShader(bounds),
      child: Text(text, style: style.copyWith(color: Colors.white)),
    );
  }
}

/// Encabezado de sección en mayúsculas y plata, como «ENCONTRADO».
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 10, 6, 10),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: dark ? silverText : const Color(0xFF59616D),
          fontSize: 12.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 2,
        ),
      ),
    );
  }
}

/// Título grande centrado de las pantallas principales.
class ScreenTitle extends StatelessWidget {
  const ScreenTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Text(
      text,
      style: TextStyle(
        color: dark ? Colors.white : const Color(0xFF141419),
        fontSize: 26,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

/// Botón circular de vidrio (retroceso, registros, acciones).
class CircleIconButton extends StatelessWidget {
  const CircleIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final button = Material(
      color: dark
          ? Colors.white.withValues(alpha: 0.07)
          : Colors.black.withValues(alpha: 0.05),
      shape: CircleBorder(
        side: BorderSide(
          color: dark ? Colors.white.withValues(alpha: 0.125) : Colors.black12,
        ),
      ),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(
            icon,
            color: dark ? Colors.white : const Color(0xFF141419),
            size: 24,
          ),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// Botón clave en cápsula de VIDRIO AZUL con la luz funcional
/// brillando dentro: degradado celeste → azul → azul profundo,
/// borde claro y resplandor azul suave bajo la cápsula. (El rojo
/// nunca es un botón: es la joya del velocímetro y las alertas.)
class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.color,
  });

  final String label;
  final VoidCallback? onPressed;

  /// Tinte alternativo; por defecto, el vidrio azul funcional.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = color ?? funcBlue;
    final enabled = onPressed != null;
    final gradient = color == null
        ? blueGlassGradient(dark: dark)
        : LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              base.withValues(alpha: 0.55),
              base.withValues(alpha: 0.85),
              base.withValues(alpha: 0.65),
            ],
          );
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: base.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onPressed,
                child: Stack(
                  children: [
                    // Base azul profunda bajo el vidrio translúcido.
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: color == null
                              ? (dark ? funcBlueDeep : funcBlue)
                              : base,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(
                        gradient: gradient,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: color == null
                              ? funcBlueLight.withValues(alpha: 0.5)
                              : Colors.white.withValues(alpha: 0.30),
                        ),
                      ),
                      child: Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Distintivo pequeño (p. ej. «Demo», «CONECTADA», «En desarrollo»).
class PillBadge extends StatelessWidget {
  const PillBadge(this.text, {super.key, this.color = const Color(0xFFB8BEC9)});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

/// Fila de navegación dentro de una tarjeta: título, descripción
/// opcional y flecha a la derecha. La baldosa del icono es vidrio
/// azul con el icono en azul funcional.
class NavTile extends StatelessWidget {
  const NavTile({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.trailing,
    required this.onTap,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      leading: icon == null
          ? null
          : GlassIconTile(icon: icon!, size: 42, iconSize: 22, radius: 12),
      title: Text(
        title,
        style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: const TextStyle(color: subText, fontSize: 13.5),
            ),
      trailing:
          trailing ?? const Icon(Icons.chevron_right, color: subText, size: 26),
      onTap: onTap,
    );
  }
}

/// Fila con interruptor dentro de una tarjeta.
class SwitchTile extends StatelessWidget {
  const SwitchTile({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      title: Text(
        title,
        style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: const TextStyle(color: subText, fontSize: 13.5),
            ),
      value: value,
      onChanged: onChanged,
    );
  }
}

/// Selector segmentado compacto (p. ej. °C/°F, bar/psi, Todo/Amigos):
/// contenedor de vidrio elevado y la opción activa como lente de
/// cristal con texto en tinta, como en la demo.
class SegmentedChoice<T> extends StatelessWidget {
  const SegmentedChoice({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final List<(T, String)> options;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: dark
            ? surfaceRaised.withValues(alpha: 0.7)
            : const Color(0xFFE7E9EE),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: dark
              ? Colors.white.withValues(alpha: 0.125)
              : const Color(0xFFDFE2E8),
        ),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (value, label) in options)
            GestureDetector(
              onTap: () => onChanged(value),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  gradient:
                      value == selected ? glassSheenGradient(dark: dark) : null,
                  color: value == selected
                      ? (dark ? surfaceTrack : Colors.white)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: value == selected
                      ? [
                          BoxShadow(
                            color: Colors.black
                                .withValues(alpha: dark ? 0.35 : 0.08),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: value == selected
                        ? (dark ? Colors.white : const Color(0xFF141419))
                        : subText,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Espacio inferior para que el contenido nunca quede tapado por la
/// barra de navegación flotante.
const double tabBarClearance = 118;
