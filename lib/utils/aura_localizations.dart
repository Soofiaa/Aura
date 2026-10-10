import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// Idioma unico de la app: la interfaz es solo en espanol y sus textos
/// estan escritos a mano.
const Locale auraLocale = Locale('es');

/// Para los MaterialApp de la app (main.dart).
const List<Locale> auraSupportedLocales = [auraLocale];

/// Carga siempre las localizaciones oficiales de Flutter en espanol
/// (flutter_localizations, del SDK, sin red), sea cual sea el idioma del
/// telefono o del test: selector de fecha, "Atras", pestanas ("Pestaña 1
/// de 4"), "Cerrar", fondo de hojas y dialogos, etc. Antes la app usaba
/// los textos en ingles de Material y solo traducia "Cerrar".
class _SpanishDelegate<T> extends LocalizationsDelegate<T> {
  const _SpanishDelegate(this._official);

  final LocalizationsDelegate<T> _official;

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<T> load(Locale locale) => _official.load(auraLocale);

  @override
  bool shouldReload(_SpanishDelegate<T> old) => false;

  @override
  Type get type => T;
}

/// Delegados de los MaterialApp de la app (main.dart). MaterialApp agrega
/// despues los de por defecto; para cada tipo gana el primero.
const List<LocalizationsDelegate<dynamic>> auraLocalizationsDelegates = [
  _SpanishDelegate<MaterialLocalizations>(GlobalMaterialLocalizations.delegate),
  _SpanishDelegate<WidgetsLocalizations>(GlobalWidgetsLocalizations.delegate),
  _SpanishDelegate<CupertinoLocalizations>(
      GlobalCupertinoLocalizations.delegate),
];
