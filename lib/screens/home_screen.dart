import 'package:flutter/material.dart';
import '../data/repositories/cycle_repository.dart';
import '../domain/cycle_predictor.dart';
import '../utils/date_utils.dart';
import '../utils/day_key.dart';

class HomeScreen extends StatefulWidget {
  /// Permite inyectar un repositorio (ej. con base en memoria) en tests.
  /// En la app real se usa el singleton global [cycleRepository].
  final CycleRepository? repository;

  const HomeScreen({super.key, this.repository});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final CycleRepository _repository = widget.repository ?? cycleRepository;

  bool _loading = true;
  CyclePrediction? _prediction;

  @override
  void initState() {
    super.initState();
    _cargarPrediccion();
  }

  Future<void> _cargarPrediccion() async {
    final prediction = await _repository.getPrediction();
    if (!mounted) return;
    setState(() {
      _prediction = prediction;
      _loading = false;
    });
  }

  String _formatDate(String dayKey) =>
      DateUtilsAura.formatFechaCorta(DayKey.toUtcAnchor(dayKey));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Aura 🌸',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFFA8D8EA),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
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
                  _buildPredictionCard(),
                  const SizedBox(height: 12),
                  _buildDisclaimer(),
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

  Widget _buildCardShell({required List<Widget> children}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }

  Widget _buildPredictionCard() {
    final prediction = _prediction;
    if (prediction == null) {
      return _buildCardShell(children: [
        const Icon(Icons.favorite_border, color: Colors.grey, size: 50),
        const SizedBox(height: 10),
        const Text(
          "Aún no hay datos suficientes",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        const Text(
          "Registra tu primer día para ver una predicción de tu ciclo.",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Colors.grey),
        ),
      ]);
    }

    return switch (prediction) {
      StaleDataPrediction() => _buildStaleCard(prediction),
      ActivePrediction() => _buildActiveCard(prediction),
    };
  }

  Widget _buildStaleCard(StaleDataPrediction p) {
    return _buildCardShell(children: [
      const Icon(Icons.history, color: Colors.grey, size: 50),
      const SizedBox(height: 10),
      const Text(
        "Hace tiempo que no registras...",
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 8),
      Text(
        "Tu último registro fue el ${_formatDate(p.lastPeriodStartDate)} "
        "(hace ${p.daysSinceLastPeriodStart} días). "
        "Registra un nuevo día para volver a ver una predicción.",
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 14, color: Colors.grey),
      ),
    ]);
  }

  Widget _buildActiveCard(ActivePrediction p) {
    return _buildCardShell(children: [
      if (p.isPeriodLate) _buildLateBanner(p),
      const Icon(Icons.favorite, color: Colors.pinkAccent, size: 50),
      const SizedBox(height: 10),
      Text(
        p.currentPhase.label,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 15),
      Text(
        "Próximo período: ${_formatDate(p.nextPeriodEarliestDate)} - "
        "${_formatDate(p.nextPeriodLatestDate)}",
        style: const TextStyle(fontSize: 16),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 4),
      Text(
        "Estimado: ${_formatDate(p.nextPeriodExpectedDate)}",
        style: TextStyle(fontSize: 13, color: Colors.grey[700]),
      ),
      const SizedBox(height: 15),
      Text(
        "Ovulación estimada: ${_formatDate(p.estimatedOvulationDate)}",
        style: const TextStyle(fontSize: 15),
      ),
      const SizedBox(height: 10),
      _buildFertileWindow(p),
      const SizedBox(height: 15),
      _buildConfidenceBadge(p),
    ]);
  }

  Widget _buildLateBanner(ActivePrediction p) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        "Período atrasado por ${p.daysLate} día${p.daysLate == 1 ? '' : 's'}",
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildFertileWindow(ActivePrediction p) {
    final isLowConfidence = p.confidence == PredictionConfidence.low;
    return Opacity(
      opacity: isLowConfidence ? 0.5 : 1.0,
      child: Column(
        children: [
          Text(
            "Días de mayor probabilidad de fertilidad (estimación):\n"
            "${_formatDate(p.fertileWindowStartDate)} - ${_formatDate(p.fertileWindowEndDate)}",
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14),
          ),
          if (isLowConfidence)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                "Confianza baja: esta ventana puede no ser precisa.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.orange,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildConfidenceBadge(ActivePrediction p) {
    final color = switch (p.confidence) {
      PredictionConfidence.low => Colors.orange,
      PredictionConfidence.medium => Colors.blueGrey,
      PredictionConfidence.high => Colors.green,
    };
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            "Confianza: ${p.confidence.label}",
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
        ),
        if (p.confidenceReasons.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              p.confidenceReasons.join(' '),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
          ),
      ],
    );
  }

  Widget _buildDisclaimer() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 10),
      child: Text(
        "Esta es una estimación, no un método anticonceptivo.",
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12,
          color: Colors.grey,
          fontStyle: FontStyle.italic,
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
