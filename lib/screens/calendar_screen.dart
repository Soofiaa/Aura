import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../data/database/hive_boxes.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  late Box diasBox;

  @override
  void initState() {
    super.initState();
    diasBox = HiveBoxes.diasMenstruacion;
  }

  List<DateTime> get diasMenstruacion {
    final List<dynamic> saved = diasBox.get('dias', defaultValue: []);
    return saved.map((d) => DateTime.parse(d.toString())).toList();
  }

  void _guardarDia(DateTime dia) {
    final List<DateTime> lista = diasMenstruacion;
    if (!lista.any((d) =>
    d.year == dia.year && d.month == dia.month && d.day == dia.day)) {
      lista.add(dia);
      diasBox.put('dias', lista.map((d) => d.toIso8601String()).toList());
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Calendario menstrual"),
        backgroundColor: const Color(0xFFA8D8EA),
        centerTitle: true,
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
                  if (diasMenstruacion.any((d) =>
                  d.year == day.year &&
                      d.month == day.month &&
                      d.day == day.day)) {
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
                if (_selectedDay != null) {
                  _guardarDia(_selectedDay!);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Día guardado localmente")),
                  );
                }
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
