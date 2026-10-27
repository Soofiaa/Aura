import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// Idiomas de la app. Los textos estan escritos a mano en cada pantalla
/// con [tr]; no hay archivos de traduccion.
const List<Locale> auraSupportedLocales = [Locale('es'), Locale('en')];

/// Fija el idioma ('es' o 'en') sin mirar el telefono. Lo usan los tests
/// (test/flutter_test_config.dart lo pone en 'es').
String? auraLanguageOverride;

/// 'en' si el primer idioma soportado de la lista del telefono es ingles;
/// si no, 'es' (tambien cuando el telefono no tiene ninguno de los dos).
// shortcut: se lee en cada build; si la usuaria cambia el idioma con la
// app abierta, las pantallas que no se reconstruyen siguen en el anterior
// hasta reabrirla.
String get auraLanguage =>
    auraLanguageOverride ??
    // Via el binding (no PlatformDispatcher.instance) para que los tests
    // puedan simular el idioma del telefono.
    WidgetsBinding.instance.platformDispatcher.locales
        .map((l) => l.languageCode)
        .firstWhere((c) => c == 'es' || c == 'en', orElse: () => 'es');

bool get auraIsEnglish => auraLanguage == 'en';

/// Locale de la app, para MaterialApp y DateFormat.
Locale get auraLocale => Locale(auraLanguage);

/// El texto en el idioma de la app.
String tr(String es, String en) => auraIsEnglish ? en : es;

/// Carga las localizaciones oficiales de Flutter (flutter_localizations,
/// del SDK, sin red) en el idioma de la app, pida lo que pida el
/// MaterialApp: selector de fecha, "Atras", pestanas, "Cerrar", etc. Asi
/// los textos de Material nunca salen en otro idioma que los de la app.
class _AuraDelegate<T> extends LocalizationsDelegate<T> {
  const _AuraDelegate(this._official);

  final LocalizationsDelegate<T> _official;

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<T> load(Locale locale) => _official.load(auraLocale);

  @override
  bool shouldReload(_AuraDelegate<T> old) => false;

  @override
  Type get type => T;
}

/// Delegados de los MaterialApp de la app (main.dart). MaterialApp agrega
/// despues los de por defecto; para cada tipo gana el primero.
const List<LocalizationsDelegate<dynamic>> auraLocalizationsDelegates = [
  _AuraDelegate<MaterialLocalizations>(GlobalMaterialLocalizations.delegate),
  _AuraDelegate<WidgetsLocalizations>(GlobalWidgetsLocalizations.delegate),
  _AuraDelegate<CupertinoLocalizations>(GlobalCupertinoLocalizations.delegate),
];
