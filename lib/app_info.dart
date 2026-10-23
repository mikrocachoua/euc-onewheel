import 'package:package_info_plus/package_info_plus.dart';

/// Datos fijos de la app EUC OneWheel (versión base 2).
///
/// La etiqueta de versión que ve el usuario se lee del propio paquete
/// instalado con [loadVersionLabel]: así nunca se queda atrás del
/// número de build real (en la build #7 la app seguía anunciando
/// «build 6» porque esta constante no se actualizó a mano). Las
/// constantes quedan solo como respaldo.
const String appVersion = '2.0.0';
const String appBuild = '8';

/// Nombre visible de la app.
const String appName = 'EUC OneWheel';

/// Etiqueta «versión (build)» leída del paquete instalado; si el
/// sistema no responde, cae a las constantes de respaldo.
Future<String> loadVersionLabel() async {
  try {
    final info = await PackageInfo.fromPlatform();
    if (info.version.isNotEmpty) {
      return '${info.version} (build ${info.buildNumber})';
    }
  } catch (_) {
    // Sin paquete legible: se usa el respaldo.
  }
  return '$appVersion (build $appBuild)';
}
