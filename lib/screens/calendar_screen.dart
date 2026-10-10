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

class _CalendarScreenState extends State<CalendarScreen> {
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
  }

  @override
  void dispose() {
    _periodDaysSub?.cancel();
    _inputsSub?.cancel();
    super.dispose();
  }

  List<CycleSummary> get _cycles => _inputs?.cycles ?? const [];

  /// Dias estimados del periodo abierto mas reciente (E-1), con la misma
  /// duracion estimada que Inicio y la hoja (P-1). Vacio si no hay
  /// periodo actual abierto. Se recalculan en cada build: no se guardan.
  List<String> get _estimatedDays => estimatedPeriodDays(
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
    if (inputs == null) return (ventana: const {}, ovulacion: const {});
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
        label: 'Deshacer',
        onPressed: () => _repository.restoreDaysSnapshot(snapshot),
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
      showAppSnackBar(context, 'Ese día ya estaba registrado');
      return;
    }
    _showUndo('Día registrado como menstruación.', result.snapshot);
  }

  /// "Quitar marca": guarda un "No" explicito, con foto tomada antes para
  /// "Deshacer".
  Future<void> _quitarMarca(DateTime date) async {
    final key = DayKey.fromDate(date);
    final snapshot = await _repository.takeDaysSnapshot([key]);
    await _repository.setPeriodDayExplicitly(key, isPeriodDay: false);

    if (!mounted) return;
    _showUndo('Marca quitada', snapshot);
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
        title: const Text('¿Confirmar los días estimados?'),
        content: Text(
          'Se marcarán ${_dias(aMarcar)} más como período y quedará '
          'terminado '
          'el ${dayMonthLabel(end)}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmar'),
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
    _showUndo('Período confirmado: ${_dias(duracion)} en total.', snapshot);
  }

  static String _dias(int n) => n == 1 ? '1 día' : '$n días';

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
        title: const Text('Confirmar rango largo'),
        content: Text(
          'Vas a marcar $cantidadDias días como menstruación. ¿Continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continuar'),
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
          title: const Text('¿Ya terminó tu período?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Todavía no'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sí, terminó'),
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
            ? 'Ese día ya estaba registrado'
            : 'Esos días ya estaban registrados',
      );
      return;
    }
    // Todos los dias ya estaban marcados y solo se guardo el fin.
    final n = result.newlyMarked;
    _showUndo(
      n == 0
          ? periodEndedMessage(fin, _today)
          : n == 1
              ? '1 día registrado como menstruación.'
              : '$n días registrados como menstruación.',
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
  ///
  /// Tambien dice en texto el estado que solo se ve por color: "periodo
  /// registrado" (relleno) y "hoy" (borde). Va en un nodo propio y la
  /// marca visible queda como nodo hijo con su etiqueta de siempre.
  Widget? _dayMark(
    DateTime day,
    Set<String> estimated,
    Set<String> registrados,
    ({Set<String> ventana, Set<String> ovulacion}) fertiles,
  ) {
    final clave = DayKey.fromDate(day);
    final estado = [
      if (registrados.contains(clave)) 'período registrado',
      if (clave == _today) 'hoy',
    ];
    final marca = _dayMarkContent(day, clave, estimated, registrados, fertiles);
    if (estado.isEmpty && marca == null) return null;
    if (estado.isEmpty) return Positioned.fill(child: marca!);
    return Positioned.fill(
      child: Semantics(
        container: true,
        label: estado.join(', '),
        child: marca ?? const SizedBox.expand(),
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
            label: 'estimado',
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
        label: ovulacion ? 'ovulación estimada' : 'ventana fértil estimada',
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
        ? 'inicio y fin del rango'
        : esInicio
            ? 'inicio del rango'
            : esFin
                ? 'fin del rango'
                : 'dentro del rango';
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
    return Scaffold(
      appBar: AppBar(
        title: const Text("Calendario menstrual",
            style: TextStyle(fontWeight: FontWeight.w600)),
        centerTitle: true,
        backgroundColor: AppColors.primary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // HU-04 crit. 1 y 6: los dos botones siempre visibles.
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => showPeriodStartSheet(context,
                        repository: _repository, today: _today),
                    icon: const Icon(Icons.water_drop_outlined),
                    label: const Text('Me llegó hoy'),
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
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _alternarModoRango,
                    icon: Icon(_rangeMode ? Icons.close : Icons.date_range),
                    label: Text(
                      _rangeMode ? 'Cancelar selección' : 'Elegir varios días',
                    ),
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
            const SizedBox(height: 4),
            TableCalendar(
              locale: 'es_ES',
              firstDay: DateTime.utc(2020, 1, 1),
              lastDay: DateTime.utc(2030, 12, 31),
              focusedDay: _focusedDay,
              currentDay: _clock(),
              enabledDayPredicate: (day) => !_esDiaFuturo(day),
              selectedDayPredicate: (day) =>
                  !_rangeMode && isSameDay(_selectedDay, day),
              // U-1: todos los toques llegan por onDaySelected.
              rangeSelectionMode: RangeSelectionMode.disabled,
              calendarFormat: CalendarFormat.month,
              startingDayOfWeek: StartingDayOfWeek.monday,
              headerStyle: const HeaderStyle(
                formatButtonVisible: false,
                titleCentered: true,
                titleTextStyle: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
                leftChevronIcon:
                    Icon(Icons.chevron_left, semanticLabel: 'Mes anterior'),
                rightChevronIcon:
                    Icon(Icons.chevron_right, semanticLabel: 'Mes siguiente'),
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
                    DateFormat.yMMMM('es_ES').format(month),
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
        "Día seleccionado: ${DateFormat('d MMMM yyyy', 'es').format(seleccionado)}",
        style: const TextStyle(fontSize: 16),
      ),
      const SizedBox(height: 20),
      if (confirmable)
        ElevatedButton.icon(
          onPressed: _confirmarDias,
          icon: const Icon(Icons.check),
          label: const Text('Confirmar días'),
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
          label: const Text("Quitar marca"),
        )
      else
        ElevatedButton.icon(
          onPressed: () => registrarDia(seleccionado),
          icon: const Icon(Icons.favorite),
          label: const Text("Registrar día de menstruación"),
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
          label: const Text('Terminó este día'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textPrimary,
            minimumSize: const Size(48, 48),
          ),
        ),
      ],
    ];
  }

  static String _diaCorto(String clave) =>
      DateFormat('d MMM', 'es').format(DateTime.parse(clave));

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
          child: const Text('Toca el primer día.', style: estilo),
        ),
      ];
    }
    final n = seleccion.dayCount;
    final dias = n == 1 ? '1 día' : '$n días';
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
            ? 'Toca otro día para cambiar el final.'
            : 'Ahora toca el último día.',
        style: ayuda,
      ),
      if (seleccion.isLong) ...[
        const SizedBox(height: 6),
        const Text(
          'Son más de $longRangeConfirmationThreshold días: revisa que sea '
          'correcto.',
          style: TextStyle(fontSize: 14, color: AppColors.textPrimary),
        ),
      ],
      const SizedBox(height: 20),
      ElevatedButton.icon(
        onPressed: _confirmarRango,
        icon: const Icon(Icons.favorite),
        label: const Text("Marcar período"),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.textPrimary,
          minimumSize: const Size(48, 48),
        ),
      ),
    ];
  }
}
