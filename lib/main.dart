import 'package:flutter/material.dart';
import 'data/repositories/cycle_repository.dart';
import 'utils/notifications.dart';
import 'utils/colors.dart';
import 'screens/onboarding_screen.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await NotificationService.init();

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
          ? const HomeScreen()
          : const OnboardingScreen(),
    );
  }
}
