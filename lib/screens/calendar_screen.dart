import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import '../data/repositories/cycle_repository.dart';
import '../utils/day_key.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  // Claves 'yyyy-MM-dd' de los dias marcados como dia de sangrado.
  List<String> _periodDayKeys = [];

  @override
  void initState() {
    super.initState();
    _cargarDiasMenstruacion();
  }

  Future<void> _cargarDiasMenstruacion() async {
    final keys = await cycleRepository.getPeriodDayDates();
    if (!mounted) return;
    setState(() => _periodDayKeys = keys);
  }

  Future<void> registrarDia(DateTime date) async {
    final wasNew = await cycleRepository.markPeriodDay(DayKey.fromDate(date));

    if (!mounted) return;
    if (wasNew) {
      await _cargarDiasMenstruacion();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Día registrado como menstruación')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ese día ya estaba registrado')),
      );
    }
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
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TableCalendar(
              locale: 'es_ES',
              firstDay: DateTime.utc(2020, 1, 1),
              lastDay: DateTime.utc(2030, 12, 31),
              focusedDay: _focusedDay,
              selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
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
                todayDecoration: const BoxDecoration(
                  color: Color(0xFFFAD4D8),
                  shape: BoxShape.circle,
                ),
                selectedDecoration: BoxDecoration(
                  color: Colors.pinkAccent,
                  shape: BoxShape.circle,
                ),
              ),
              onDaySelected: (selectedDay, focusedDay) {
                setState(() {
                  _selectedDay = selectedDay;
                  _focusedDay = focusedDay;
                });
              },
              calendarBuilders: CalendarBuilders(
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
            if (_selectedDay != null)
              Text(
                "Día seleccionado: ${DateFormat('d MMMM yyyy', 'es').format(_selectedDay!)}",
                style: const TextStyle(fontSize: 16),
              ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                if (_selectedDay != null) registrarDia(_selectedDay!);
              },
              icon: const Icon(Icons.favorite),
              label: const Text("Registrar día de menstruación"),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFA8D8EA),
                foregroundColor: Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
