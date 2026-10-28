import 'dart:async';

import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import '../data/repositories/cycle_repository.dart';
import '../domain/current_period.dart';
import '../domain/cycle_deriver.dart';
import '../domain/cycle_predictor.dart';
import '../domain/fertile_marks.dart';
import '../domain/range_selection.dart';
import '../utils/colors.dart';
import '../utils/day_key.dart';
import '../utils/app_snackbar.dart';
import '../utils/aura_localizations.dart';
import '../utils/period_end_messages.dart';
import '../widgets/period_day_marks.dart';
import '../widgets/period_start_sheet.dart';
import '../widgets/single_day_period_dialog.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key, this.repository, this.clock});

  /// Para tests; en la app, el repositorio global.
  final CycleRepository? repository;

  /// Para tests; en la app, la hora del telefono.
  final DateTime Function()? clock;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen>
    with WidgetsBindingObserver {
  late final CycleRepository _repository =
      widget.repository ?? cycleRepository;
  DateTime Function() get _clock => widget.clock ?? DateTime.now;
  String get _today => DayKey.fromDate(_clock());

  late DateTime _focusedDay = _clock();
  DateTime? _selectedDay;

  // "Elegir varios dias" (U-1): la seleccion vive aqui, no en
  // table_calendar (su modo de rango queda desactivado).
  bool _rangeMode = false;
  RangeSelection _selection = RangeSelection.empty;

  // Claves 'yyyy-MM-dd' de los dias marcados como dia de sangrado.
  List<String> _periodDayKeys = [];

  // Suscripcion en vez de cargar una vez: la pantalla vive dentro de un
  // IndexedStack y nunca se reconstruye desde cero, asi que sin esto no
  // se enteraria de cambios hechos en otra pestana (importar un
  // respaldo, borrar todos los datos, la pregunta de Inicio).
  StreamSubscription<List<String>>? _periodDaysSub;

  // Ciclos y duracion estimada, para los dias estimados (E-1), y la
  // prediccion de la ventana fertil (HU-05, CP5d-2).
  PredictionInputs? _inputs;
  StreamSubscription<PredictionInputs>? _inputsSub;

  @override
  void initState() {
    super.initState();
    _periodDaysSub = _repository.watchPeriodDayDates().listen((keys) {
      if (!mounted) return;
      setState(() => _periodDayKeys = keys);
    });
    _inputsSub = _repository.watchPredictionInputs().listen((inputs) {
      if (!mounted) return;
      setState(() => _inputs = inputs);
    });
    WidgetsBinding.instance.addObserver(this);
    _scheduleMidnightRefresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _midnightTimer?.cancel();
    _periodDaysSub?.cancel();
    _inputsSub?.cancel();
    super.dispose();
  }

  // Cambio de dia con la app abierta (como Inicio): sin esto, hoy, los
  // dias futuros deshabilitados, los estimados y la ventana quedaban un
  // dia atrasados hasta el proximo toque.
  Timer? _midnightTimer;
  late String _builtDay = _today;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshToday();
  }

  void _refreshToday() {
    if (!mounted) return;
    if (_today != _builtDay) setState(() => _builtDay = _today);
    _scheduleMidnightRefresh();
  }

  void _scheduleMidnightRefresh() {
    _midnightTimer?.cancel();
    final now = _clock();
    final nextMidnight = DateTime(now.year, now.month, now.day + 1);
    _midnightTimer = Timer(nextMidnight.difference(now), _refreshToday);
  }

  List<CycleSummary> get _cycles => _inputs?.cycles ?? const [];

  /// Dias estimados del periodo abierto mas reciente (E-1), con la misma
  /// duracion estimada que Inicio y la hoja (P-1). Vacio si no hay
  /// periodo actual abierto. Se recalculan en cada build: no se guardan.
  List<String> get _estimatedDays => _inputs?.predictionsPaused ?? false
      ? const []
      : estimatedPeriodDays(
        cycles: _cycles,
        typicalPeriodLengthDays: estimatePeriodLength(
          cycles: _cycles,
          config: _inputs?.config ?? const PredictionConfig(),
        ).days,
        today: _today,
      );

  /// Dias de la ventana fertil y de la ovulacion que se marcan (HU-05,
  /// CP5d-2), con la misma regla que Inicio (visibleFertileMarks) y la
  /// misma prediccion (predictCycle). Vacios mientras _inputs es null.
  /// Se calculan una vez por build, no por celda.
  ({Set<String> ventana, Set<String> ovulacion}) _fertileDays() {
    final inputs = _inputs;
    if (inputs == null || inputs.predictionsPaused) {
      return (ventana: const {}, ovulacion: const {});
    }
    final marks = visibleFertileMarks(
      predictCycle(cycles: inputs.cycles, today: _today, config: inputs.config),
      showFertileWindow: inputs.showFertileWindow,
    );
    if (marks == null) return (ventana: const {}, ovulacion: const {});
    final ventana = <String>{};
    for (var d = marks.windowStartDate;
        !DayKey.isBefore(marks.windowEndDate, d);
        d = DayKey.addDays(d, 1)) {
      ventana.add(d);
    }
    return (ventana: ventana, ovulacion: {marks.ovulationDate});
  }

  bool _esDiaFuturo(DateTime day) {
    final hoy = _clock();
    final hoySinHora = DateTime(hoy.year, hoy.month, hoy.day);
    return DateTime(day.year, day.month, day.day).isAfter(hoySinHora);
  }

  /// "Elegir varios dias" / "Cancelar seleccion" (crit. 14: la
  /// seleccion queda vacia).
  void _alternarModoRango() {
    setState(() {
      _rangeMode = !_rangeMode;
      _selection = RangeSelection.empty;
      _selectedDay = null;
    });
  }

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
            showAppSnackBar(
                context,
                tr('No se pudo guardar el cambio. Inténtalo de nuevo.',
                    "Couldn't save the change. Please try again."));
          }
        },
      ),
    );
  }

  /// Marca un dia suelto con foto para "Deshacer" (HU-04 crit. 7). No
  /// cierra el periodo: R-1 es solo para rangos.
  Future<void> registrarDia(DateTime date) async {
    final result = await _repository.markPeriodDayWithSnapshot(
        DayKey.fromDate(date),
        closeAtEnd: false,
        today: _today);

    if (!mounted) return;
    if (!result.changedAnything) {
      showAppSnackBar(context,
          tr('Ese día ya está registrado.', 'That day is already logged.'));
      return;
    }
    _showUndo(tr('Día registrado como menstruación.', 'Day logged as period.'),
        result.snapshot);
  }

  /// "Quitar marca": guarda un "No" explicito, con foto tomada antes para
  /// "Deshacer".
  Future<void> _quitarMarca(DateTime date) async {
    final key = DayKey.fromDate(date);
    final snapshot = await _repository.takeDaysSnapshot([key]);
    await _repository.setPeriodDayExplicitly(key, isPeriodDay: false);

    if (!mounted) return;
    _showUndo(tr('Marca quitada.', 'Mark removed.'), snapshot);
  }

  /// "Confirmar dias" (HU-04 crit. 4, decision 4A): los estimados pasan a
  /// registrados y el periodo queda cerrado en el ultimo estimado, con
  /// closePeriod (que tambien completa los huecos sin registro y respeta
  /// los "No" explicitos, decision 3B). Solo se ofrece cuando el ultimo
  /// estimado es hoy o ya paso.
  Future<void> _confirmarDias() async {
    final current = findCurrentPeriod(cycles: _cycles, today: _today);
    final estimated = _estimatedDays;
    if (current == null || current.isClosed || estimated.isEmpty) return;
    final end = estimated.last;

    // Cuantos dias se marcaran: los mismos que calcula closePeriod.
    final fechas = [
      for (var d = current.startDate;
          !DayKey.isBefore(end, d);
          d = DayKey.addDays(d, 1))
        d,
    ];
    final filas = (await _repository.takeDaysSnapshot(fechas)).rows;
    final aMarcar = daysToMarkWhenClosing(
      periodStart: current.startDate,
      endDate: end,
      periodDays: [
        for (final e in filas.entries)
          if (e.value?.isPeriodDay ?? false) e.key,
      ],
      explicitNonPeriodDays: [
        for (final e in filas.entries)
          if (e.value != null &&
              !e.value!.isPeriodDay &&
              e.value!.periodDayExplicit)
            e.key,
      ],
    ).length;
    if (!mounted) return;

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
            tr('¿Confirmar los días estimados?', 'Confirm the estimated days?')),
        content: Text(
          tr(
              'Se marcarán ${_dias(aMarcar)} más como período y quedará '
              'terminado '
              'el ${dayMonthLabel(end)}.',
              '${_dias(aMarcar)} more will be marked as period, and it will '
              'end on ${dayMonthLabel(end)}.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Cancelar', 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Confirmar', 'Confirm')),
          ),
        ],
      ),
    );
    if (confirmado != true || !mounted) return;

    final DaysSnapshot snapshot;
    try {
      snapshot =
          await _repository.closePeriod(current.startDate, end, today: _today);
    } on PeriodEndException catch (e) {
      if (!mounted) return;
      showAppSnackBar(
          context, periodEndProblemMessage(e.check, current.startDate));
      return;
    }
    if (!mounted) return;
    final duracion = DayKey.diffInDays(current.startDate, end) + 1;
    _showUndo(
        tr('Período confirmado: ${_dias(duracion)} en total.',
            'Period confirmed: ${_dias(duracion)} in total.'),
        snapshot);
  }

  static String _dias(int n) =>
      n == 1 ? tr('1 día', '1 day') : tr('$n días', '$n days');

  /// "Termino este dia" (decision 11B): cierra [periodo] en [dia] con
  /// closePeriod, que completa los dias sin registro hasta [dia] y
  /// respeta los "No" explicitos (decision 3B) y bloquea si hay dias
  /// marcados despues (decision 5A). Un periodo de 1 dia se confirma
  /// antes (decision 14, misma condicion que en Inicio).
  Future<void> _terminarEsteDia(CycleSummary periodo, String dia) async {
    final ultimoMarcado =
        DayKey.addDays(periodo.startDate, periodo.periodLengthDays - 1);
    if (needsSingleDayConfirmation(
            periodStart: periodo.startDate, endDate: dia) &&
        ultimoMarcado == dia) {
      final confirmado = await confirmSingleDayPeriod(context);
      if (!confirmado || !mounted) return;
    }

    final DaysSnapshot snapshot;
    try {
      snapshot =
          await _repository.closePeriod(periodo.startDate, dia, today: _today);
    } on PeriodEndException catch (e) {
      if (!mounted) return;
      showAppSnackBar(
          context, periodEndProblemMessage(e.check, periodo.startDate));
      return;
    }
    if (!mounted) return;
    _showUndo(periodEndedMessage(dia, _today), snapshot);
  }

  Future<bool> _confirmarRangoLargo(int cantidadDias) async {
    final resultado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Confirmar rango largo', 'Confirm long range')),
        content: Text(
          tr('Vas a marcar $cantidadDias días como menstruación. ¿Continuar?',
              "You're about to mark $cantidadDias days as period. Continue?"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Cancelar', 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Continuar', 'Continue')),
          ),
        ],
      ),
    );
    return resultado ?? false;
  }

  /// R-1 cuando el rango termina hoy o ayer. Null si se cierra el
  /// dialogo sin elegir.
  Future<bool?> _preguntarSiTermino() => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('¿Ya terminó tu período?', 'Has your period ended?')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Todavía no', 'Not yet')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Sí, terminó', 'Yes, it ended')),
            ),
          ],
        ),
      );

  /// "Marcar periodo" (U-1 con R-1): marca todos los dias del rango con
  /// markPeriodRangeWithSnapshot (un rango nunca se bloquea) y, segun
  /// rangeEndAction, guarda el fin en el ultimo dia: si termina hace 2
  /// dias o mas se cierra; si termina hoy o ayer se pregunta; si despues
  /// quedan dias marcados del mismo periodo, solo se marca. Un periodo que
  /// quedaria de 1 dia se confirma antes de cerrarlo (decision 14).
  Future<void> _confirmarRango() async {
    final seleccion = _selection;
    if (seleccion.isEmpty) return;
    final dias = seleccion.days;
    final inicio = dias.first;
    final fin = dias.last;

    if (seleccion.isLong) {
      final confirmado = await _confirmarRangoLargo(seleccion.dayCount);
      if (!confirmado || !mounted) return;
    }

    final bool cerrar;
    switch (rangeEndAction(
        rangeDays: dias, existingPeriodDays: _periodDayKeys, today: _today)) {
      case RangeEndAction.close:
        cerrar = true;
      case RangeEndAction.markOnly:
        cerrar = false;
      case RangeEndAction.ask:
        final respuesta = await _preguntarSiTermino();
        if (respuesta == null || !mounted) return;
        cerrar = respuesta;
    }

    if (cerrar) {
      final periodo = groupPeriodRuns([..._periodDayKeys, ...dias])
          .firstWhere((r) => r.contains(fin));
      if (needsSingleDayConfirmation(
          periodStart: periodo.first, endDate: fin)) {
        final confirmado = await confirmSingleDayPeriod(context);
        if (!confirmado || !mounted) return;
      }
    }

    final result = await _repository.markPeriodRangeWithSnapshot(inicio, fin,
        closeAtEnd: cerrar, today: _today);

    if (!mounted) return;
    setState(() {
      _selection = RangeSelection.empty;
      _rangeMode = false;
    });
    if (!result.changedAnything) {
      showAppSnackBar(
        context,
        dias.length == 1
            ? tr('Ese día ya está registrado.', 'That day is already logged.')
            : tr('Esos días ya están registrados.',
                'Those days are already logged.'),
      );
      return;
    }
    // Todos los dias ya estaban marcados y solo se guardo el fin.
    final n = result.newlyMarked;
    _showUndo(
      n == 0
          ? periodEndedMessage(fin, _today)
          : n == 1
              ? tr('1 día registrado como menstruación.',
                  '1 day logged as period.')
              : tr('$n días registrados como menstruación.',
                  '$n days logged as period.'),
      result.snapshot,
    );
  }

  /// Marca de fondo de cada dia: el rango elegido (U-1) o, si no esta en
  /// el rango, el borde punteado de un dia estimado o, si no, la marca de
  /// la ventana fertil o de la ovulacion (CP5d-2). Prioridad: seleccion >
  /// periodo (registrado o estimado) > ventana/ovulacion; un dia
  /// seleccionado o registrado no lleva marca de ventana. Va en
  /// rangeHighlightBuilder porque table_calendar envuelve el contenido de
  /// cada celda en un Semantics que excluye las etiquetas de adentro, y
  /// este builder queda fuera de ese Semantics; ademas se llama para
  /// todos los dias, incluidos los futuros (deshabilitados) y hoy. Como
  /// table_calendar no recibe rangeStartDay/rangeEndDay, nunca dibuja su
  /// propio resaltado.
  Widget? _dayMark(
    DateTime day,
    Set<String> estimated,
    Set<String> registrados,
    ({Set<String> ventana, Set<String> ovulacion}) fertiles,
  ) {
    final marca = _dayMarkContent(
        day, DayKey.fromDate(day), estimated, registrados, fertiles);
    return marca == null ? null : Positioned.fill(child: marca);
  }

  /// Estado que solo se ve por color: "periodo registrado" (relleno) y
  /// "hoy" (borde), en ese orden. Va en markerBuilder porque table_calendar
  /// lo pinta DESPUES de su Semantics con la fecha (CellContent) y, sin
  /// container, se fusiona en el mismo nodo de la celda (el del toque):
  /// la celda queda como un solo nodo con la fecha y el estado. Las
  /// celdas sin estado no cambian. markerBuilder solo se llama para dias
  /// habilitados, y los dos estados lo son (hoy y dias pasados).
  Widget? _stateSemantics(DateTime day, Set<String> registrados) {
    final clave = DayKey.fromDate(day);
    final estado = [
      if (registrados.contains(clave))
        tr('período registrado', 'logged period'),
      if (clave == _today) tr('hoy', 'today'),
    ];
    if (estado.isEmpty) return null;
    return Positioned.fill(
      child: Semantics(
        label: estado.join(', '),
        child: const SizedBox.expand(),
      ),
    );
  }

  /// La marca visible de [_dayMark], sin posicionar.
  Widget? _dayMarkContent(
    DateTime day,
    String clave,
    Set<String> estimated,
    Set<String> registrados,
    ({Set<String> ventana, Set<String> ovulacion}) fertiles,
  ) {
    final rango = _rangeMark(clave);
    if (rango != null) return rango;
    if (estimated.contains(clave)) {
      return SizedBox.expand(
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Semantics(
            container: true,
            label: tr('estimado', 'estimated'),
            child: const CustomPaint(painter: DashedBorderPainter()),
          ),
        ),
      );
    }
    if (!fertiles.ventana.contains(clave)) return null;
    if (!_rangeMode && isSameDay(_selectedDay, day)) return null;
    if (registrados.contains(clave)) return null;
    final ovulacion = fertiles.ovulacion.contains(clave);
    return SizedBox.expand(
      child: Semantics(
        container: true,
        label: ovulacion
            ? tr('ovulación estimada', 'estimated ovulation')
            : tr('ventana fértil estimada', 'estimated fertile window'),
        child: FertileDayMark(ovulation: ovulacion),
      ),
    );
  }

  /// Dia dentro de la seleccion de varios dias: franja AppColors.accent
  /// suave en todo el rango y el primer y el ultimo dia con borde grueso
  /// AppColors.accent (no depende solo del color: el lector de pantalla
  /// anuncia "inicio del rango", "fin del rango" o "dentro del rango").
  /// Con solo el inicio elegido se pinta solo ese dia.
  Widget? _rangeMark(String clave) {
    final seleccion = _selection;
    if (!_rangeMode || seleccion.isEmpty) return null;
    final inicio = seleccion.start!;
    final fin = seleccion.end ?? inicio;
    if (DayKey.isBefore(clave, inicio) || DayKey.isBefore(fin, clave)) {
      return null;
    }
    final esInicio = clave == inicio;
    final esFin = clave == fin && seleccion.isComplete;
    final etiqueta = esInicio && esFin
        ? tr('inicio y fin del rango', 'start and end of range')
        : esInicio
            ? tr('inicio del rango', 'start of range')
            : esFin
                ? tr('fin del rango', 'end of range')
                : tr('dentro del rango', 'within range');
    final extremo = esInicio || esFin;
    return SizedBox.expand(
      child: Semantics(
        container: true,
        label: etiqueta,
        child: Container(
          margin: EdgeInsets.all(extremo ? 2 : 6),
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: extremo ? 0.35 : 0.2),
            // Extremos con borde grueso (inicio y fin); los dias de en
            // medio, con borde fino para que la franja llegue a 3:1.
            border: Border.all(
              color: AppColors.accentStrong,
              width: extremo ? 3 : AppColors.thinBorderWidth,
            ),
            borderRadius: BorderRadius.circular(periodDayMarkRadius),
          ),
        ),
      ),
    );
  }

  /// Dia registrado: relleno AppColors.secondary. Null si [day] no esta
  /// marcado (table_calendar usa entonces su celda normal o la de hoy).
  Widget? _registeredCell(DateTime day) {
    if (!_periodDayKeys.contains(DayKey.fromDate(day))) return null;
    return Container(
      margin: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: AppColors.secondary,
        border: Border.all(
          color: AppColors.accentStrong,
          width: AppColors.thinBorderWidth,
        ),
        borderRadius: BorderRadius.circular(periodDayMarkRadius),
      ),
      alignment: Alignment.center,
      child: Text(
        '${day.day}',
        style: const TextStyle(
            color: AppColors.textPrimary, fontWeight: FontWeight.bold),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final estimated = _estimatedDays.toSet();
    final registrados = _periodDayKeys.toSet();
    final fertiles = _fertileDays();
    final hoy = _clock();
    return Scaffold(
      appBar: AppBar(
        title: Text(tr("Calendario menstrual", "Period calendar"),
            style: const TextStyle(fontWeight: FontWeight.w600)),
        centerTitle: true,
        backgroundColor: AppColors.primary,
        actions: [
          IconButton(
            icon: const Icon(Icons.today),
            tooltip: tr('Ir a hoy', 'Go to today'),
            onPressed: () => setState(() => _focusedDay = _clock()),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // HU-04 crit. 1 y 6: los dos botones siempre visibles.
            // IntrinsicHeight + stretch: los dos botones miden lo mismo
            // aunque el texto de uno se parta en dos lineas.
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Con un embarazo activo, solo "Elegir varios dias".
                  if (!(_inputs?.isPregnant ?? false)) ...[
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => showPeriodStartSheet(context,
                          repository: _repository, today: _today),
                      icon: const Icon(Icons.water_drop_outlined),
                      label: Text(tr('Me llegó hoy', 'My period started today')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: AppColors.textPrimary,
                        minimumSize: const Size(48, 48),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _alternarModoRango,
                      icon: Icon(_rangeMode ? Icons.close : Icons.date_range),
                      // En modo rango se ve "Cancelar" (entra en una linea),
                      // pero el lector de pantalla sigue diciendo "Cancelar
                      // seleccion": semanticsLabel reemplaza al texto en el
                      // mismo nodo del boton.
                      label: _rangeMode
                          ? Text(tr('Cancelar', 'Cancel'),
                              semanticsLabel:
                                  tr('Cancelar selección', 'Cancel selection'))
                          : Text(tr('Elegir varios días', 'Select multiple days')),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textPrimary,
                        minimumSize: const Size(48, 48),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            // <dynamic> explicito: con markerBuilder se inferiria otro tipo
            // y cambiaria el tipo del widget (antes era dynamic).
            TableCalendar<dynamic>(
              locale: auraLanguage,
              firstDay: DateTime.utc(2020, 1, 1),
              // Un ano hacia adelante desde hoy (los estimados y la
              // ventana fertil caen en los meses siguientes). Antes era
              // fijo, 2030-12-31: desde 2031 focusedDay pasaba lastDay.
              lastDay: DateTime.utc(hoy.year + 1, hoy.month, hoy.day),
              focusedDay: _focusedDay,
              // Los nombres de los dias crecen con el tamano de letra (fijo
              // en 16 se cortaban con letra grande).
              daysOfWeekHeight: MediaQuery.textScalerOf(context).scale(16) + 4,
              currentDay: _clock(),
              enabledDayPredicate: (day) => !_esDiaFuturo(day),
              selectedDayPredicate: (day) =>
                  !_rangeMode && isSameDay(_selectedDay, day),
              // U-1: todos los toques llegan por onDaySelected.
              rangeSelectionMode: RangeSelectionMode.disabled,
              calendarFormat: CalendarFormat.month,
              startingDayOfWeek: StartingDayOfWeek.monday,
              headerStyle: HeaderStyle(
                formatButtonVisible: false,
                titleCentered: true,
                titleTextStyle: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
                leftChevronIcon: Icon(Icons.chevron_left,
                    semanticLabel: tr('Mes anterior', 'Previous month')),
                rightChevronIcon: Icon(Icons.chevron_right,
                    semanticLabel: tr('Mes siguiente', 'Next month')),
              ),
              calendarStyle: CalendarStyle(
                // Los dias del mes anterior/siguiente que rellenan la
                // grilla quedan ocultos: evita numeros duplicados (ej.
                // "5" del mes actual Y del siguiente) que vuelven
                // ambiguo tocar un dia por su numero.
                outsideDaysVisible: false,
                // Hoy sin marcar: borde sin relleno y numero en negrita,
                // para no confundirlo con un dia registrado (relleno). Hoy
                // marcado usa todayBuilder.
                todayDecoration: BoxDecoration(
                  border: Border.all(color: AppColors.accentStrong, width: 2),
                  shape: BoxShape.circle,
                ),
                todayTextStyle: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
                selectedDecoration: const BoxDecoration(
                  color: AppColors.accent,
                  shape: BoxShape.circle,
                ),
                selectedTextStyle: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
                // Dias futuros (deshabilitados): textSecondary (4,28:1
                // sobre el fondo) en vez del #BFBFBF de la libreria
                // (1,76:1); ahi caen casi siempre la ventana y la
                // ovulacion (CP5d-2).
                disabledTextStyle:
                    const TextStyle(color: AppColors.textSecondary),
              ),
              onDaySelected: (selectedDay, focusedDay) {
                setState(() {
                  _focusedDay = focusedDay;
                  if (_rangeMode) {
                    _selection =
                        _selection.tap(DayKey.fromDate(selectedDay));
                  } else {
                    _selectedDay = selectedDay;
                  }
                });
              },
              // Sin esto, _focusedDay (el de este State) nunca se entera
              // de que la usuaria navego de mes con las flechas del
              // encabezado: TableCalendar lleva su propio estado interno
              // de pagina, pero CUALQUIER rebuild por otro motivo (ej.
              // alternar "Seleccionar varios dias") le pasa de nuevo nuestro
              // _focusedDay desactualizado y el calendario salta de vuelta
              // al mes original.
              onPageChanged: (focusedDay) {
                _focusedDay = focusedDay;
              },
              calendarBuilders: CalendarBuilders(
                // El titulo por defecto de table_calendar va dentro de un
                // GestureDetector que no hace nada (no usamos
                // onHeaderTapped) y se anuncia como boton: este es el
                // mismo texto, como encabezado y sin gesto.
                headerTitleBuilder: (context, month) => Semantics(
                  header: true,
                  child: Text(
                    DateFormat.yMMMM(auraLanguage).format(month),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                outsideBuilder: (context, day, focusedDay) =>
                    const SizedBox.shrink(),
                rangeHighlightBuilder: (context, day, isWithinRange) =>
                    _dayMark(day, estimated, registrados, fertiles),
                defaultBuilder: (context, day, focusedDay) =>
                    _registeredCell(day),
                todayBuilder: (context, day, focusedDay) =>
                    _registeredCell(day),
                markerBuilder: (context, day, events) =>
                    _stateSemantics(day, registrados),
              ),
            ),
            const SizedBox(height: 12),
            CalendarLegend(
              showEstimated: estimated.isNotEmpty,
              showFertile: fertiles.ventana.isNotEmpty,
            ),
            const SizedBox(height: 20),
            if (_rangeMode)
              ..._buildPanelRango()
            else
              ..._buildPanelDiaUnico(estimated),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildPanelDiaUnico(Set<String> estimated) {
    final seleccionado = _selectedDay;
    if (seleccionado == null) return const [];

    final clave = DayKey.fromDate(seleccionado);
    final yaMarcado = _periodDayKeys.contains(clave);
    // Decision 4A: un dia estimado ofrece "Confirmar dias" solo cuando el
    // ultimo estimado es hoy o ya paso; si no, es un dia sin marcar.
    final confirmable = estimated.contains(clave) &&
        canConfirmEstimates(estimatedDays: _estimatedDays, today: _today);
    // Decision 11B: "Termino este dia" si hay un periodo abierto que
    // pueda terminar en este dia. En el ultimo estimado confirmable no se
    // ofrece: "Confirmar dias" hace lo mismo.
    final periodo = periodThatCanEndOn(
      cycles: _cycles,
      periodDays: _periodDayKeys,
      day: clave,
      today: _today,
    );
    final esUltimoEstimado =
        confirmable && clave == _estimatedDays.last;
    final ofrecerTermino = periodo != null && !esUltimoEstimado;
    return [
      Text(
        tr("Día seleccionado: ${DateFormat('d MMMM yyyy', 'es').format(seleccionado)}",
            "Selected day: ${DateFormat('MMMM d, yyyy', 'en').format(seleccionado)}"),
        style: const TextStyle(fontSize: 16),
      ),
      const SizedBox(height: 20),
      if (confirmable)
        ElevatedButton.icon(
          onPressed: _confirmarDias,
          icon: const Icon(Icons.check),
          label: Text(tr('Confirmar días', 'Confirm days')),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.textPrimary,
            minimumSize: const Size(48, 48),
          ),
        )
      else if (yaMarcado)
        OutlinedButton.icon(
          onPressed: () => _quitarMarca(seleccionado),
          icon: const Icon(Icons.remove_circle_outline),
          label: Text(tr("Quitar marca", "Remove mark")),
        )
      else
        ElevatedButton.icon(
          onPressed: () => registrarDia(seleccionado),
          icon: const Icon(Icons.favorite),
          label: Text(tr("Marcar período", "Mark period")),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.textPrimary,
          ),
        ),
      if (ofrecerTermino) ...[
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => _terminarEsteDia(periodo, clave),
          icon: const Icon(Icons.flag_outlined),
          label: Text(tr('Terminó este día', 'Ended this day')),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textPrimary,
            minimumSize: const Size(48, 48),
          ),
        ),
      ],
    ];
  }

  static String _diaCorto(String clave) =>
      DateFormat(auraIsEnglish ? 'MMM d' : 'd MMM', auraLanguage)
          .format(DateTime.parse(clave));

  /// Panel de "Elegir varios dias" con los textos de la Etapa A (U-1, A).
  /// El resumen es una liveRegion: el lector de pantalla anuncia cada
  /// cambio del rango.
  List<Widget> _buildPanelRango() {
    final seleccion = _selection;
    const estilo = TextStyle(fontSize: 16, color: AppColors.textPrimary);
    const ayuda = TextStyle(fontSize: 14, color: AppColors.textSecondary);
    if (seleccion.isEmpty) {
      return [
        Semantics(
          liveRegion: true,
          child: Text(tr('Toca el primer día.', 'Tap the first day.'),
              style: estilo),
        ),
      ];
    }
    final n = seleccion.dayCount;
    final dias = _dias(n);
    final inicio = _diaCorto(seleccion.start!);
    final resumen = seleccion.isComplete
        ? '$inicio → ${_diaCorto(seleccion.end!)} · $dias'
        : '$inicio · $dias';
    return [
      Semantics(
        liveRegion: true,
        child: Text(resumen, style: estilo),
      ),
      const SizedBox(height: 6),
      Text(
        seleccion.isComplete
            ? tr('Toca otro día para cambiar el final.',
                'Tap another day to change the end.')
            : tr('Ahora toca el último día.', 'Now tap the last day.'),
        style: ayuda,
      ),
      if (seleccion.isLong) ...[
        const SizedBox(height: 6),
        Text(
          tr(
              'Son más de $longRangeConfirmationThreshold días: revisa que sea '
              'correcto.',
              "That's more than $longRangeConfirmationThreshold days: check "
              "that it's correct."),
          style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
        ),
      ],
      const SizedBox(height: 20),
      ElevatedButton.icon(
        onPressed: _confirmarRango,
        icon: const Icon(Icons.favorite),
        label: Text(tr("Marcar período", "Mark period")),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.textPrimary,
          minimumSize: const Size(48, 48),
        ),
      ),
    ];
  }
}
