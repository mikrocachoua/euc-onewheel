import 'package:flutter/material.dart';

import 'screens/history_screen.dart';
import 'screens/panel_screen.dart';
import 'screens/ride_screen.dart';
import 'screens/wheel_screen.dart';
import 'theme.dart';

void main() {
  runApp(const EucOneWheelApp());
}

/// EUC OneWheel — app nativa v1.
/// Fase 1: GPS real para grabar rodadas + historial.
/// Fase 2 (preparada en el Panel): Bluetooth real con la rueda.
class EucOneWheelApp extends StatelessWidget {
  const EucOneWheelApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EUC OneWheel',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  final _historyKey = GlobalKey<HistoryScreenState>();

  late final List<Widget> _screens = [
    const PanelScreen(),
    const RideScreen(),
    HistoryScreen(key: _historyKey),
    const WheelScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) {
          setState(() => _index = i);
          // Al entrar al historial, recarga las rodadas guardadas.
          if (i == 2) _historyKey.currentState?.reload();
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Panel',
          ),
          NavigationDestination(
            icon: Icon(Icons.route_outlined),
            selectedIcon: Icon(Icons.route),
            label: 'Rodar',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: 'Historial',
          ),
          NavigationDestination(
            icon: Icon(Icons.electric_bolt_outlined),
            selectedIcon: Icon(Icons.electric_bolt),
            label: 'Rueda',
          ),
        ],
      ),
    );
  }
}
