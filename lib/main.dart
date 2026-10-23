import 'package:flutter/material.dart';

import 'screens/devices_screen.dart';
import 'screens/map_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/rides_screen.dart';
import 'screens/settings_screen.dart';
import 'services/app_log.dart';
import 'services/ble/wheel_connection_controller.dart';
import 'state/app_settings.dart';
import 'theme.dart';
import 'widgets/floating_tab_bar.dart';
import 'widgets/ui_kit.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await AppSettings.load();
  AppLog.instance.add('App iniciada (base v2)');
  runApp(EucOneWheelApp(settings: settings));
}

/// EUC OneWheel — versión 2, build #6.
///
/// Identidad visual final (portada de la demo aprobada): cluster
/// digital sobre grafito azulado con paneles de vidrio en capas,
/// azul funcional como acento de trabajo, cifras en degradado
/// blanco → plata y el rojo de la marca solo como luz dentro del
/// tubo del velocímetro y en alertas críticas. Navegación flotante
/// de cinco secciones (Dispositivos, Viajes, Mapa, Perfil,
/// Configuración) y contenido siempre a pantalla completa. La base
/// Bluetooth multimarca, la grabación GPS y el historial siguen
/// funcionando igual, sin fijarse en ninguna marca en especial.
class EucOneWheelApp extends StatelessWidget {
  const EucOneWheelApp({super.key, this.settings});

  /// Ajustes cargados al arrancar (en pruebas puede omitirse).
  final AppSettings? settings;

  @override
  Widget build(BuildContext context) {
    final effectiveSettings = settings ?? AppSettings();
    return AppSettingsScope(
      settings: effectiveSettings,
      child: ListenableBuilder(
        listenable: effectiveSettings,
        builder: (context, _) {
          final choice = effectiveSettings.themeChoice;
          return MaterialApp(
            title: 'EUC OneWheel',
            debugShowCheckedModeBanner: false,
            theme: buildLightAppTheme(),
            darkTheme: choice == AppThemeChoice.negroPuro
                ? buildBlackAppTheme()
                : buildAppTheme(),
            themeMode: switch (choice) {
              AppThemeChoice.claro => ThemeMode.light,
              AppThemeChoice.oscuro => ThemeMode.dark,
              AppThemeChoice.negroPuro => ThemeMode.dark,
              AppThemeChoice.sistema => ThemeMode.system,
            },
            home: HomeShell(settings: effectiveSettings),
          );
        },
      ),
    );
  }
}

/// Contenedor principal: las cinco secciones a pantalla completa
/// con la barra de navegación flotante encima.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.settings, this.controller});

  final AppSettings settings;
  final WheelConnectionController? controller;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  final _ridesKey = GlobalKey<RidesScreenState>();

  /// Conexión Bluetooth con la rueda: la comparten Dispositivos
  /// (escaneo/conexión), el Panel (telemetría) y el Perfil.
  late final WheelConnectionController _wheelController =
      widget.controller ?? WheelConnectionController();

  late final List<Widget> _screens = [
    DevicesScreen(controller: _wheelController, settings: widget.settings),
    RidesScreen(key: _ridesKey, settings: widget.settings),
    MapScreen(settings: widget.settings),
    ProfileScreen(settings: widget.settings, controller: _wheelController),
    SettingsScreen(settings: widget.settings, controller: _wheelController),
  ];

  static const _tabs = [
    TabItem(Icons.bluetooth, Icons.bluetooth_connected, 'Dispositivos'),
    TabItem(Icons.route_outlined, Icons.route, 'Viajes'),
    TabItem(Icons.map_outlined, Icons.map, 'Mapa'),
    TabItem(Icons.person_outline, Icons.person, 'Perfil'),
    TabItem(Icons.settings_outlined, Icons.settings, 'Configuración'),
  ];

  @override
  void dispose() {
    if (widget.controller == null) _wheelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackground(
        child: Stack(
          children: [
            IndexedStack(index: _index, children: _screens),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: FloatingTabBar(
                items: _tabs,
                index: _index,
                onSelected: (i) {
                  setState(() => _index = i);
                  // Al entrar a Viajes, recarga el historial.
                  if (i == 1) _ridesKey.currentState?.reload();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
