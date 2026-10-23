import 'package:flutter/material.dart';

import '../../state/app_settings.dart';
import '../../theme.dart';
import '../../widgets/ui_kit.dart';
import 'settings_widgets.dart';

/// Panel personalizado: el usuario elige qué indicadores se ven en
/// el panel de conducción y su tamaño. La elección persiste.
class PanelConfigScreen extends StatelessWidget {
  const PanelConfigScreen({super.key, required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final selected = settings.panelIndicators;
        return SettingsScaffold(
          title: 'Panel personalizado',
          children: [
            const SurfaceCard(
              child: Text(
                'Selecciona los indicadores que quieres ver en el '
                'panel de conducción y ajusta su tamaño. Tu elección '
                'se guarda automáticamente.',
                style: TextStyle(color: subText, fontSize: 14),
              ),
            ),
            const SizedBox(height: 16),
            const SectionHeader('Tamaño'),
            RadioGroup<PanelIndicatorSize>(
              groupValue: settings.panelSize,
              onChanged: (v) {
                if (v != null) settings.update((s) => s.panelSize = v);
              },
              child: SettingsGroup(
                children: [
                  for (final size in PanelIndicatorSize.values)
                    RadioListTile<PanelIndicatorSize>(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      title: Text(
                        size == PanelIndicatorSize.normal
                            ? 'Normal'
                            : 'Grande (cifras más visibles rodando)',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      value: size,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const SectionHeader('Indicadores'),
            SettingsGroup(
              children: [
                for (final indicator in PanelIndicator.values)
                  CheckboxListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    title: Text(
                      indicator.label,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    value: selected.contains(indicator),
                    onChanged: (on) {
                      settings.update((s) {
                        final list = [...s.panelIndicators];
                        if (on == true) {
                          if (!list.contains(indicator)) {
                            list.add(indicator);
                          }
                        } else {
                          // El panel nunca se queda vacío.
                          if (list.length > 1) list.remove(indicator);
                        }
                        s.panelIndicators = list;
                      });
                    },
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}
