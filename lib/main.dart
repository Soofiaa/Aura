import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'data/notifications/notification_reconciler.dart';
import 'data/repositories/cycle_repository.dart';
import 'utils/colors.dart';
import 'screens/onboarding_screen.dart';
import 'screens/main_navigation_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // calendar_screen.dart y date_utils.dart formatean fechas en español
  // ('es_ES' / 'es'); sin esto, DateFormat/TableCalendar tiran
  // LocaleDataException la primera vez que se usan.
  await initializeDateFormatting();

  await notificationScheduler.init();
  // Suscripcion viva por el resto de la vida de la app: no se dispose()
  // nunca aca a proposito, igual que cycleRepository.
  notificationReconciler.start();

  final onboardingVisto = await cycleRepository.getOnboardingSeen();

  runApp(AuraApp(onboardingVisto: onboardingVisto));
}

class AuraApp extends StatelessWidget {
  final bool onboardingVisto;
  const AuraApp({super.key, required this.onboardingVisto});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aura',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
        scaffoldBackgroundColor: AppColors.background,
        useMaterial3: true,
      ),
      home: onboardingVisto
          ? const MainNavigationScreen()
          : const OnboardingScreen(),
    );
  }
}
