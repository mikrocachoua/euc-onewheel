# EUC OneWheel — app nativa (v1)

EUC OneWheel es un producto original: la app completa y mejorada para
salir a rodar en monociclo eléctrico, con la identidad visual de Mikro:
logo rojo oficial e interfaz oscura con acentos rojos (#E0231C).

## Qué incluye esta v1 (lo que ya funciona de verdad)

- **GPS 100 % real** (pestaña **Rodar**): pide permiso de ubicación, te
  centra en el mapa (OpenStreetMap), y al pulsar *Iniciar rodada* graba tu
  ruta en vivo: dibuja el recorrido en rojo sobre el mapa y muestra
  distancia, tiempo, velocidad actual, media y máxima mientras ruedas.
  Botones de **Pausar / Reanudar / Terminar**.
- **Resumen completo de la rodada** al terminar: distancia total, duración,
  velocidad media y máxima y desnivel estimado (con las altitudes del
  GPS), con botón **Compartir** para mandar el resumen en texto.
- **Historial** (pestaña **Historial**): las rodadas se guardan en el
  teléfono (archivo JSON en los datos de la app). Al tocar una rodada se
  ve su mapa con la ruta y todas sus cifras; también se puede **borrar**.
- **Panel** (pestaña **Panel**): la pantalla principal con el panel de
  telemetría más completo — velocímetro grande en rojo y tarjetas de
  batería, voltaje, potencia y temperatura.
- **Rueda** (pestaña **Rueda**): la sección de **marcas compatibles**
  (InMotion, KingSong, Begode/Gotway, Veteran/LeaperKim y Ninebot), la
  sección **Controles de la rueda** con su diseño definitivo (luces,
  tilt-back, alarmas, modo de pedales, calibración y bloqueo — visibles
  pero deshabilitados hasta conectar una rueda) y el «Acerca de» con tu
  logo. La app es abierta: no está amarrada a una marca ni a un modelo.

## Qué queda para la fase 2 (honestidad ante todo)

En la v1 el Panel muestra la telemetría en estado «—», la tarjeta dice
«Sin rueda conectada» y los controles de la rueda se ven completos pero
deshabilitados: es el diseño definitivo esperando la conexión. La fase
2 es el Bluetooth real, en tres capas:

- **a) Detección automática.** Escaneo Bluetooth LE: la app identifica
  la marca y el modelo de la rueda por el nombre y los servicios que
  anuncia al aire, sin que tengas que configurar nada a mano.
- **b) Lectura de telemetría.** Cada marca habla su propio protocolo;
  la fase 2 lo implementa marca por marca para llenar el Panel con
  datos en vivo: velocidad, batería, voltaje, corriente, potencia,
  temperaturas e inclinación.
- **c) Comandos de control.** La app no solo leerá: también podrá
  **operar** la rueda desde el teléfono, únicamente con los comandos
  que el protocolo de cada marca y modelo exponga — encender/apagar
  las luces, ajustar la velocidad de tilt-back, las alarmas de
  velocidad, el modo y la sensibilidad de pedales (ride mode), la
  calibración y el bloqueo del motor. Lo que un modelo no exponga
  quedará deshabilitado en su caso. Todos los comandos de control
  quedan sujetos a la Regla de seguridad (sección siguiente).
- Publicar fotos/videos de la app a redes sociales (el resumen de texto
  ya se puede compartir con el botón Compartir del sistema).

## Regla de seguridad (obligatoria, sin excepción)

Principio de diseño de la fase 2: **ninguna función de la app puede
poner en riesgo al equipo en uso. La rueda NUNCA debe poder apagarse
desde la app mientras está en movimiento.**

Clasificación de comandos de la fase 2:

- **Permitidos en movimiento:** solo la lectura de telemetría y las
  funciones inocuas (por ejemplo, encender/apagar las luces).
- **Solo con la rueda detenida (velocidad = 0) y con confirmación
  explícita en pantalla:** apagar la rueda, bloquear el motor, la
  calibración y cualquier ajuste que afecte el comportamiento en
  marcha (velocidad de tilt-back, alarmas de velocidad y modo de
  pedales).
- **Candado por software en la app:** si la rueda reporta velocidad
  mayor a 0, la app bloquea esos comandos por su cuenta, además del
  candado que ya traiga el firmware de la rueda.
- **Sin acciones por desconexión:** la pérdida de la conexión
  Bluetooth nunca debe disparar ninguna acción en la rueda.

En la v1 esta regla ya se refleja en la interfaz: los controles
peligrosos de la sección «Controles de la rueda» (apagar, bloqueo del
motor, calibración, tilt-back, alarmas y modo de pedales) llevan la
leyenda «Solo con la rueda detenida».

## Estructura del proyecto

```
lib/
  main.dart                  → arranque y navegación inferior (4 pestañas)
  theme.dart                 → tema Material 3 oscuro, rojo #E0231C
  models/
    ride.dart                → modelo de rodada y punto GPS (JSON)
  services/
    ride_store.dart          → guardar/leer/borrar rodadas en el teléfono
  screens/
    panel_screen.dart        → Panel (telemetría, preparada para fase 2)
    ride_screen.dart         → Rodar (GPS real y grabación)
    history_screen.dart      → Historial de rodadas
    ride_detail_screen.dart  → Detalle de una rodada (mapa + cifras)
    wheel_screen.dart        → Rueda (marcas compatibles) y Acerca de
  utils/
    format.dart              → formatos de fecha y duración
assets/
  logo.jpg                   → logo oficial (en Panel, Rueda y Acerca de)
  icon.png                   → logo cuadrado para el ícono de la app
codemagic.yaml               → compilación en la nube (iOS → TestFlight)
```

Tecnologías: Flutter (Material 3), `geolocator` (GPS), `flutter_map` +
`latlong2` (mapas OpenStreetMap), `path_provider` (guardado local),
`share_plus` (compartir), `intl` (fechas).

## Cómo se compila en la nube (Codemagic)

No necesitas una Mac: Codemagic compila la app de iOS en sus servidores.
Todo el proceso está descrito en el archivo **`codemagic.yaml`** de esta
misma carpeta: es el guion que Codemagic sigue paso a paso (descargar
dependencias, firmar la app automáticamente con la clave de API de App
Store Connect, compilar el `.ipa` en Release y subirlo a TestFlight).
El YAML no guarda ninguna contraseña: las credenciales viven cifradas
en Codemagic.

El flujo se llama **«iOS a TestFlight»** y, una vez configurado (pasos
del día de la instalación, abajo), se dispara a mano desde el panel de
Codemagic con «Start new build». Al terminar, la app aparece sola en
TestFlight.

Datos reales de esta app (los que pide Apple, sin inventar):

- **Bundle id de iOS:** `com.euconewheel.eucOnewheel` — ojo, lleva
  mayúscula en «Onewheel»; debe escribirse idéntico en todas partes.
- **Nombre visible:** EUC OneWheel.
- En Codemagic, la integración con App Store Connect debe llamarse
  **`EUC OneWheel ASC`** (es el nombre escrito en el `codemagic.yaml`;
  si se crea con otro nombre, hay que cambiarlo también ahí) y el
  grupo de variables **`credenciales_app_store`** debe traer la clave
  de API: `APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_KEY_IDENTIFIER`
  y `APP_STORE_CONNECT_PRIVATE_KEY` (el contenido del archivo `.p8`,
  marcado como «Secure»). Los comentarios al inicio del `codemagic.yaml`
  explican cada bloque.

## El día de la instalación (pasos en orden)

1. **Membresía Apple Developer activa (US$99/año).** Es un cobro de
   Apple y se hace con tu Apple ID en developer.apple.com. Si ya tienes
   cuenta de desarrollador pero la membresía venció, solo hay que
   renovarla. Sin la membresía activa, Apple no deja firmar la app ni
   subirla a TestFlight. Actívala el mismo día de la instalación, no
   antes, para que el año empiece a correr con la app ya en tu teléfono.
2. **Crear la app en App Store Connect.** Entra a
   appstoreconnect.apple.com → «Mis apps» → «+» → «Nueva app»:
   plataforma iOS, nombre **EUC OneWheel**, idioma principal español,
   **bundle id `com.euconewheel.eucOnewheel`** (se elige de la lista;
   si no aparece, se registra primero en developer.apple.com →
   Certificates, Identifiers & Profiles → Identifiers) y un SKU
   cualquiera, por ejemplo `euc-onewheel-001`. De paso, en «Usuarios y
   acceso» → «Claves», crea la clave de API (rol App Manager) y guarda
   el archivo `.p8`, el Issuer ID y el Key ID: son los datos de los
   pasos siguientes.
3. **Cuenta en Codemagic y conectar el proyecto.** Sube esta carpeta a
   un repositorio de GitHub (privado está bien), crea la cuenta en
   codemagic.io y conecta el repositorio: Codemagic detecta el
   `codemagic.yaml` y el flujo «iOS a TestFlight». Después crea:
   - la **integración** con App Store Connect llamada
     `EUC OneWheel ASC`, usando la clave de API del paso 2;
   - el **grupo de variables** `credenciales_app_store` con
     `APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_KEY_IDENTIFIER`
     y `APP_STORE_CONNECT_PRIVATE_KEY` (esta última como «Secure»).
4. **Disparar el flujo en Codemagic.** Pulsa «Start new build» y elige
   «iOS a TestFlight». Codemagic compila, firma y sube la app a
   TestFlight solo; tarda unos minutos y Apple puede tardar un rato
   más en procesar la versión antes de mostrarla.
5. **Instalar desde TestFlight en tu iPhone.** Instala **TestFlight**
   (la app oficial y gratuita de Apple), acepta la invitación de
   prueba de EUC OneWheel y descárgala. Listo: el ícono rojo queda en
   tu pantalla de inicio como cualquier app, con tu logo y tu nombre.
   Las mejoras futuras llegan como actualizaciones por el mismo camino.
6. (Opcional, después) Publicarla en la App Store para todo el público:
   Apple revisa cada app antes de publicarla (normalmente 1–2 días).

---
*Versión del proyecto: 1.0.0 · Hecha con Flutter · La telemetría
Bluetooth es fase 2; el GPS de esta v1 es real.*
