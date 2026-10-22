import 'package:euc_onewheel/screens/panel_screen.dart';
import 'package:euc_onewheel/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('El Panel muestra la marca y el estado sin rueda',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const PanelScreen()),
    );
    expect(find.text('EUC OneWheel'), findsWidgets);
    expect(find.text('Sin rueda conectada'), findsOneWidget);
    expect(find.text('VELOCIDAD'), findsOneWidget);
  });
}
