import 'package:flutter/material.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Simulación temporal (luego vendrá de Hive)
  String? ultimoInicio = "No registrado";
  int diasCiclo = 28;
  int duracionMenstruacion = 5;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Aura 🌸',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFFA8D8EA), // Celeste pastel
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 10),
            const Text(
              "Tu ciclo actual",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 20),

            // Tarjeta con info resumida
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  const Icon(Icons.favorite, color: Colors.pinkAccent, size: 50),
                  const SizedBox(height: 10),
                  Text(
                    "Último inicio del período:",
                    style: TextStyle(color: Colors.grey[700]),
                  ),
                  Text(
                    ultimoInicio ?? "No registrado",
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 15),
                  Text(
                    "Duración estimada del ciclo: $diasCiclo días",
                    style: const TextStyle(fontSize: 16),
                  ),
                  Text(
                    "Menstruación: $duracionMenstruacion días",
                    style: const TextStyle(fontSize: 16),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 30),

            // Botones principales
            ElevatedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Función próximamente')),
                );
              },
              icon: const Icon(Icons.add),
              label: const Text("Registrar nuevo ciclo"),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFAD4D8),
                foregroundColor: Colors.black,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 10),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildMenuButton(Icons.calendar_month, "Calendario"),
                _buildMenuButton(Icons.show_chart, "Estadísticas"),
                _buildMenuButton(Icons.settings, "Ajustes"),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuButton(IconData icon, String label) {
    return Column(
      children: [
        InkWell(
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Abrir $label')),
            );
          },
          borderRadius: BorderRadius.circular(50),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFA8D8EA),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, size: 28, color: Colors.white),
          ),
        ),
        const SizedBox(height: 5),
        Text(label),
      ],
    );
  }
}
