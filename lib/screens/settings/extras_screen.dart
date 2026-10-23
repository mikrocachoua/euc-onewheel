import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../widgets/ui_kit.dart';
import 'settings_widgets.dart';

/// Una función del catálogo de extras: nombre, descripción, icono y
/// si ya está disponible en la app o sigue en desarrollo.
class _Extra {
  const _Extra(this.title, this.description, this.icon,
      {this.available = false});
  final String title;
  final String description;
  final IconData icon;
  final bool available;
}

/// Configuración → Tienda / Extras: catálogo estilo «Premium» de
/// EUC OneWheel. Aquí NO hay paywall: todo forma parte de la app; lo
/// que aún no está implementado se marca honestamente como
/// «En desarrollo», sin prometer fechas.
class ExtrasScreen extends StatelessWidget {
  const ExtrasScreen({super.key});

  static const _extras = <_Extra>[
    _Extra(
        'Alarmas',
        'Alarmas por velocidad, amperaje, potencia, temperatura y PWM',
        Icons.notifications_active_outlined,
        available: true),
    _Extra(
        'Gráficos',
        'Visualización de gráficos de tus viajes durante un período '
            'prolongado de hasta un año',
        Icons.show_chart),
    _Extra(
        'Grabador de video',
        'Grabación de video desde la cámara con métricas superpuestas',
        Icons.videocam_outlined),
    _Extra(
        'Panel personalizado',
        'Seleccionar indicadores para mostrar y ajustar el tamaño',
        Icons.dashboard_customize_outlined,
        available: true),
    _Extra(
        'Tema',
        'Posibilidad de aplicar temas a la app (oscuro deportivo y claro)',
        Icons.palette_outlined,
        available: true),
    _Extra(
        'Linterna automática',
        'Encender automáticamente la linterna del dispositivo al '
            'conducir después del atardecer',
        Icons.flashlight_on_outlined),
    _Extra(
        'Rastreador',
        'Registra la geolocalización durante el viaje. El tiempo de '
            'funcionamiento de tu dispositivo puede reducirse',
        Icons.location_on_outlined,
        available: true),
    _Extra(
        'Volumen automático',
        'El volumen de la música dependerá de la velocidad',
        Icons.music_note_outlined,
        available: true),
    _Extra('Beep personalizado', 'Reemplaza el pitido del dispositivo',
        Icons.graphic_eq,
        available: true),
    _Extra(
        'Sonido de motor',
        'AVAS con selección de presets, desarrollado para simular '
            'sonidos de motor según la velocidad',
        Icons.speaker_outlined,
        available: true),
    _Extra(
        'Live Activity',
        'Datos en vivo en la pantalla de bloqueo y la Dynamic Island',
        Icons.notifications_outlined),
    _Extra(
        'Estimación dinámica de kilometraje',
        'El kilometraje restante se calculará dinámicamente según el '
            'estilo de conducción reciente',
        Icons.battery_saver_outlined),
    _Extra('Exportación de viajes', 'Compartir viajes en CSV',
        Icons.file_download_outlined,
        available: true),
    _Extra(
        'Introducción',
        'Capacidad para desactivar la pantalla de inicio con consejos',
        Icons.phone_iphone_outlined,
        available: true),
    _Extra(
        'Nombre del dispositivo',
        'Posibilidad de cambiar el nombre de los dispositivos',
        Icons.badge_outlined,
        available: true),
    _Extra(
        'Integración avanzada de dispositivos portátiles',
        'Integración con lentes y accesorios portátiles compatibles',
        Icons.watch_outlined),
    _Extra(
        'Carga inteligente',
        'Controla la carga con un enchufe inteligente: programa el '
            'tope de carga y corta automáticamente al alcanzarlo',
        Icons.ev_station_outlined),
    _Extra(
        'Mapa de calor',
        'Tu mapa personal de calor con las zonas que más ruedas',
        Icons.local_fire_department_outlined),
    _Extra(
        'Gestos al rodar',
        'Acciones rápidas con gestos desde el reloj o el teléfono',
        Icons.gesture_outlined),
    _Extra(
        'Caja negra',
        'Registro detallado de cada rodada para diagnóstico y '
            'exportación completa',
        Icons.inventory_2_outlined),
    _Extra(
        'Clima en ruta',
        'Pronóstico y avisos de clima para planear tus rodadas',
        Icons.cloud_outlined),
    _Extra(
        'Estadísticas del piloto',
        'Tus cifras de rodador, récords personales y clasificación '
            'con la comunidad',
        Icons.leaderboard_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
      title: 'Tienda',
      children: [
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.diamond_outlined, color: safetyAmber, size: 30),
                  SizedBox(width: 10),
                  Text('EUC ONE WHEEL COMPLETO',
                      style:
                          TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Todas las funciones forman parte de la app: no hay '
                'muro de pago. Las marcadas como «En desarrollo» '
                'llegarán en fases posteriores.',
                style: TextStyle(color: subText, fontSize: 14),
              ),
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                decoration: BoxDecoration(
                  gradient: iconTileGradient(),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: funcBlue.withValues(alpha: 0.35)),
                ),
                child: const Text(
                  'Incluido',
                  style: TextStyle(
                    color: funcBlueLight,
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SectionHeader('Incluye'),
        for (final extra in _extras) ...[
          SurfaceCard(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                GlassIconTile(
                  icon: extra.icon,
                  size: 62,
                  iconSize: 30,
                  radius: 18,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(extra.title,
                                style: const TextStyle(
                                    fontSize: 16.5,
                                    fontWeight: FontWeight.w800)),
                          ),
                          if (!extra.available)
                            const PillBadge('En desarrollo'),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(extra.description,
                          style:
                              const TextStyle(color: subText, fontSize: 13.5)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}
