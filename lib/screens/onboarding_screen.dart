import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../data/database/hive_boxes.dart';
import 'home_screen.dart'; // reemplaza main_navigation.dart

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<Map<String, String>> _pages = [
    {
      "titulo": "Bienvenida a Aura 🌸",
      "descripcion":
      "Tu espacio personal para entender, registrar y cuidar tu ciclo menstrual.",
      "imagen": "assets/images/onboarding1.png"
    },
    {
      "titulo": "Registra tu bienestar 💕",
      "descripcion":
      "Anota tus síntomas, emociones y observaciones día a día para conocerte mejor.",
      "imagen": "assets/images/onboarding2.png"
    },
    {
      "titulo": "Conoce tus patrones 🌙",
      "descripcion":
      "Aura analiza tus ciclos y te ayuda a identificar tendencias en tu salud.",
      "imagen": "assets/images/onboarding3.png"
    },
  ];

  void _finalizarOnboarding() async {
    final box = HiveBoxes.getConfigBox(); // ✅ caja correcta
    await box.put('onboardingVisto', true);

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()), // ✅ pantalla real
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FA),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() => _currentPage = index);
                },
                itemCount: _pages.length,
                itemBuilder: (context, index) {
                  final page = _pages[index];
                  return Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Image.asset(
                          page["imagen"]!,
                          height: 250,
                          fit: BoxFit.contain,
                        ),
                        const SizedBox(height: 40),
                        Text(
                          page["titulo"]!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          page["descripcion"]!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _pages.length,
                    (index) => AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  height: 8,
                  width: _currentPage == index ? 20 : 8,
                  decoration: BoxDecoration(
                    color: _currentPage == index
                        ? const Color(0xFFA8D8EA)
                        : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ElevatedButton(
                onPressed: _currentPage == _pages.length - 1
                    ? _finalizarOnboarding
                    : () {
                  _pageController.nextPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFA8D8EA),
                  foregroundColor: Colors.black,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  _currentPage == _pages.length - 1
                      ? "Comenzar"
                      : "Siguiente",
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}
