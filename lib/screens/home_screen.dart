import 'dart:async';

import 'package:flutter/material.dart';
import '../data/database/app_database.dart' show DailyLogRow;
import '../data/notifications/notification_reconciler.dart';
import '../data/repositories/cycle_repository.dart';
import '../domain/current_period.dart';
import '../domain/cycle_predictor.dart';
import '../domain/fertile_marks.dart';
import '../utils/colors.dart';
import '../utils/date_utils.dart';
import '../utils/day_key.dart';
import '../utils/period_end_messages.dart';
import '../widgets/period_start_sheet.dart';
import '../widgets/single_day_period_dialog.dart';
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

  void _showUndo(String message, DaysSnapshot snapshot) {
    showAppSnackBar(
      context,
      SnackBar(
        content: Text(message),
        persist: false,
        duration: undoSnackBarDuration,
        action: SnackBarAction(
          label: 'Deshacer',
          onPressed: () => _repository.restoreDaysSnapshot(snapshot),
        ),
      ),
    );
  }

  /// "Sigue": marca hoy como dia de sangrado. La tarjeta vuelve a
  /// preguntar manana.
  Future<void> _sigue() async {
    final result = await _repository.markPeriodDayWithSnapshot(_today,
        closeAtEnd: false, today: _today);
    if (!mounted || !result.changedAnything) return;
    _showUndo('Día marcado como sangrado.', result.snapshot);
  }

  /// "Termino hoy" y "Ya termino antes" (HU-03): cierra el periodo en
  /// [endDate] con closePeriod, que completa los dias sin registro
  /// (decision 3) y bloquea si hay dias marcados despues (decision 5).
  Future<void> _terminar(CurrentPeriod current, String endDate) async {
    // Decision 14: un periodo de 1 dia se confirma. Solo se pregunta si
    // ese dia es el unico marcado; si hay mas, closePeriod lo bloquea.
    if (needsSingleDayConfirmation(
            periodStart: current.startDate, endDate: endDate) &&
        current.lastMarkedDate == endDate) {
      final confirmado = await confirmSingleDayPeriod(context);
      if (!confirmado || !mounted) return;
    }

    final DaysSnapshot snapshot;
    try {
      snapshot = await _repository.closePeriod(current.startDate, endDate,
          today: _today);
    } on PeriodEndException catch (e) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        SnackBar(
            content:
                Text(periodEndProblemMessage(e.check, current.startDate))),
      );
      return;
    }
    if (!mounted) return;
    _showUndo(periodEndedMessage(endDate, _today), snapshot);
  }

  /// "Ya termino antes": selector entre el inicio del periodo y hoy,
  /// abierto en el ultimo dia marcado (decision 2).
  Future<void> _yaTermino(CurrentPeriod current) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.parse(current.lastMarkedDate),
      firstDate: DateTime.parse(current.startDate),
      lastDate: DateTime.parse(_today),
      currentDate: DateTime.parse(_today),
    );
    if (picked == null || !mounted) return;
    await _terminar(current, DayKey.fromDate(picked));
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
          final current = findCurrentPeriod(
              cycles: inputs?.cycles ?? const [], today: _today);
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
                _buildPredictionCard(prediction,
                    mostrarFertilidad: inputs?.showFertileWindow ?? true),
                StreamBuilder<DailyLogRow?>(
                  stream: _todayStream,
                  builder: (context, todaySnapshot) {
                    final card = _buildPeriodCheckCard(
                      prediction,
                      todaySnapshot.data,
                      current,
                      estimatePeriodLength(
                        cycles: inputs?.cycles ?? const [],
                        config: inputs?.config ?? const PredictionConfig(),
                      ).days,
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

                // Decision 1: "Me llego hoy" en Inicio solo cuando no hay
                // un periodo abierto en curso.
                if (current == null || current.isClosed) ...[
                  ElevatedButton.icon(
                    onPressed: () => showPeriodStartSheet(context,
                        repository: _repository, today: _today),
                    icon: const Icon(Icons.water_drop_outlined),
                    label: const Text('Me llegó hoy'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: AppColors.textPrimary,
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

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

  Widget _buildPredictionCard(CyclePrediction? prediction,
      {required bool mostrarFertilidad}) {
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
      ActivePrediction() =>
        _buildActiveCard(prediction, mostrarFertilidad: mostrarFertilidad),
    };
  }

  /// Null si no corresponde mostrarla. Se muestra solo con un periodo
  /// actual abierto (findCurrentPeriod), cuando hoy todavia no tiene una
  /// respuesta (ni is_period_day=true, ni una negacion explicita ya
  /// registrada; si no, se preguntaria lo mismo una y otra vez el mismo
  /// dia) y ademas en fase menstrual O con el ultimo dia marcado del
  /// periodo en ayer. La fase menstrual dura el promedio de P-1, no lo
  /// que dura este periodo; la regla de ayer mantiene la pregunta en un
  /// periodo mas largo que el promedio mientras se siga marcando. Un
  /// periodo cerrado no muestra la tarjeta.
  Widget? _buildPeriodCheckCard(
    CyclePrediction? prediction,
    DailyLogRow? today,
    CurrentPeriod? current,
    int estimatedPeriodLength,
  ) {
    if (prediction is! ActivePrediction) return null;
    if (current == null || current.isClosed) return null;
    final ultimoMarcadoAyer =
        current.lastMarkedDate == DayKey.addDays(_today, -1);
    if (prediction.currentPhase != CyclePhase.menstrual &&
        !ultimoMarcadoAyer) {
      return null;
    }

    final yaRespondida = today != null &&
        (today.isPeriodDay || (!today.isPeriodDay && today.periodDayExplicit));
    if (yaRespondida) return null;

    final dias = estimatedPeriodLength == 1
        ? '1 día'
        : '$estimatedPeriodLength días';
    const minimo = Size(48, 48);

    return _buildCardShell(children: [
      const Text(
        "¿Sigue tu período hoy?",
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 4),
      Text(
        'Día ${current.dayNumber} de tu período · duración estimada: $dias',
        style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 12),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          ElevatedButton(
            onPressed: _sigue,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.textPrimary,
              minimumSize: minimo,
            ),
            child: const Text("Sigue"),
          ),
          OutlinedButton(
            onPressed: () => _terminar(current, _today),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              minimumSize: minimo,
            ),
            child: const Text("Terminó hoy"),
          ),
        ],
      ),
      const SizedBox(height: 4),
      TextButton(
        onPressed: () => _yaTermino(current),
        style: TextButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          minimumSize: minimo,
        ),
        child: const Text(
          "Ya terminó antes",
          style: TextStyle(decoration: TextDecoration.underline),
        ),
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
        "Tu último período empezó el ${_formatDate(p.lastPeriodStartDate)} "
        "(hace ${p.daysSinceLastPeriodStart} días). "
        "Registra un nuevo día para volver a ver una predicción.",
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 14, color: Colors.grey),
      ),
    ]);
  }

  /// Tarjeta de prediccion (HU-05). La ovulacion, la ventana fertil y su
  /// aviso se muestran segun visibleFertileMarks, la misma regla que usa
  /// el Calendario: no con confianza baja (H5-1 A), ni con "Mostrar
  /// ovulacion y ventana fertil" apagado ([mostrarFertilidad], H5-3), ni
  /// con el periodo atrasado. Sin ellas tampoco se muestra la fase
  /// ovulatoria. Con confianza baja se explica por que en una linea gris
  /// (solo si el interruptor esta encendido). Con un periodo atrasado no
  /// se muestra ninguna fase: el ciclo real ya supero lo estimado. El
  /// predictor no cambia: esto es solo lo que se muestra.
  Widget _buildActiveCard(ActivePrediction p,
      {required bool mostrarFertilidad}) {
    final confianzaBaja = p.confidence == PredictionConfidence.low;
    final mostrarFertil =
        visibleFertileMarks(p, showFertileWindow: mostrarFertilidad) != null;
    final valorPorDefecto = p.completeCyclesConsidered <
        const PredictionConfig().minCompleteCyclesForMedium;
    final mostrarFase = !p.isPeriodLate &&
        !(!mostrarFertil && p.currentPhase == CyclePhase.ovulatoria);
    return _buildCardShell(children: [
      if (p.isPeriodLate) _buildLateBanner(p),
      const Icon(Icons.favorite, color: Colors.pinkAccent, size: 50),
      if (mostrarFase) ...[
        const SizedBox(height: 10),
        Text(
          p.currentPhase.label,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ],
      const SizedBox(height: 15),
      Text(
        "Próximo período: ${_formatDate(p.nextPeriodEarliestDate)} - "
        "${_formatDate(p.nextPeriodLatestDate)}",
        style: const TextStyle(fontSize: 16),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 4),
      Text(
        "Estimado: ${_formatDate(p.nextPeriodExpectedDate)}"
        "${valorPorDefecto ? ' (valor por defecto)' : ''}",
        style: TextStyle(fontSize: 13, color: Colors.grey[700]),
      ),
      const SizedBox(height: 15),
      if (mostrarFertilidad && confianzaBaja)
        Text(
          valorPorDefecto
              ? "Con más ciclos registrados podremos estimar tu ventana "
                  "fértil."
              : "Tus ciclos varían mucho, así que no mostramos tu ventana "
                  "fértil.",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Colors.grey[700]),
        )
      else if (mostrarFertil) ...[
        Text(
          "Ovulación estimada: ${_formatDate(p.estimatedOvulationDate)}",
          style: const TextStyle(fontSize: 15),
        ),
        const SizedBox(height: 10),
        _buildFertileWindow(p),
        const SizedBox(height: 4),
        Text(
          "Estimación; no es un método anticonceptivo.",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[700],
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
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

  /// Solo si visibleFertileMarks la deja ver (ver _buildActiveCard).
  Widget _buildFertileWindow(ActivePrediction p) {
    return Text(
      "Días de mayor probabilidad de fertilidad (estimación):\n"
      "${_formatDate(p.fertileWindowStartDate)} - ${_formatDate(p.fertileWindowEndDate)}",
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 14),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Text(
        "Esta es una estimación, no un método anticonceptivo.",
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12,
          color: Colors.grey[700],
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }

}
