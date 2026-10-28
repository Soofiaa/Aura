import 'dart:async';

import 'package:flutter/material.dart';
import '../data/backup/backup_file_gateway.dart' show BackupFileGateway;
import '../data/backup/backup_reminder_store.dart';
import '../data/backup/backup_service.dart';
import '../data/database/app_database.dart' show DailyLogRow;
import '../data/notifications/notification_reconciler.dart';
import '../data/repositories/cycle_repository.dart';
import '../domain/backup_reminder.dart';
import '../domain/current_period.dart';
import '../domain/cycle_predictor.dart';
import '../domain/fertile_marks.dart';
import '../utils/colors.dart';
import '../utils/date_labels.dart';
import '../utils/day_key.dart';
import '../utils/period_end_messages.dart';
import '../widgets/backup_reminder_card.dart';
import '../widgets/period_start_sheet.dart';
import '../widgets/single_day_period_dialog.dart';
import 'add_cycle_screen.dart';
import 'backup_create_flow.dart';
import '../utils/app_snackbar.dart';
import '../utils/aura_localizations.dart';

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

  /// Recordatorio de respaldo: inyectables para tests. En la app real, los
  /// singletons globales [backupReminderStore], [backupService] y
  /// [backupFileGateway] (como en SettingsScreen).
  final BackupReminderStore? reminderStore;
  final BackupService? backupService;
  final BackupFileGateway? fileGateway;

  const HomeScreen({
    super.key,
    this.repository,
    this.clock,
    this.reconciler,
    this.reminderStore,
    this.backupService,
    this.fileGateway,
  });

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

  // Recordatorio de respaldo: estado del archivo y si hay algun registro,
  // los dos en vivo (crear un respaldo, "Ahora no" o registrar el primer
  // dia cambian la tarjeta sin recargar).
  BackupReminderStore get _reminderStore =>
      widget.reminderStore ?? backupReminderStore;
  late final Stream<BackupReminderState> _recordatorio =
      _reminderStore.watch();
  late final Stream<bool> _hayRegistros = _repository.watchHasAnyLog();

  /// Ver BackupBusyScope: compartido con Ajustes dentro de la app.
  late ValueNotifier<bool> _backupBusy;
  ValueNotifier<bool>? _backupBusyPropio;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _backupBusy = BackupBusyScope.maybeOf(context) ??
        (_backupBusyPropio ??= ValueNotifier<bool>(false));
  }

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

  /// "21 de abril" (con el ano si no es el de hoy), como los avisos y el
  /// Calendario. TalkBack lo lee bien, a diferencia de "21/04/2026".
  String _formatDate(String dayKey) =>
      dayMonthLabelWithYear(dayKey, today: _today);

  void _showUndo(String message, DaysSnapshot snapshot) {
    showAppSnackBar(
      context,
      message,
      action: SnackBarAction(
        label: tr('Deshacer', 'Undo'),
        onPressed: () async {
          try {
            await _repository.restoreDaysSnapshot(snapshot);
          } catch (_) {
            if (!mounted) return;
            showAppSnackBar(context, _errorAlGuardar);
          }
        },
      ),
    );
  }

  static String get _errorAlGuardar => tr(
      'No se pudo guardar el cambio. Inténtalo de nuevo.',
      "Couldn't save the change. Please try again.");

  /// "Sigue": marca hoy como dia de sangrado. La tarjeta vuelve a
  /// preguntar manana.
  Future<void> _sigue() async {
    final MarkDaysResult result;
    try {
      result = await _repository.markPeriodDayWithSnapshot(_today,
          closeAtEnd: false, today: _today);
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(context, _errorAlGuardar);
      return;
    }
    if (!mounted || !result.changedAnything) return;
    _showUndo(tr('Día marcado como sangrado.', 'Day marked as bleeding.'),
        result.snapshot);
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
          context, periodEndProblemMessage(e.check, current.startDate));
      return;
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(context, _errorAlGuardar);
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
          'Aura',
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
          final enPausa = inputs?.predictionsPaused ?? false;
          final embarazada = inputs?.isPregnant ?? false;
          final prediction = enPausa
              ? null
              : predictCycle(
                  cycles: inputs?.cycles ?? const [],
                  today: _today,
                  config: inputs?.config ?? const PredictionConfig(),
                );
          final current = findCurrentPeriod(
              cycles: inputs?.cycles ?? const [], today: _today);
          // #17: los botones de accion quedan fijos abajo, fuera del
          // scroll (mismo patron que "Guardar registro"): siempre a la
          // vista aunque la tarjeta "Sigue tu periodo hoy?" alargue Inicio.
          return Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SizedBox(height: 10),
                      Text(
                        embarazada
                            ? tr("Tu embarazo", "Your pregnancy")
                            : tr("Tu ciclo actual", "Your current cycle"),
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 20),
                      if (enPausa)
                        _buildPregnancyCard(inputs!.pregnancies.last)
                      else
                        _buildPredictionCard(prediction,
                            mostrarFertilidad: inputs?.showFertileWindow ?? true,
                            enCurso: _periodoEnCurso(prediction, current)),
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
                      _buildBackupReminder(),
                      if (!embarazada) ...[
                        const SizedBox(height: 12),
                        _buildDisclaimer(),
                      ],
                    ],
                  ),
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Decision 1: "Me llego hoy" en Inicio solo cuando no hay
                      // un periodo abierto en curso. Nunca con un embarazo activo.
                      if (!embarazada && (current == null || current.isClosed)) ...[
                        ElevatedButton.icon(
                          onPressed: () => showPeriodStartSheet(context,
                              repository: _repository, today: _today),
                          icon: const Icon(Icons.water_drop_outlined),
                          label: Text(tr('Me llegó hoy', 'My period started today')),
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
                        label: Text(tr("Registrar día", "Log day")),
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
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Tarjeta del recordatorio de respaldo, debajo de la del ciclo y de
  /// "Sigue tu periodo hoy?". Nada mientras no se haya leido el estado o
  /// si no se puede leer (sin parpadeo ni aviso por un error).
  Widget _buildBackupReminder() {
    return StreamBuilder<bool>(
      stream: _hayRegistros,
      builder: (context, registros) => StreamBuilder<BackupReminderState>(
        stream: _recordatorio,
        builder: (context, snapshot) {
          final estado = snapshot.hasError ? null : snapshot.data;
          final hayRegistros = registros.hasError ? null : registros.data;
          if (estado == null || hayRegistros == null) {
            return const SizedBox.shrink();
          }
          final mostrar = deberiaRecordarRespaldo(
            today: _today,
            activado: estado.activado,
            hayRegistros: hayRegistros,
            primerUso: estado.primerUso,
            ultimoRespaldo: estado.ultimoRespaldo,
            pospuestoHasta: estado.pospuestoHasta,
          );
          if (!mostrar) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(top: 12),
            child: ValueListenableBuilder<bool>(
              valueListenable: _backupBusy,
              builder: (context, ocupada, _) => BackupReminderCard(
                estado: estado,
                today: _today,
                onCrear: ocupada ? null : _crearRespaldo,
                onAhoraNo: _ahoraNo,
                onNoRecordar: _noRecordarMas,
              ),
            ),
          );
        },
      ),
    );
  }

  /// El mismo flujo que "Crear respaldo" en Ajustes. Los dialogos y avisos
  /// van sobre el contexto de Inicio, no el de la tarjeta: la tarjeta se
  /// va sola al anotar el respaldo y "Respaldo guardado." debe verse igual.
  Future<void> _crearRespaldo() => CreateBackupFlow(
        service: widget.backupService ?? backupService,
        busy: _backupBusy,
        gateway: widget.fileGateway,
        reminderStore: _reminderStore,
      ).run(context);

  Future<void> _ahoraNo() async {
    try {
      await _reminderStore.postpone();
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(context, _errorAlGuardar);
    }
  }

  Future<void> _noRecordarMas() async {
    try {
      await _reminderStore.setEnabled(false);
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(context, _errorAlGuardar);
      return;
    }
    if (!mounted) return;
    showAppSnackBar(context, tr('Puedes volver a activarlo en Ajustes.',
        'You can turn it back on in Settings.'));
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

  /// Periodo en curso, tal como lo presenta Inicio: el periodo actual
  /// (findCurrentPeriod) sigue abierto y, ademas, la fase calculada es la
  /// menstrual o el ultimo dia con sangrado es hoy o ayer. Es la misma
  /// condicion con la que aparece "Sigue tu periodo hoy?" (HU-03). Solo
  /// cambia lo que se muestra en Inicio (fase y fertilidad); la
  /// prediccion, el Calendario, Estadisticas y los avisos no cambian.
  /// Sin esto, un sangrado que reabre o alarga el periodo (regla de 7
  /// dias, R-4) dejaba "Fase folicular" junto a "Dia 9 de tu periodo".
  bool _periodoEnCurso(CyclePrediction? prediction, CurrentPeriod? current) {
    if (prediction is! ActivePrediction) return false;
    if (current == null || current.isClosed) return false;
    return prediction.currentPhase == CyclePhase.menstrual ||
        current.lastMarkedDate == _today ||
        current.lastMarkedDate == DayKey.addDays(_today, -1);
  }

  Widget _buildPredictionCard(CyclePrediction? prediction,
      {required bool mostrarFertilidad, required bool enCurso}) {
    if (prediction == null) {
      return _buildCardShell(children: [
        const Icon(Icons.favorite_border, color: AppColors.textSecondary, size: 50),
        const SizedBox(height: 10),
        Text(
          tr("Aún no hay datos suficientes", "Not enough data yet"),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          tr("Registra tu primer día para ver una predicción de tu ciclo.",
              "Log your first day to see a prediction of your cycle."),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
      ]);
    }

    return switch (prediction) {
      StaleDataPrediction() => _buildStaleCard(prediction),
      ActivePrediction() => _buildActiveCard(prediction,
          mostrarFertilidad: mostrarFertilidad, enCurso: enCurso),
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
        ? tr('1 día', '1 day')
        : tr('$estimatedPeriodLength días', '$estimatedPeriodLength days');
    const minimo = Size(48, 48);

    return _buildCardShell(children: [
      Text(
        tr("¿Sigue tu período hoy?", "Is your period still going today?"),
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 4),
      Text(
        // Si el dia ya supera la duracion estimada, no se presenta como si
        // el periodo durara menos que el dia actual.
        current.dayNumber > estimatedPeriodLength
            ? tr(
                'Día ${current.dayNumber} de tu período · ya superó tu '
                    'duración estimada ($dias)',
                'Day ${current.dayNumber} of your period · longer than your '
                    'estimated length ($dias)')
            : tr(
                'Día ${current.dayNumber} de tu período · duración estimada: '
                    '$dias',
                'Day ${current.dayNumber} of your period · estimated length: '
                    '$dias'),
        style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 12),
      // Wrap: con pantalla angosta o letra grande, "Termino hoy" baja a
      // la linea siguiente en vez de desbordar (con 1,0 en 360 dp ya no
      // entraban los dos).
      Wrap(
        alignment: WrapAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          ElevatedButton(
            onPressed: _sigue,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.textPrimary,
              minimumSize: minimo,
            ),
            child: Text(tr("Sigue", "Still going")),
          ),
          OutlinedButton(
            onPressed: () => _terminar(current, _today),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              minimumSize: minimo,
            ),
            child: Text(tr("Terminó hoy", "Ended today")),
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
        child: Text(
          tr("Ya terminó antes", "It ended earlier"),
          style: const TextStyle(decoration: TextDecoration.underline),
        ),
      ),
    ]);
  }

  /// Modo embarazo: semanas desde la ultima regla y fecha probable de
  /// parto (+280 dias). Si ya termino y no hay un periodo despues, solo
  /// explica la pausa, sin mencionar como termino.
  Widget _buildPregnancyCard(PregnancySpan embarazo) {
    const gris = TextStyle(fontSize: 14, color: AppColors.textSecondary);
    if (embarazo.end != null) {
      return _buildCardShell(children: [
        const Icon(Icons.pause_circle_outline,
            color: AppColors.textSecondary, size: 50),
        const SizedBox(height: 10),
        Text(
          tr("Predicciones en pausa", "Predictions paused"),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          tr("Cuando vuelva tu período, regístralo para retomar las "
                  "predicciones.",
              "When your period returns, log it to resume predictions."),
          textAlign: TextAlign.center,
          style: gris,
        ),
      ]);
    }
    final dias = DayKey.diffInDays(embarazo.start, _today);
    final semanas = dias ~/ 7;
    final resto = dias % 7;
    return _buildCardShell(children: [
      const Icon(Icons.pregnant_woman, color: Colors.pinkAccent, size: 50),
      const SizedBox(height: 10),
      Text(
        tr("$semanas ${semanas == 1 ? 'semana' : 'semanas'} y $resto "
                "${resto == 1 ? 'día' : 'días'}",
            "$semanas ${semanas == 1 ? 'week' : 'weeks'} and $resto "
                "${resto == 1 ? 'day' : 'days'}"),
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 15),
      Text(
        tr("Fecha probable de parto: "
                "${_formatDate(DayKey.addDays(embarazo.start, 280))}",
            "Estimated due date: "
                "${_formatDate(DayKey.addDays(embarazo.start, 280))}"),
        style: const TextStyle(fontSize: 16),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 15),
      Text(
        tr("Estimación desde el primer día de tu última regla "
                "(${_formatDate(embarazo.start)}). Las predicciones y los "
                "avisos del ciclo están en pausa.",
            "Estimated from the first day of your last period "
                "(${_formatDate(embarazo.start)}). Cycle predictions and "
                "reminders are paused."),
        textAlign: TextAlign.center,
        style: gris,
      ),
    ]);
  }

  Widget _buildStaleCard(StaleDataPrediction p) {
    return _buildCardShell(children: [
      const Icon(Icons.history, color: AppColors.textSecondary, size: 50),
      const SizedBox(height: 10),
      Text(
        tr("Hace tiempo que no registras...",
            "It's been a while since you logged..."),
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 8),
      Text(
        tr(
            "Tu último período empezó el ${_formatDate(p.lastPeriodStartDate)} "
            "(hace ${p.daysSinceLastPeriodStart} días). "
            "Registra un nuevo día para volver a ver una predicción.",
            "Your last period started on ${_formatDate(p.lastPeriodStartDate)} "
            "(${p.daysSinceLastPeriodStart} days ago). "
            "Log a new day to see a prediction again."),
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
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
  /// [enCurso]: ver [_periodoEnCurso]. Con el periodo en curso, la fase
  /// que se muestra es la menstrual. Inicio no habla de fertilidad
  /// mientras la fase mostrada sea la menstrual: no se muestran la
  /// ovulacion ni la ventana fertil (tambien el dia en que el periodo se
  /// cierra con "Termino hoy", que sigue siendo fase menstrual). La linea
  /// gris de confianza baja no da fechas y se mantiene.
  Widget _buildActiveCard(ActivePrediction p,
      {required bool mostrarFertilidad, required bool enCurso}) {
    final confianzaBaja = p.confidence == PredictionConfidence.low;
    final valorPorDefecto = p.completeCyclesConsidered <
        const PredictionConfig().minCompleteCyclesForMedium;
    final fase = enCurso ? CyclePhase.menstrual : p.currentPhase;
    final marcas = fase == CyclePhase.menstrual
        ? null
        : visibleFertileMarks(p, showFertileWindow: mostrarFertilidad);
    final mostrarFertil = marcas != null;
    final mostrarFase = !p.isPeriodLate &&
        !(!mostrarFertil && fase == CyclePhase.ovulatoria);
    return _buildCardShell(children: [
      if (p.isPeriodLate) _buildLateBanner(p),
      const Icon(Icons.favorite, color: Colors.pinkAccent, size: 50),
      if (mostrarFase) ...[
        const SizedBox(height: 10),
        Text(
          fase.label,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ],
      const SizedBox(height: 15),
      Text(
        tr(
            "Próximo período: ${_formatDate(p.nextPeriodEarliestDate)} - "
            "${_formatDate(p.nextPeriodLatestDate)}",
            "Next period: ${_formatDate(p.nextPeriodEarliestDate)} - "
            "${_formatDate(p.nextPeriodLatestDate)}"),
        style: const TextStyle(fontSize: 16),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 4),
      Text(
        tr(
            "Estimado: ${_formatDate(p.nextPeriodExpectedDate)}"
            "${valorPorDefecto ? ' (valor por defecto)' : ''}",
            "Estimated: ${_formatDate(p.nextPeriodExpectedDate)}"
            "${valorPorDefecto ? ' (default value)' : ''}"),
        style: TextStyle(fontSize: 13, color: Colors.grey[700]),
      ),
      const SizedBox(height: 15),
      if (mostrarFertilidad && confianzaBaja)
        Text(
          valorPorDefecto
              ? tr(
                  "Con más ciclos registrados podremos estimar tu ventana "
                      "fértil.",
                  "Once you log more cycles, we can estimate your fertile "
                      "window.")
              : tr(
                  "Tus ciclos varían mucho, así que no mostramos tu ventana "
                      "fértil.",
                  "Your cycles vary a lot, so we don't show your fertile "
                      "window."),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Colors.grey[700]),
        )
      else if (marcas != null) ...[
        Text(
          tr("Ovulación estimada: ${_formatDate(marcas.ovulationDate)}",
              "Estimated ovulation: ${_formatDate(marcas.ovulationDate)}"),
          style: const TextStyle(fontSize: 15),
        ),
        const SizedBox(height: 10),
        _buildFertileWindow(marcas),
        const SizedBox(height: 4),
        Text(
          tr("Estimación; no es un método anticonceptivo.",
              "Estimate only; not a method of birth control."),
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
        tr("Período atrasado por ${p.daysLate} día${p.daysLate == 1 ? '' : 's'}",
            "Period late by ${p.daysLate} day${p.daysLate == 1 ? '' : 's'}"),
        textAlign: TextAlign.center,
        style: const TextStyle(
            color: AppColors.lateText, fontWeight: FontWeight.bold),
      ),
    );
  }

  /// Solo si visibleFertileMarks la deja ver (ver _buildActiveCard).
  Widget _buildFertileWindow(FertileMarks marcas) {
    return Text(
      tr(
          "Días de mayor probabilidad de fertilidad (estimación):\n"
          "${_formatDate(marcas.windowStartDate)} - ${_formatDate(marcas.windowEndDate)}",
          "Most likely fertile days (estimate):\n"
          "${_formatDate(marcas.windowStartDate)} - ${_formatDate(marcas.windowEndDate)}"),
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
    final textColor = switch (p.confidence) {
      PredictionConfidence.low => AppColors.confidenceLowText,
      PredictionConfidence.medium => AppColors.confidenceMediumText,
      PredictionConfidence.high => AppColors.confidenceHighText,
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
            tr("Confianza: ${p.confidence.label}",
                "Confidence: ${p.confidence.label}"),
            style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
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
        tr("Esta es una estimación, no un método anticonceptivo.",
            "This is an estimate, not a method of birth control."),
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
