import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'data/database/hive_boxes.dart';
import 'utils/notifications.dart';
import 'utils/color.dart';
import 'screens/onboarding_screen.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Hive.initFlutter();
  await NotificationService.init();

  await Hive.openBox(HiveBoxes.diasMenstruacion);
  await Hive.openBox(HiveBoxes.ciclos);
  await Hive.openBox(HiveBoxes.configuracion);

  final configBox = HiveBoxes.getConfigBox();
  final bool onboardingVisto = configBox.get('onboardingVisto', defaultValue: false);

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
