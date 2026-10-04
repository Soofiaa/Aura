import 'dart:async';

import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import '../data/repositories/cycle_repository.dart';
import '../data/database/app_database.dart' show DailyLogRow;
import '../utils/day_key.dart';
import '../utils/app_snackbar.dart';

/// Rangos mas largos que esto piden confirmacion extra antes de marcar
/// todos los dias como menstruacion (evita que un arrastre accidental
/// marque semanas enteras sin querer).
const int longRangeConfirmationThreshold = 10;

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _focusedDay = DateTime.now();
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

  @override
  void initState() {
    super.initState();
    _periodDaysSub = cycleRepository.watchPeriodDayDates().listen((keys) {
      if (!mounted) return;
      setState(() => _periodDayKeys = keys);
    });
  }

  @override
  void dispose() {
    _periodDaysSub?.cancel();
    super.dispose();
  }

  bool _esDiaFuturo(DateTime day) {
    final hoy = DateTime.now();
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

  Future<void> registrarDia(DateTime date) async {
    final wasNew = await cycleRepository.markPeriodDay(DayKey.fromDate(date));

    if (!mounted) return;
    if (wasNew) {
      showAppSnackBar(
        context,
        const SnackBar(content: Text('Día registrado como menstruación')),
      );
    } else {
      showAppSnackBar(
        context,
        const SnackBar(content: Text('Ese día ya estaba registrado')),
      );
    }
  }

  Future<void> _quitarMarca(DateTime date) async {
    final key = DayKey.fromDate(date);
    final DailyLogRow? previo = await cycleRepository.getDay(key);
    await cycleRepository.setPeriodDayExplicitly(key, isPeriodDay: false);

    if (!mounted) return;
    showAppSnackBar(
      context,
      SnackBar(
        content: const Text('Marca quitada'),
        persist: false,
        duration: undoSnackBarDuration,
        action: SnackBarAction(
          label: 'Deshacer',
          onPressed: () => cycleRepository.restoreDaySnapshot(key, previo),
        ),
      ),
    );
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

    await cycleRepository.markPeriodDays(claves);

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

  @override
  Widget build(BuildContext context) {
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
                todayDecoration: const BoxDecoration(
                  color: Color(0xFFFAD4D8),
                  shape: BoxShape.circle,
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
                defaultBuilder: (context, day, focusedDay) {
                  // Colorear días guardados
                  if (_periodDayKeys.contains(DayKey.fromDate(day))) {
                    return Container(
                      margin: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFAD4D8),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${day.day}',
                        style: const TextStyle(
                            color: Colors.black, fontWeight: FontWeight.bold),
                      ),
                    );
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(height: 20),
            if (_rangeMode) ..._buildPanelRango() else ..._buildPanelDiaUnico(),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildPanelDiaUnico() {
    final seleccionado = _selectedDay;
    if (seleccionado == null) return const [];

    final yaMarcado = _periodDayKeys.contains(DayKey.fromDate(seleccionado));
    return [
      Text(
        "Día seleccionado: ${DateFormat('d MMMM yyyy', 'es').format(seleccionado)}",
        style: const TextStyle(fontSize: 16),
      ),
      const SizedBox(height: 20),
      if (yaMarcado)
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
