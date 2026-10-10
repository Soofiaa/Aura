import 'package:flutter/material.dart';
import '../data/repositories/cycle_repository.dart';
import 'main_navigation_screen.dart';

class OnboardingScreen extends StatefulWidget {
  /// Inyectables para tests. En la app real, [cycleRepository] y
  /// MainNavigationScreen.
  final CycleRepository? repository;
  final WidgetBuilder? nextScreen;

  const OnboardingScreen({super.key, this.repository, this.nextScreen});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<Map<String, Object>> _pages = [
    {
      "titulo": "Bienvenida a Aura 🌸",
      "descripcion":
      "Tu espacio personal para entender, registrar y cuidar tu ciclo menstrual.",
      "icono": Icons.favorite_rounded,
    },
    {
      "titulo": "Registra tu bienestar 💕",
      "descripcion":
      "Anota tus síntomas, emociones y observaciones día a día para conocerte mejor.",
      "icono": Icons.edit_note_rounded,
    },
    {
      "titulo": "Conoce tus patrones 🌙",
      "descripcion":
      "Aura analiza tus ciclos y te ayuda a identificar tendencias en tu salud.",
      "icono": Icons.insights_rounded,
    },
    // Solo la ven las instalaciones nuevas (el onboarding se muestra una
    // vez): a quien actualiza, se lo recuerda la tarjeta de Inicio.
    {
      "titulo": "Tus datos se quedan contigo 🔒",
      "descripcion":
      "Aura funciona sin internet y guarda todo solo en este teléfono. Para "
          "no perder tus registros si cambias o pierdes el teléfono, crea un "
          "respaldo de vez en cuando desde Ajustes.",
      "icono": Icons.lock_rounded,
    },
  ];

  void _finalizarOnboarding() async {
    await (widget.repository ?? cycleRepository).setOnboardingSeen(true);

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
          builder: widget.nextScreen ?? (_) => const MainNavigationScreen()),
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
                  // Desplazable: con letra grande o pantalla baja, el texto
                  // mas largo (la 4.a pagina) no entra; centrado si sobra.
                  return LayoutBuilder(
                    builder: (context, constraints) => SingleChildScrollView(
                      padding: const EdgeInsets.all(24.0),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: (constraints.maxHeight - 48)
                              .clamp(0, double.infinity),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              page["icono"] as IconData,
                              size: 140,
                              color: const Color(0xFFA8D8EA),
                            ),
                            const SizedBox(height: 40),
                            Text(
                              page["titulo"] as String,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              page["descripcion"] as String,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 16,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
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
