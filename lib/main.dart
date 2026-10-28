import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'app_startup.dart';
import 'data/backup/auto_drive_backup_service.dart';
import 'data/backup/backup_file_gateway.dart';
import 'data/backup/backup_service.dart';
import 'data/backup/plugin_backup_file_gateway.dart';
import 'data/device_settings_store.dart';
import 'data/home_widget_sync.dart';
import 'data/repositories/cycle_repository.dart';
import 'data/notifications/notification_reconciler.dart';
import 'utils/android_system.dart';
import 'utils/aura_localizations.dart';
import 'utils/colors.dart';
import 'screens/onboarding_screen.dart';
import 'screens/main_navigation_screen.dart';
import 'screens/update_error_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Android 15+ dibuja de borde a borde por defecto; esto lo aplica tambien
  // en versiones anteriores. Las pantallas deben respetar las inserciones
  // (SafeArea) para no quedar bajo la barra de estado o de navegacion.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // calendar_screen.dart, backup_section.dart, period_end_messages.dart
  // y period_start_sheet.dart formatean fechas en español ('es_ES' /
  // 'es'); sin esto, DateFormat/TableCalendar tiran
  // LocaleDataException la primera vez que se usan.
  await initializeDateFormatting();

  // Un fallo de las notificaciones (zona horaria, plugin) no debe dejar la
  // app en el splash: sin init, los avisos no se programan, pero la app
  // abre.
  try {
    await notificationScheduler.init();
  } catch (_) {}

  backupFileGateway = const PluginBackupFileGateway();

  // MainActivity arranca con FLAG_SECURE; aqui se aplica lo elegido en
  // Ajustes ("Ocultar Aura en Recientes") y cada cambio. Sin leer el
  // archivo se deja como esta (protegida).
  deviceSettingsStore.watch().listen(
        (ajustes) => androidSystem.setScreenProtection(ajustes.ocultarEnRecientes),
        onError: (Object _) {},
      );

  // La base se abre (y migra) ANTES que todo lo que la usa: si falla, se
  // muestra UpdateErrorScreen y no se programan notificaciones ni se
  // limpian temporales.
  final startup = AppStartup(onReady: () {
    // Suscripcion viva por el resto de la vida de la app: no se dispose()
    // nunca aca a proposito, igual que cycleRepository.
    notificationReconciler.start();
    startHomeWidgetSync(
      inputs: cycleRepository.watchPredictionInputs(),
      settings: deviceSettingsStore.watch(),
      system: androidSystem,
    );

    // Las copias temporales de un respaldo exportado se borran al abrir la
    // app (no al volver de la hoja de compartir: la app de destino puede
    // seguir leyendolas). Sin await: no debe demorar el arranque, y si
    // falla se reintenta en la proxima apertura o exportacion.
    unawaited(backupService.cleanTemporaryFiles().catchError((Object _) {}));

    // La copia previa a la migracion v4 se borra a los 30 dias.
    unawaited(backupService
        .deleteExpiredPreMigrationCopy()
        .catchError((Object _) {}));

    // Respaldo automatico en Drive (HU-09): al abrir la app se intenta el
    // del dia (si ya salio, no hace nada). El de reanudar esta en
    // _RespaldoAlReanudar y el de guardar, en add_cycle_screen.
    intentarRespaldoAutomatico();
  });

  // Con la base abierta y antes de runApp: el observer vive el resto de
  // la app, igual que notificationReconciler.
  WidgetsBinding.instance.addObserver(_RespaldoAlReanudar());

  final result = await startup.open();
  // El tema elegido antes del primer cuadro, para no parpadear en claro.
  final ajustes = await deviceSettingsStore
      .read()
      .catchError((Object _) => const DeviceSettings());

  runApp(AuraRoot(
      startup: startup, initialResult: result, initialTheme: ajustes.tema));
}

/// Tema de la app (publico para que los tests usen los mismos colores).
/// En el oscuro, la barra superior va del color de las tarjetas en vez del
/// celeste pastel.
ThemeData auraTheme([Brightness brightness = Brightness.light]) {
  final colores =
      brightness == Brightness.dark ? AuraColors.dark : AuraColors.light;
  return ThemeData(
    colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary, brightness: brightness),
    scaffoldBackgroundColor: colores.background,
    appBarTheme: AppBarTheme(
      backgroundColor: brightness == Brightness.dark
          ? colores.card
          : AppColors.primary,
    ),
    extensions: [colores],
    useMaterial3: true,
  );
}

/// HU-09: al volver a primer plano se intenta el respaldo automatico del
/// dia (si ya salio hoy, no hace nada; si falla, lo reintenta el proximo
/// trigger).
class _RespaldoAlReanudar with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) intentarRespaldoAutomatico();
  }
}

/// Raiz de la app: la app normal si la base abrio, o la pantalla de error
/// con "Reintentar" si no.
class AuraRoot extends StatefulWidget {
  const AuraRoot({
    super.key,
    required this.startup,
    required this.initialResult,
    this.initialTheme = ThemeMode.system,
  });

  final AppStartup startup;
  final StartupResult initialResult;
  final ThemeMode initialTheme;

  @override
  State<AuraRoot> createState() => _AuraRootState();
}

class _AuraRootState extends State<AuraRoot> {
  late StartupResult _result = widget.initialResult;
  bool _retrying = false;
  late ThemeMode _tema = widget.initialTheme;
  StreamSubscription<DeviceSettings>? _temaSub;

  @override
  void initState() {
    super.initState();
    // El tema sigue a Ajustes en vivo; si no se puede leer, queda el actual.
    _temaSub = deviceSettingsStore.watch().listen(
          (ajustes) => setState(() => _tema = ajustes.tema),
          onError: (Object _) {},
        );
  }

  @override
  void dispose() {
    _temaSub?.cancel();
    super.dispose();
  }

  Future<void> _retry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    final result = await widget.startup.open();
    if (!mounted) return;
    setState(() {
      _result = result;
      _retrying = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return switch (_result) {
      StartupReady(:final onboardingSeen) =>
        AuraApp(onboardingVisto: onboardingSeen, themeMode: _tema),
      StartupFailed(:final outOfSpace) => MaterialApp(
          title: 'Aura',
          debugShowCheckedModeBanner: false,
          theme: auraTheme(),
          darkTheme: auraTheme(Brightness.dark),
          themeMode: _tema,
          localizationsDelegates: auraLocalizationsDelegates,
          supportedLocales: auraSupportedLocales,
          locale: auraLocale,
          home: UpdateErrorScreen(
            outOfSpace: outOfSpace,
            retrying: _retrying,
            onRetry: _retry,
          ),
        ),
    };
  }
}

class AuraApp extends StatelessWidget {
  final bool onboardingVisto;
  final ThemeMode themeMode;
  const AuraApp(
      {super.key,
      required this.onboardingVisto,
      this.themeMode = ThemeMode.system});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aura',
      debugShowCheckedModeBanner: false,
      theme: auraTheme(),
      darkTheme: auraTheme(Brightness.dark),
      themeMode: themeMode,
      localizationsDelegates: auraLocalizationsDelegates,
      supportedLocales: auraSupportedLocales,
      locale: auraLocale,
      home: onboardingVisto
          ? const MainNavigationScreen()
          : const OnboardingScreen(),
    );
  }
}
