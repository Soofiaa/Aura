/// Version de la app, unica fuente para la pantalla de Ajustes y para el
/// campo `appVersion` de los respaldos. Debe coincidir con `version:` de
/// pubspec.yaml (nombre+build); test/utils/app_version_test.dart falla
/// si se desincronizan. Se evita package_info_plus para no sumar una
/// dependencia solo por esto.
const String appVersionName = '1.0.1';
const int appBuildNumber = 2;
