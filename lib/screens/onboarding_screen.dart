import 'package:flutter/material.dart';
import '../data/repositories/cycle_repository.dart';
import '../utils/aura_localizations.dart';
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

  List<Map<String, Object>> get _pages => [
    {
      "titulo": tr("Bienvenida a Aura", "Welcome to Aura"),
      "descripcion": tr(
      "Tu espacio personal para entender, registrar y cuidar tu ciclo menstrual.",
      "Your personal space to understand, track, and care for your menstrual cycle."),
      "icono": Icons.favorite_rounded,
    },
    {
      "titulo": tr("Registra tu bienestar", "Track your well-being"),
      "descripcion": tr(
      "Anota tus síntomas, emociones y observaciones día a día para conocerte mejor.",
      "Note your symptoms, feelings, and observations each day to get to know yourself better."),
      "icono": Icons.edit_note_rounded,
    },
    {
      "titulo": tr("Conoce tus patrones", "Discover your patterns"),
      "descripcion": tr(
      "Aura analiza tus ciclos y te ayuda a identificar tendencias en tu salud.",
      "Aura analyzes your cycles and helps you spot trends in your health."),
      "icono": Icons.insights_rounded,
    },
    // Solo la ven las instalaciones nuevas (el onboarding se muestra una
    // vez): a quien actualiza, se lo recuerda la tarjeta de Inicio.
    {
      "titulo": tr("Tus datos son tuyos", "Your data is yours"),
      "descripcion": tr(
      "Aura funciona sin internet y guarda todo solo en este teléfono. Para "
          "no perder tus registros si cambias o pierdes el teléfono, crea un "
          "respaldo de vez en cuando desde Ajustes.",
      "Aura works offline and keeps everything only on this phone. So you "
          "don't lose your logs if you change or lose your phone, create a "
          "backup from Settings every now and then."),
      "icono": Icons.lock_rounded,
    },
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// Doble toque en "Comenzar": sin esto, dos pushReplacement.
  bool _finalizando = false;

  void _finalizarOnboarding() async {
    if (_finalizando) return;
    _finalizando = true;
    try {
      await (widget.repository ?? cycleRepository).setOnboardingSeen(true);
    } catch (_) {
      // Se vuelve a mostrar la proxima vez; igual se entra a la app.
    }

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
                      ? tr("Comenzar", "Get started")
                      : tr("Siguiente", "Next"),
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
