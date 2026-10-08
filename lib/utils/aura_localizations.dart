import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Textos de Material que la app ve en espanol. La app no usa
/// flutter_localizations (la interfaz es solo en espanol y sus textos
/// estan escritos a mano), asi que Material usa sus textos en ingles por
/// defecto. Por ahora solo se cambia el de la "x" de cerrar (por ejemplo,
/// la del aviso de exito de la importacion), que el lector de pantalla
/// leeria "Close".
class AuraMaterialLocalizations extends DefaultMaterialLocalizations {
  const AuraMaterialLocalizations();

  @override
  String get closeButtonTooltip => 'Cerrar';
}

class _AuraMaterialLocalizationsDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const _AuraMaterialLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<MaterialLocalizations> load(Locale locale) =>
      SynchronousFuture<MaterialLocalizations>(
        const AuraMaterialLocalizations(),
      );

  @override
  bool shouldReload(_AuraMaterialLocalizationsDelegate old) => false;
}

/// Delegados de los MaterialApp de la app (main.dart). MaterialApp agrega
/// despues los de por defecto; para MaterialLocalizations gana este.
const List<LocalizationsDelegate<dynamic>> auraLocalizationsDelegates = [
  _AuraMaterialLocalizationsDelegate(),
];
