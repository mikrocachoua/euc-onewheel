import 'package:euc_onewheel/main.dart';
import 'package:euc_onewheel/screens/panel_screen.dart';
import 'package:euc_onewheel/state/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('La navegación flotante recorre las cinco secciones de la v2',
      (tester) async {
    final settings = AppSettings()..demoMode = true;
    await tester.pumpWidget(EucOneWheelApp(settings: settings));
    await tester.pump();

    // Dispositivos: encabezado, tarjeta demo y lista ENCONTRADO.
    expect(find.text('Dispositivos'), findsOneWidget);
    expect(find.text('ENCONTRADO'), findsOneWidget);
    expect(find.text('Modo demo activo'), findsOneWidget);
    expect(find.text('Mi rueda (demo)'), findsOneWidget);

    // Viajes: historial y acceso a grabar.
    await tester.tap(find.text('Viajes'));
    await tester.pump();
    expect(find.text('Grabar una rodada'), findsOneWidget);

    // Mapa: título y botón AR.
    await tester.tap(find.text('Mapa'));
    await tester.pump();
    expect(find.text('AR'), findsOneWidget);

    // Perfil: la rueda de demostración genérica del perfil demo
    // (la app no se enfoca en ninguna marca en especial).
    await tester.tap(find.text('Perfil'));
    await tester.pump();
    expect(find.text('Ricardo Cachoúa'), findsOneWidget);
    expect(find.text('Rueda de demostración'), findsOneWidget);
    expect(find.text('46%'), findsOneWidget);

    // Configuración: el menú completo de subpantallas.
    await tester.tap(find.text('Configuración'));
    await tester.pump();
    expect(find.text('Aplicación'), findsOneWidget);
    expect(find.text('Privacidad'), findsOneWidget);
    expect(find.text('Tienda'), findsOneWidget);
    expect(find.text('Integración'), findsOneWidget);
    expect(find.text('Soporte'), findsOneWidget);
    expect(find.text('Acerca de'), findsOneWidget);
  });

  testWidgets('El panel en modo demo muestra telemetría simulada',
      (tester) async {
    final settings = AppSettings()..demoMode = true;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: PanelScreen(settings: settings),
        ),
      ),
    );
    // Deja correr el simulador un par de ciclos.
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('Rueda de demostración'), findsOneWidget);
    expect(find.text('VELOCIDAD'), findsOneWidget);
    expect(find.text('Batería'), findsWidgets);
    // La sección de controles está más abajo en la lista: se rueda
    // el ListView principal hasta que aparezca.
    for (var i = 0;
        i < 6 && find.text('Controles de la rueda').evaluate().isEmpty;
        i++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -500));
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(find.text('Controles de la rueda'), findsOneWidget);
    expect(
        find.text('Solo con la rueda detenida y tu confirmación '
            '(compuerta de seguridad)'),
        findsWidgets);
  });
}
