import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'app_startup.dart';
import 'data/backup/backup_file_gateway.dart';
import 'data/backup/backup_service.dart';
import 'data/backup/plugin_backup_file_gateway.dart';
import 'data/notifications/notification_reconciler.dart';
import 'utils/colors.dart';
import 'screens/onboarding_screen.dart';
import 'screens/main_navigation_screen.dart';
import 'screens/update_error_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // calendar_screen.dart y date_utils.dart formatean fechas en español
  // ('es_ES' / 'es'); sin esto, DateFormat/TableCalendar tiran
  // LocaleDataException la primera vez que se usan.
  await initializeDateFormatting();

  await notificationScheduler.init();

  backupFileGateway = const PluginBackupFileGateway();

  // La base se abre (y migra) ANTES que todo lo que la usa: si falla, se
  // muestra UpdateErrorScreen y no se programan notificaciones ni se
  // limpian temporales.
  final startup = AppStartup(onReady: () {
    // Suscripcion viva por el resto de la vida de la app: no se dispose()
    // nunca aca a proposito, igual que cycleRepository.
    notificationReconciler.start();

    // Las copias temporales de un respaldo exportado se borran al abrir la
    // app (no al volver de la hoja de compartir: la app de destino puede
    // seguir leyendolas). Sin await: no debe demorar el arranque, y si
    // falla se reintenta en la proxima apertura o exportacion.
    unawaited(backupService.cleanTemporaryFiles().catchError((Object _) {}));

    // La copia previa a la migracion v4 se borra a los 30 dias.
    unawaited(backupService
        .deleteExpiredPreMigrationCopy()
        .catchError((Object _) {}));
  });
  final result = await startup.open();

  runApp(AuraRoot(startup: startup, initialResult: result));
}

ThemeData _auraTheme() => ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
      scaffoldBackgroundColor: AppColors.background,
      useMaterial3: true,
    );

/// Raiz de la app: la app normal si la base abrio, o la pantalla de error
/// con "Reintentar" si no.
class AuraRoot extends StatefulWidget {
  const AuraRoot({
    super.key,
    required this.startup,
    required this.initialResult,
  });

  final AppStartup startup;
  final StartupResult initialResult;

  @override
  State<AuraRoot> createState() => _AuraRootState();
}

class _AuraRootState extends State<AuraRoot> {
  late StartupResult _result = widget.initialResult;
  bool _retrying = false;

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
        AuraApp(onboardingVisto: onboardingSeen),
      StartupFailed(:final outOfSpace) => MaterialApp(
          title: 'Aura',
          debugShowCheckedModeBanner: false,
          theme: _auraTheme(),
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
  const AuraApp({super.key, required this.onboardingVisto});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aura',
      debugShowCheckedModeBanner: false,
      theme: _auraTheme(),
      home: onboardingVisto
          ? const MainNavigationScreen()
          : const OnboardingScreen(),
    );
  }
}
