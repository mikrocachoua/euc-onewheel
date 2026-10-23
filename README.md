# EUC OneWheel — app nativa (base v2, build #6)

EUC OneWheel es un producto original: la app completa para salir a
rodar en monociclo eléctrico, con identidad visual propia — cluster
digital de auto eléctrico sobre grafito azulado profundo, paneles
de vidrio en capas con iridiscencia sutil, azul funcional
(#2E7CD6) como acento de trabajo, cifras en degradado blanco →
plata y el rojo de la marca (#E0231C) solo como luz dentro del
tubo del velocímetro y en alertas críticas — y compatibilidad con
las marcas principales de ruedas: **InMotion, KingSong,
Begode/Gotway, Veteran/LeaperKim y Ninebot**. Ninguna función está
amarrada a una marca ni a un modelo concretos; la app no se enfoca
en ningún monociclo en especial.

## La base v2 de un vistazo

Navegación flotante de **cinco secciones**, siempre a pantalla
completa:

- **Dispositivos** — escaneo y conexión Bluetooth reales con
  detección automática de marca y modelo (huella GATT + primera
  trama), lista «ENCONTRADO» de dispositivos cercanos y distintivo
  «Demo» cuando se explora sin rueda real.
- **Viajes** — historial de rodadas con tarjetas completas (fecha,
  distancia, duración, velocidad media y máxima, desnivel), detalle
  con mapa de la ruta, resumen completo, **gráfico de velocidad**,
  **exportación a CSV** y compartir por la hoja del sistema. La
  grabación GPS real de la v1 sigue intacta.
- **Mapa** — mapa a pantalla completa (OpenStreetMap) con tu
  ubicación en vivo, zoom +/−, botón de centrar, **filtros** (solo
  amigos / solo en línea / solo con el dispositivo conectado) y
  modo AR en preparación.
- **Perfil** — tarjeta del rodador con avatar, contadores sociales,
  valoración y la fila de su dispositivo con batería.
- **Configuración** — el menú completo:
  - **Aplicación**: panel personalizado (indicadores y tamaño,
    persistentes), **alarmas configurables** (velocidad, amperaje,
    potencia, temperatura y PWM), grabador de video (en desarrollo),
    volumen automático según la velocidad, **sonido de motor
    (AVAS)** con presets y volumen propio, grabación automática de
    GPS, apariencia (sistema imperial, °C/°F, bar/psi, tema oscuro
    deportivo / claro / negro puro / según el sistema), introducción, bloqueo de
    orientación, permanecer encendido, reset automático de ruta y
    datos de la app.
  - **Privacidad**: quién ve tu localización y tu perfil, precisión
    mejorada, ubicación en segundo plano y clasificaciones.
  - **Tienda / Extras**: el catálogo completo de funciones de la
    app, sin muro de pago; lo no implementado se marca «En
    desarrollo», sin prometer fechas.
  - **Integración**: comunidad, atajos de voz, relojes y radar
    Garmin, espejo Third Eye y ActiveLook (próximamente).
  - **Soporte**: canal de ayuda y **compartir registros** de la app.
  - **Acerca de**: versión, información, librerías y créditos.

## Panel de conducción

Medidor circular grande de velocidad: tubo de vidrio azulado con
la luz roja de la marca brillando dentro (borde oscuro → rojo vivo
→ núcleo casi blanco) y la cifra en degradado blanco → plata.
Indicadores personalizables (batería, voltaje, corriente, potencia,
temperatura, PWM, distancia del viaje y odómetro), avisos de
alarmas en pantalla con sonido, y los controles de la rueda
(luces, tilt-back, alarmas, modo de pedales, calibración, bloqueo
y apagado) visibles pero **deshabilitados** hasta que el adaptador
de cada marca implemente sus comandos. La ruta de los viajes y las
gráficas van en el degradado azul → cian de la identidad.

El **sonido de motor (AVAS)** tiene su lógica completa: apagado por
defecto, solo suena con rueda conectada y velocidad > 0, el tono
sigue a la velocidad según el preset (deportivo, clásico, eléctrico,
personalizado) y, si salta una alarma real, su volumen se agacha
casi a silencio para nunca taparla. El reproductor de audio nativo
se conecta en una fase posterior.

## Bluetooth multimarca (base existente, intacta)

- Detección por **huella GATT + olfateo de la primera trama** para
  todas las marcas principales.
- Adaptadores de telemetría implementados y probados con vectores
  de tramas reales para las **cinco marcas**: KingSong,
  Begode/Gotway, Veteran/LeaperKim (incluida la línea NOSFET),
  InMotion V2 (V11/V12/V13 y familia nueva) y Ninebot Z. Todos en
  modo **solo telemetría**: ningún adaptador envía comandos
  todavía; los controles saldrán únicamente por la compuerta de
  seguridad en su fase.
- Permisos de runtime de Android gestionados (Bluetooth en
  Android 12+, ubicación legada en versiones anteriores).

## Regla de seguridad (obligatoria, sin excepción)

**Ninguna función de la app puede poner en riesgo la rodada.** La
rueda NUNCA debe poder apagarse desde la app mientras está en
movimiento. Todos los comandos de control salen únicamente por la
**compuerta de seguridad** (`lib/services/ble/safety_gate.dart`):

- Comandos críticos (apagar, bloquear el motor, calibrar, tilt-back,
  alarmas de velocidad, modo de pedales, ángulo y modo transporte)
  solo con **velocidad = 0**, telemetría fresca (< 2 s) y
  **confirmación explícita** del usuario.
- Perder el enlace Bluetooth **nunca** dispara ninguna acción.
- Cada comando autorizado queda en el registro de auditoría.

## Publicación

La app se prueba de forma **privada por TestFlight** (pipeline de
Codemagic ya verificado con la v1). No se publica ni se envía a
revisión pública sin aprobación expresa.
