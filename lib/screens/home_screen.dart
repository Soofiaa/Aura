import 'dart:async';

import 'package:flutter/material.dart';
import '../data/database/app_database.dart' show DailyLogRow;
import '../data/notifications/notification_reconciler.dart';
import '../data/repositories/cycle_repository.dart';
import '../domain/cycle_predictor.dart';
import '../utils/date_utils.dart';
import '../utils/day_key.dart';
import 'add_cycle_screen.dart';
import '../utils/app_snackbar.dart';

class HomeScreen extends StatefulWidget {
  /// Permite inyectar un repositorio (ej. con base en memoria) en tests.
  /// En la app real se usa el singleton global [cycleRepository].
  final CycleRepository? repository;

  /// Reloj inyectable para tests (controla que dia es "hoy" y cuanto
  /// falta para la medianoche). En la app real, DateTime.now().
  final DateTime Function()? clock;

  /// Inyectable para tests (evita tocar el scheduler real de
  /// notificaciones, que usa canales de plataforma). En la app real, el
  /// singleton global [notificationReconciler].
  final NotificationReconciler? reconciler;

  const HomeScreen({super.key, this.repository, this.clock, this.reconciler});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late final CycleRepository _repository = widget.repository ?? cycleRepository;
  late final NotificationReconciler _reconciler =
      widget.reconciler ?? notificationReconciler;
  DateTime Function() get _clock => widget.clock ?? DateTime.now;

  // Stream en vez de un Future cargado una vez en initState: se vuelve a
  // calcular solo cuando cambia algo en daily_logs (registrar un dia,
  // marcar desde el calendario, borrar datos) o en los ajustes (duracion
  // habitual del periodo), sin importar si volvimos aca con push/pop o
  // cambiando de pestana en la NavigationBar. El motor (predictCycle)
  // sigue siendo puro: "hoy" lo decide esta pantalla (_today, mas abajo),
  // no el stream ni el repositorio.
  late final Stream<PredictionInputs> _inputsStream =
      _repository.watchPredictionInputs();

  late String _today = DayKey.fromDate(_clock());
  late Stream<DailyLogRow?> _todayStream = _repository.watchDay(_today);
  Timer? _midnightTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleMidnightRefresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _midnightTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshToday();
      _reconciler.onAppResumed();
    }
  }

  /// Recalcula que dia es "hoy" (sin tocar la base de datos) y vuelve a
  /// programar el timer de medianoche. Se llama al volver la app a
  /// primer plano y cuando ese timer dispara.
  void _refreshToday() {
    final current = DayKey.fromDate(_clock());
    if (current != _today) {
      setState(() {
        _today = current;
        _todayStream = _repository.watchDay(_today);
      });
    }
    _scheduleMidnightRefresh();
  }

  void _scheduleMidnightRefresh() {
    _midnightTimer?.cancel();
    final now = _clock();
    final nextMidnight = DateTime(now.year, now.month, now.day + 1);
    _midnightTimer = Timer(nextMidnight.difference(now), _refreshToday);
  }

  String _formatDate(String dayKey) =>
      DateUtilsAura.formatFechaCorta(DayKey.toUtcAnchor(dayKey));

  /// "Si"/"No" de la pregunta rapida. Usa setPeriodDayExplicitly (no
  /// upsertDay): esta SI es una declaracion directa y dedicada, a
  /// diferencia del interruptor del formulario general.
  Future<void> _responderPeriodoHoy(bool isPeriodDay) async {
    final date = _today;
    final previous = await _repository.getDay(date);
    await _repository.setPeriodDayExplicitly(date, isPeriodDay: isPeriodDay);

    if (!mounted) return;
    showAppSnackBar(
      context,
      SnackBar(
        content: Text(
          isPeriodDay
              ? 'Día marcado como sangrado.'
              : 'Registrado: hoy no hubo sangrado.',
        ),
        persist: false,
        duration: undoSnackBarDuration,
        action: SnackBarAction(
          label: 'Deshacer',
          onPressed: () => _repository.restoreDaySnapshot(date, previous),
        ),
      ),
    );
  }

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
      body: StreamBuilder<PredictionInputs>(
        stream: _inputsStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final inputs = snapshot.data;
          final prediction = predictCycle(
            cycles: inputs?.cycles ?? const [],
            today: _today,
            config: inputs?.config ?? const PredictionConfig(),
          );
          return SingleChildScrollView(
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
                _buildPredictionCard(prediction),
                StreamBuilder<DailyLogRow?>(
                  stream: _todayStream,
                  builder: (context, todaySnapshot) {
                    final card = _buildPeriodCheckCard(
                      prediction,
                      todaySnapshot.data,
                    );
                    if (card == null) return const SizedBox.shrink();
                    return Column(children: [
                      const SizedBox(height: 12),
                      card,
                    ]);
                  },
                ),
                const SizedBox(height: 12),
                _buildDisclaimer(),
                const SizedBox(height: 30),

                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AddCycleScreen()),
                    );
                  },
                  icon: const Icon(Icons.add),
                  label: const Text("Registrar día"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFAD4D8),
                    foregroundColor: Colors.black,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          );
        },
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

  Widget _buildPredictionCard(CyclePrediction? prediction) {
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

  /// Null si no corresponde mostrarla: solo aplica en fase menstrual y
  /// cuando hoy todavia no tiene una respuesta (ni is_period_day=true, ni
  /// una negacion explicita ya registrada) -- si no, se preguntaria lo
  /// mismo una y otra vez el mismo dia.
  Widget? _buildPeriodCheckCard(CyclePrediction? prediction, DailyLogRow? today) {
    if (prediction is! ActivePrediction) return null;
    if (prediction.currentPhase != CyclePhase.menstrual) return null;

    final yaRespondida = today != null &&
        (today.isPeriodDay || (!today.isPeriodDay && today.periodDayExplicit));
    if (yaRespondida) return null;

    return _buildCardShell(children: [
      const Text(
        "¿Sigue tu período hoy?",
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 12),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          ElevatedButton(
            onPressed: () => _responderPeriodoHoy(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFA8D8EA),
              foregroundColor: Colors.black,
            ),
            child: const Text("Sí"),
          ),
          OutlinedButton(
            onPressed: () => _responderPeriodoHoy(false),
            child: const Text("No"),
          ),
        ],
      ),
    ]);
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

}
