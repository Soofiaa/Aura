import 'dart:async';

import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import '../data/repositories/cycle_repository.dart';
import '../domain/current_period.dart';
import '../domain/cycle_deriver.dart';
import '../domain/cycle_predictor.dart';
import '../utils/colors.dart';
import '../utils/day_key.dart';
import '../utils/app_snackbar.dart';
import '../utils/period_end_messages.dart';
import '../widgets/period_day_marks.dart';
import '../widgets/period_start_sheet.dart';
import '../widgets/single_day_period_dialog.dart';

/// Rangos mas largos que esto piden confirmacion extra antes de marcar
/// todos los dias como menstruacion (evita que un arrastre accidental
/// marque semanas enteras sin querer).
const int longRangeConfirmationThreshold = 10;

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

  bool _rangeMode = false;
  DateTime? _rangeStart;
  DateTime? _rangeEnd;

  // Claves 'yyyy-MM-dd' de los dias marcados como dia de sangrado.
  List<String> _periodDayKeys = [];

  // Suscripcion en vez de cargar una vez: la pantalla vive dentro de un
  // IndexedStack y nunca se reconstruye desde cero, asi que sin esto no
  // se enteraria de cambios hechos en otra pestana (importar un
  // respaldo, borrar todos los datos, la pregunta de Inicio).
  StreamSubscription<List<String>>? _periodDaysSub;

  // Ciclos y duracion estimada, para los dias estimados (E-1).
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

  bool _esDiaFuturo(DateTime day) {
    final hoy = _clock();
    final hoySinHora = DateTime(hoy.year, hoy.month, hoy.day);
    return DateTime(day.year, day.month, day.day).isAfter(hoySinHora);
  }

  void _alternarModoRango() {
    setState(() {
      _rangeMode = !_rangeMode;
      _rangeStart = null;
      _rangeEnd = null;
      _selectedDay = null;
    });
  }

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

  /// Marca un dia suelto con foto para "Deshacer" (HU-04 crit. 7). No
  /// cierra el periodo: R-1 es solo para rangos.
  Future<void> registrarDia(DateTime date) async {
    final result = await _repository.markPeriodDayWithSnapshot(
        DayKey.fromDate(date),
        closeAtEnd: false,
        today: _today);

    if (!mounted) return;
    if (!result.changedAnything) {
      showAppSnackBar(
        context,
        const SnackBar(content: Text('Ese día ya estaba registrado')),
      );
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
        context,
        SnackBar(
            content:
                Text(periodEndProblemMessage(e.check, current.startDate))),
      );
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
        context,
        SnackBar(
            content:
                Text(periodEndProblemMessage(e.check, periodo.startDate))),
      );
      return;
    }
    if (!mounted) return;
    _showUndo(periodEndedMessage(dia, _today), snapshot);
  }

  List<String> _clavesEnRango(DateTime start, DateTime end) {
    final startKey = DayKey.fromDate(start);
    final endKey = DayKey.fromDate(end);
    final dias = DayKey.diffInDays(startKey, endKey);
    return [for (var i = 0; i <= dias; i++) DayKey.addDays(startKey, i)];
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

  Future<void> _confirmarRango() async {
    final start = _rangeStart;
    if (start == null) return;
    final end = _rangeEnd ?? start;

    final claves = _clavesEnRango(start, end);
    if (claves.length > longRangeConfirmationThreshold) {
      final confirmado = await _confirmarRangoLargo(claves.length);
      if (!confirmado) return;
    }

    await _repository.markPeriodDays(claves);

    if (!mounted) return;
    setState(() {
      _rangeStart = null;
      _rangeEnd = null;
      _rangeMode = false;
    });
    showAppSnackBar(
      context,
      SnackBar(
        content: Text('${claves.length} días registrados como menstruación'),
      ),
    );
  }

  /// Borde punteado y etiqueta "estimado" de un dia estimado. Va en
  /// rangeHighlightBuilder porque table_calendar envuelve el contenido de
  /// cada celda en un Semantics que excluye las etiquetas de adentro, y
  /// este builder queda fuera de ese Semantics; ademas se llama para
  /// todos los dias, incluidos los futuros (deshabilitados) y hoy. En el
  /// modo de varios dias, el resaltado del rango tiene prioridad: con
  /// null, table_calendar dibuja su resaltado por defecto en los dias
  /// dentro del rango.
  Widget? _estimatedMark(
      DateTime day, bool isWithinRange, Set<String> estimated) {
    if (isWithinRange || !estimated.contains(DayKey.fromDate(day))) {
      return null;
    }
    return Positioned.fill(
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

  /// Dia registrado: relleno AppColors.secondary. Null si [day] no esta
  /// marcado (table_calendar usa entonces su celda normal o la de hoy).
  Widget? _registeredCell(DateTime day) {
    if (!_periodDayKeys.contains(DayKey.fromDate(day))) return null;
    return Container(
      margin: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: AppColors.secondary,
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
    return Scaffold(
      appBar: AppBar(
        title: const Text("Calendario menstrual",
            style: TextStyle(fontWeight: FontWeight.w600)),
        centerTitle: true,
        backgroundColor: const Color(0xFFA8D8EA),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // HU-04 crit. 1: siempre visible.
            ElevatedButton.icon(
              onPressed: () => showPeriodStartSheet(context,
                  repository: _repository, today: _today),
              icon: const Icon(Icons.water_drop_outlined),
              label: const Text('Me llegó hoy'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.textPrimary,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _alternarModoRango,
                icon: Icon(_rangeMode ? Icons.close : Icons.date_range),
                label: Text(
                  _rangeMode ? 'Cancelar selección' : 'Seleccionar varios días',
                ),
              ),
            ),
            TableCalendar(
              locale: 'es_ES',
              firstDay: DateTime.utc(2020, 1, 1),
              lastDay: DateTime.utc(2030, 12, 31),
              focusedDay: _focusedDay,
              currentDay: _clock(),
              enabledDayPredicate: (day) => !_esDiaFuturo(day),
              selectedDayPredicate: (day) =>
                  !_rangeMode && isSameDay(_selectedDay, day),
              rangeStartDay: _rangeStart,
              rangeEndDay: _rangeEnd,
              rangeSelectionMode: _rangeMode
                  ? RangeSelectionMode.toggledOn
                  : RangeSelectionMode.toggledOff,
              calendarFormat: CalendarFormat.month,
              startingDayOfWeek: StartingDayOfWeek.monday,
              headerStyle: const HeaderStyle(
                formatButtonVisible: false,
                titleCentered: true,
                titleTextStyle: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
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
                  border: Border.all(color: AppColors.accent, width: 2),
                  shape: BoxShape.circle,
                ),
                todayTextStyle: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
                selectedDecoration: BoxDecoration(
                  color: Colors.pinkAccent,
                  shape: BoxShape.circle,
                ),
                rangeStartDecoration: const BoxDecoration(
                  color: Colors.pinkAccent,
                  shape: BoxShape.circle,
                ),
                rangeEndDecoration: const BoxDecoration(
                  color: Colors.pinkAccent,
                  shape: BoxShape.circle,
                ),
                withinRangeDecoration: BoxDecoration(
                  color: Colors.pinkAccent.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
              ),
              onDaySelected: (selectedDay, focusedDay) {
                if (_rangeMode) return;
                setState(() {
                  _selectedDay = selectedDay;
                  _focusedDay = focusedDay;
                });
              },
              onRangeSelected: (start, end, focusedDay) {
                if (!_rangeMode) return;
                setState(() {
                  _rangeStart = start;
                  _rangeEnd = end;
                  _focusedDay = focusedDay;
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
                outsideBuilder: (context, day, focusedDay) =>
                    const SizedBox.shrink(),
                rangeHighlightBuilder: (context, day, isWithinRange) =>
                    _estimatedMark(day, isWithinRange, estimated),
                defaultBuilder: (context, day, focusedDay) =>
                    _registeredCell(day),
                todayBuilder: (context, day, focusedDay) =>
                    _registeredCell(day),
              ),
            ),
            const SizedBox(height: 12),
            const CalendarLegend(),
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
            backgroundColor: const Color(0xFFA8D8EA),
            foregroundColor: Colors.black,
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

  List<Widget> _buildPanelRango() {
    final start = _rangeStart;
    if (start == null) {
      return const [
        Text(
          'Toca el primer y el último día del rango.',
          style: TextStyle(fontSize: 14),
        ),
      ];
    }
    final end = _rangeEnd ?? start;
    final cantidad = _clavesEnRango(start, end).length;
    final formato = DateFormat('d MMMM yyyy', 'es');
    return [
      Text(
        '${formato.format(start)} - ${formato.format(end)} ($cantidad días)',
        style: const TextStyle(fontSize: 16),
      ),
      const SizedBox(height: 20),
      ElevatedButton.icon(
        onPressed: _confirmarRango,
        icon: const Icon(Icons.favorite),
        label: const Text("Marcar período"),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFA8D8EA),
          foregroundColor: Colors.black,
        ),
      ),
    ];
  }
}
