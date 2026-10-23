import 'package:flutter/material.dart';

/// ————————————————————————————————————————————————————————————————
/// Identidad visual final de EUC OneWheel (build #6, portada de la
/// demo aprobada): cluster digital de auto eléctrico de alta gama
/// sobre grafito azulado profundo. Reglas de color:
///
/// · El AZUL FUNCIONAL (#2E7CD6, en degradados vivos zafiro →
///   eléctrico → cian) es el acento de trabajo: botones, interruptores,
///   deslizadores, pestaña activa, Bluetooth conectado y la ruta del
///   mapa. Nada funcional va en rojo.
/// · La tipografía es blanca/plateada: CERO letras rojas. Las cifras
///   grandes van en degradado blanco → plata.
/// · El ROJO de la marca (#E0231C) vive solo como JOYA: la luz dentro
///   del tubo de vidrio del velocímetro (borde oscuro → rojo vivo →
///   núcleo casi blanco) y las alertas críticas.
/// · El CIAN eléctrico (#35C4FF) se reserva a los datos de energía:
///   batería, voltaje, corriente, potencia y autonomía.
/// · Las superficies son VIDRIO en capas: degradado base grafito
///   azulado + velo de cristal con iridiscencia sutil (luz azul y
///   violeta en los bordes), nunca tonos planos.
/// · La seguridad se expresa en ÁMBAR (tarjeta y leyendas).
/// ————————————————————————————————————————————————————————————————

/// Rojo oficial de la marca EUC OneWheel (logo glossy de Mikro).
/// SOLO joya (luz del velocímetro) y alertas críticas.
const Color brandRed = Color(0xFFE0231C);

/// Rojo profundo y borde oscuro del tubo del velocímetro: el
/// degradado de la luz roja dentro del cristal va de este borde
/// oscuro al rojo vivo y de ahí al salmón luminoso.
const Color brandRedDeep = Color(0xFF8E0F0B);
const Color brandRedEdge = Color(0xFF6E0A06);
const Color brandRedLight = Color(0xFFFF6B5E);

/// Núcleo casi blanco de la luz del velocímetro.
const Color gaugeCore = Color(0xFFFFF1EA);

/// Azul funcional: el acento de trabajo de toda la app.
const Color funcBlue = Color(0xFF2E7CD6);

/// Azul claro para textos e iconos sobre fondos azules suaves.
const Color funcBlueLight = Color(0xFF8FBAF5);

/// Azul profundo, base de los degradados de vidrio azul.
const Color funcBlueDeep = Color(0xFF12428A);

/// Cian eléctrico «energía EV»: SOLO datos de energía (batería,
/// voltaje, corriente, potencia, autonomía) y brillos de la ruta.
const Color evCyan = Color(0xFF35C4FF);

/// Cian casi blanco, extremo luminoso de los degradados de energía.
const Color cyanLight = Color(0xFF8FE8FF);

/// Alias histórico del acento de energía.
const Color accentBlue = evCyan;

/// Ámbar de seguridad (tarjeta de la regla de seguridad, leyendas
/// de la compuerta y avisos de precaución).
const Color safetyAmber = Color(0xFFF5A623);

/// Verde de estado correcto (p. ej. punto de inicio de una ruta).
const Color okGreen = Color(0xFF2EBC78);

/// Fondo grafito azulado profundo del cluster (base y parte alta).
const Color cockpitBg = Color(0xFF11151D);
const Color cockpitBgTop = Color(0xFF131A24);

/// Superficies de vidrio: tarjeta base, tarjeta elevada y pista/
/// borde grueso (la profundidad real la dan los degradados de
/// [cardBaseGradient] y [glassSheenGradient]).
const Color surfaceDark = Color(0xFF181E29);
const Color surfaceRaised = Color(0xFF1F2634);
const Color surfaceTrack = Color(0xFF2C3547);
const Color surfaceBorder = Color(0xFF2C3547);

/// Texto principal (blanco), secundario (gris) y terciario.
const Color inkText = Color(0xFFF4F5F7);
const Color subText = Color(0xFF9BA1AB);
const Color dimText = Color(0xFF5F636D);

/// Plata de las etiquetas de sección y detalles sobrios.
const Color silverText = Color(0xFFC6CDD9);

/// Radio estándar de las tarjetas.
const double cardRadius = 22;

/// Degradado BASE de las tarjetas de vidrio (165°): grafito azulado
/// en capas, más luminoso arriba a la izquierda y profundo abajo.
LinearGradient cardBaseGradient({required bool dark, bool pureBlack = false}) {
  if (pureBlack) {
    return const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF141419), Color(0xFF0B0B0E)],
    );
  }
  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: dark
        ? [
            const Color(0xFF384866).withValues(alpha: 0.66),
            const Color(0xFF1B2231).withValues(alpha: 0.74),
            const Color(0xFF0F1521).withValues(alpha: 0.84),
          ]
        : [
            Colors.white.withValues(alpha: 0.97),
            const Color(0xFFF3F6FB).withValues(alpha: 0.94),
            const Color(0xFFDFE7F5).withValues(alpha: 0.95),
          ],
    stops: dark ? const [0, 0.46, 1] : const [0, 0.48, 1],
  );
}

/// Velo de CRISTAL sobre las tarjetas (158°): luz blanca arriba que
/// se apaga, con iridiscencia sutil azul y violeta hacia los bordes.
LinearGradient glassSheenGradient(
    {required bool dark, bool pureBlack = false}) {
  return LinearGradient(
    begin: const Alignment(-0.35, -1),
    end: const Alignment(0.35, 1),
    colors: dark
        ? [
            Colors.white.withValues(alpha: pureBlack ? 0.07 : 0.14),
            Colors.white.withValues(alpha: pureBlack ? 0.015 : 0.03),
            const Color(0xFF82AAFF).withValues(alpha: pureBlack ? 0.03 : 0.06),
            const Color(0xFF966EFF).withValues(alpha: pureBlack ? 0.02 : 0.05),
          ]
        : [
            Colors.white.withValues(alpha: 0.85),
            Colors.white.withValues(alpha: 0.25),
            const Color(0xFF8CB4FF).withValues(alpha: 0.12),
            const Color(0xFFBEA0FF).withValues(alpha: 0.08),
          ],
    stops: const [0, 0.38, 0.72, 1],
  );
}

/// Degradado de VIDRIO AZUL de los botones clave (píldora): luz
/// celeste arriba, azul funcional en el centro y azul profundo
/// abajo; el brillo interior lo aporta el resplandor del contenedor.
LinearGradient blueGlassGradient({bool dark = true}) {
  return LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      const Color(0xFF8CB9F5).withValues(alpha: dark ? 0.32 : 0.55),
      funcBlue.withValues(alpha: dark ? 0.30 : 0.75),
      funcBlueDeep.withValues(alpha: dark ? 0.36 : 0.85),
    ],
    stops: const [0, 0.45, 1],
  );
}

/// Degradado de las baldosas de icono (150°): cian suave → azul
/// funcional translúcido → azul intenso, como en la demo.
LinearGradient iconTileGradient() {
  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      evCyan.withValues(alpha: 0.26),
      funcBlue.withValues(alpha: 0.16),
      const Color(0xFF1B5FBF).withValues(alpha: 0.24),
    ],
    stops: const [0, 0.52, 1],
  );
}

/// Degradado de las CIFRAS GRANDES: blanco → plata en oscuro;
/// grafito → negro en claro. Nunca color plano ni rojo.
LinearGradient numberGradient({required bool dark}) {
  return LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: dark
        ? const [Colors.white, Color(0xFFD9E1ED), Color(0xFF9FB0C6)]
        : const [Color(0xFF262B33), Color(0xFF14171C), Color(0xFF04060A)],
    stops: const [0.22, 0.66, 1],
  );
}

/// Degradado de ENERGÍA (batería y barras de energía): azul
/// funcional → cian eléctrico → cian casi blanco, con brillo.
LinearGradient energyGradient() {
  return const LinearGradient(
    colors: [funcBlue, evCyan, cyanLight],
    stops: [0, 0.55, 1],
  );
}

/// Degradado de la RUTA en el mapa y de las líneas de gráficas:
/// la misma familia azul → cian de la identidad.
LinearGradient routeGradient() => energyGradient();

/// Sombra profunda de las tarjetas de vidrio.
List<BoxShadow> glassShadow({required bool dark}) {
  return [
    BoxShadow(
      color: Colors.black.withValues(alpha: dark ? 0.55 : 0.10),
      blurRadius: 30,
      offset: const Offset(0, 14),
    ),
    BoxShadow(
      color: Colors.black.withValues(alpha: dark ? 0.35 : 0.06),
      blurRadius: 8,
      offset: const Offset(0, 3),
    ),
  ];
}

/// Tema principal de EUC OneWheel: OSCURO tipo cluster digital
/// sobre grafito azulado, vidrio en capas y azul funcional como
/// acento de trabajo; el rojo queda para la joya del velocímetro
/// y las alertas críticas.
ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: funcBlue,
    brightness: Brightness.dark,
  ).copyWith(
    primary: funcBlue,
    secondary: evCyan,
    surface: surfaceDark,
    onSurface: inkText,
    error: brandRed,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: cockpitBg,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      foregroundColor: Colors.white,
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.w800,
      ),
      iconTheme: IconThemeData(color: Colors.white),
    ),
    cardTheme: CardThemeData(
      color: surfaceDark,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(cardRadius),
        side: const BorderSide(color: surfaceBorder),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: funcBlue,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: inkText,
        side: BorderSide(color: Colors.white.withValues(alpha: 0.28)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.all(Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? funcBlue : surfaceTrack,
      ),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: funcBlue,
      thumbColor: funcBlue,
      inactiveTrackColor: surfaceTrack,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: funcBlue,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surfaceDark,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(cardRadius),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: surfaceRaised,
      contentTextStyle: TextStyle(color: Colors.white),
    ),
    dividerTheme: const DividerThemeData(color: surfaceBorder),
    listTileTheme: const ListTileThemeData(
      textColor: inkText,
      iconColor: subText,
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? funcBlue : null,
      ),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? funcBlue : null,
      ),
    ),
  );
}

/// Tema NEGRO PURO (opción de Apariencia, como en la demo): fondo
/// negro absoluto y vidrio casi negro; mismos acentos.
ThemeData buildBlackAppTheme() {
  final base = buildAppTheme();
  return base.copyWith(
    scaffoldBackgroundColor: Colors.black,
    colorScheme: base.colorScheme.copyWith(surface: const Color(0xFF0B0B0E)),
    cardTheme: CardThemeData(
      color: const Color(0xFF0B0B0E),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(cardRadius),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: const Color(0xFF0B0B0E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(cardRadius),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: Color(0xFF101014),
      contentTextStyle: TextStyle(color: Colors.white),
    ),
    dividerTheme: DividerThemeData(
      color: Colors.white.withValues(alpha: 0.08),
    ),
  );
}

/// Tema claro de EUC OneWheel (opción en Apariencia): fondos
/// grisáceos suaves, tarjetas blancas de vidrio y el mismo azul
/// funcional como acento de trabajo.
ThemeData buildLightAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: funcBlue,
    brightness: Brightness.light,
  ).copyWith(
    primary: funcBlue,
    secondary: const Color(0xFF0B93D6),
    surface: Colors.white,
    error: brandRed,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFFF5F6F9),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      foregroundColor: Color(0xFF141419),
      titleTextStyle: TextStyle(
        color: Color(0xFF141419),
        fontSize: 20,
        fontWeight: FontWeight.w800,
      ),
      iconTheme: IconThemeData(color: Color(0xFF141419)),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(cardRadius),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: funcBlue,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF141419),
        side: const BorderSide(color: Color(0xFFB9BEC9)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.all(Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? funcBlue
            : const Color(0xFFD9DDE4),
      ),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: funcBlue,
      thumbColor: funcBlue,
      inactiveTrackColor: Color(0xFFD9DDE4),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: funcBlue,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(cardRadius),
      ),
    ),
    dividerTheme: const DividerThemeData(color: Color(0xFFDFE2E8)),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? funcBlue : null,
      ),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? funcBlue : null,
      ),
    ),
  );
}

/// Alias histórico: el tema oscuro ES el tema de la app.
ThemeData buildDarkAppTheme() => buildAppTheme();
