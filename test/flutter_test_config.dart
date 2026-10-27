import 'dart:async';

import 'package:aura/utils/aura_localizations.dart';

/// Corre antes de cada archivo de test: los tests verifican los textos en
/// espanol, sea cual sea el idioma de la maquina. Los tests del ingles
/// cambian auraLanguageOverride y lo restauran.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  auraLanguageOverride = 'es';
  await testMain();
}
