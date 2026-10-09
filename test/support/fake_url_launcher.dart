import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

/// Doble de url_launcher para tests de widget: reemplaza la plataforma
/// (UrlLauncherPlatform.instance), asi que launchUrl de la app pasa por
/// aca sin canales nativos ni red. Registra cada pedido con su modo.
class FakeUrlLauncher extends UrlLauncherPlatform {
  /// Lo que devuelve launchUrl (false: ninguna app pudo abrirlo).
  bool result = true;

  /// Si no es null, launchUrl lo lanza (p.ej. una PlatformException).
  Object? error;

  final List<String> launchedUrls = [];
  final List<PreferredLaunchMode> launchedModes = [];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launchedUrls.add(url);
    launchedModes.add(options.mode);
    final e = error;
    if (e != null) throw e;
    return result;
  }
}
