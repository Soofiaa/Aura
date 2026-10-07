import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/repositories/cycle_repository.dart';
import '../domain/current_period.dart';
import '../domain/cycle_predictor.dart';
import '../utils/app_snackbar.dart';
import '../utils/colors.dart';
import '../utils/day_key.dart';

/// Opciones de la hoja "Me llego hoy".
enum PeriodStartOption { today, yesterday, otherDay }

/// Hoja "Me llego hoy" (HU-02): la usuaria elige el primer dia de su
/// periodo (hoy, ayer u otro dia, nunca futuro) y se guarda solo ese dia
/// (crit. 2). Al confirmar muestra el aviso con "Deshacer", que restaura
/// la foto del dia. La abren Inicio y el Calendario.
///
/// [repository] y [today] son para tests; en la app se usan el
/// repositorio global y la fecha del telefono.
Future<void> showPeriodStartSheet(
  BuildContext context, {
  CycleRepository? repository,
  String? today,
}) async {
  final repo = repository ?? cycleRepository;
  final hoy = today ?? DayKey.today();

  final day = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.background,
    builder: (_) => PeriodStartSheet(repository: repo, today: hoy),
  );
  if (day == null) return;

  final result =
      await repo.markPeriodDayWithSnapshot(day, closeAtEnd: false, today: hoy);
  if (!context.mounted) return;

  if (!result.changedAnything) {
    // La hoja ya no deja confirmar un dia marcado; esto cubre que se haya
    // marcado por otro lado mientras estaba abierta.
    showAppSnackBar(
      context,
      const SnackBar(content: Text('Ese día ya está registrado.')),
    );
    return;
  }
  showAppSnackBar(
    context,
    SnackBar(
      content: const Text('Inicio del período registrado.'),
      persist: false,
      duration: undoSnackBarDuration,
      action: SnackBarAction(
        label: 'Deshacer',
        onPressed: () => repo.restoreDaysSnapshot(result.snapshot),
      ),
    ),
  );
}

/// Contenido de la hoja. Devuelve con Navigator.pop la fecha elegida
/// ('yyyy-MM-dd'), o null si se cierra sin confirmar. No escribe nada:
/// eso lo hace [showPeriodStartSheet].
class PeriodStartSheet extends StatefulWidget {
  const PeriodStartSheet({
    super.key,
    required this.repository,
    required this.today,
  });

  final CycleRepository repository;
  final String today;

  @override
  State<PeriodStartSheet> createState() => _PeriodStartSheetState();
}

class _PeriodStartSheetState extends State<PeriodStartSheet> {
  late final Future<_SheetData> _data = _load();
  PeriodStartOption _option = PeriodStartOption.today;
  String? _otherDay;

  Future<_SheetData> _load() async {
    final inputs = await widget.repository.getPredictionInputs();
    return _SheetData(
      periodDays: await widget.repository.getPeriodDayDates(),
      estimate:
          estimatePeriodLength(cycles: inputs.cycles, config: inputs.config),
    );
  }

  String get _chosenDay => switch (_option) {
        PeriodStartOption.today => widget.today,
        PeriodStartOption.yesterday => DayKey.addDays(widget.today, -1),
        PeriodStartOption.otherDay => _otherDay ?? widget.today,
      };

  static DateTime _toDate(String key) => DateTime.parse(key);

  static String _dayMonth(String key) =>
      DateFormat("d 'de' MMMM", 'es_ES').format(_toDate(key));

  /// Aviso de la decision 7, hacia atras y hacia adelante: el dia elegido
  /// se sumaria a un periodo anterior, a uno posterior o los uniria.
  static String? _joinWarning(String day, List<String> periodDays) {
    final before = periodThatDayWouldJoin(day: day, periodDays: periodDays);
    final after =
        laterPeriodThatDayWouldJoin(day: day, periodDays: periodDays);
    if (before != null && after != null) {
      return 'Ese día está muy cerca de tu período anterior (último día '
          'marcado: ${_dayMonth(before)}) y del período que empezó el '
          '${_dayMonth(after)}, así que los dos se unirán en un solo período.';
    }
    if (before != null) {
      return 'Ese día está muy cerca de tu período anterior (último día '
          'marcado: ${_dayMonth(before)}), así que se sumará a ese período.';
    }
    if (after != null) {
      return 'Ese día está muy cerca de tu período que empezó el '
          '${_dayMonth(after)}, así que se sumará a ese período.';
    }
    return null;
  }

  Future<void> _choose(PeriodStartOption? option) async {
    if (option == null) return;
    if (option != PeriodStartOption.otherDay) {
      setState(() => _option = option);
      return;
    }
    final hoy = _toDate(widget.today);
    final picked = await showDatePicker(
      context: context,
      initialDate: _toDate(_chosenDay),
      firstDate: DateTime(2020),
      lastDate: hoy,
      currentDate: hoy,
    );
    // Cancelar el selector deja la opcion que estaba.
    if (picked == null || !mounted) return;
    setState(() {
      _option = PeriodStartOption.otherDay;
      _otherDay = DayKey.fromDate(picked);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_SheetData>(
      future: _data,
      builder: (context, snapshot) {
        final data = snapshot.data;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: data == null
              ? const Center(child: CircularProgressIndicator())
              : _content(data),
        );
      },
    );
  }

  Widget _content(_SheetData data) {
    final day = _chosenDay;
    final alreadyMarked = data.periodDays.contains(day);
    final joinWarning =
        alreadyMarked ? null : _joinWarning(day, data.periodDays);
    final n = data.estimate.days;
    final days = n == 1 ? '1 día' : '$n días';
    // La misma duracion estimada que Inicio y el Calendario (P-1).
    final source = data.estimate.source == PeriodLengthSource.setting
        ? 'puedes cambiarla en Ajustes'
        : 'según tus últimos períodos';
    const secondary = TextStyle(fontSize: 14, color: AppColors.textSecondary);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '¿Cuándo empezó tu período?',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        RadioGroup<PeriodStartOption>(
          groupValue: _option,
          onChanged: _choose,
          child: Column(
            children: [
              const RadioListTile<PeriodStartOption>(
                value: PeriodStartOption.today,
                activeColor: AppColors.accent,
                contentPadding: EdgeInsets.zero,
                title: Text('Hoy'),
              ),
              const RadioListTile<PeriodStartOption>(
                value: PeriodStartOption.yesterday,
                activeColor: AppColors.accent,
                contentPadding: EdgeInsets.zero,
                title: Text('Ayer'),
              ),
              RadioListTile<PeriodStartOption>(
                value: PeriodStartOption.otherDay,
                activeColor: AppColors.accent,
                contentPadding: EdgeInsets.zero,
                title: const Text('Otro día'),
                subtitle: _option == PeriodStartOption.otherDay
                    ? Text(_dayMonth(day))
                    : null,
                // Con la opcion ya elegida, tocarla otra vez no avisa al
                // grupo: el boton del costado abre el selector de nuevo.
                secondary: _option == PeriodStartOption.otherDay
                    ? IconButton(
                        icon: const Icon(Icons.edit_calendar,
                            color: AppColors.accent,
                            semanticLabel: 'Cambiar el día'),
                        onPressed: () => _choose(PeriodStartOption.otherDay),
                      )
                    : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Duración estimada: $days ($source)',
          style: const TextStyle(fontSize: 15, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 6),
        const Text(
          'Solo se guarda el primer día. Los días siguientes se muestran '
          'como estimados hasta que los confirmes.',
          style: secondary,
        ),
        if (joinWarning != null) ...[
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            child: Text(
              joinWarning,
              style: const TextStyle(
                  fontSize: 14, color: AppColors.textPrimary),
            ),
          ),
        ],
        if (alreadyMarked) ...[
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            child: const Text(
              'Ese día ya está registrado.',
              style: TextStyle(fontSize: 14, color: AppColors.textPrimary),
            ),
          ),
        ],
        const SizedBox(height: 20),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: AppColors.background,
            minimumSize: const Size.fromHeight(48),
          ),
          onPressed:
              alreadyMarked ? null : () => Navigator.pop(context, day),
          child: const Text('Marcar mi período'),
        ),
      ],
    );
  }
}

class _SheetData {
  const _SheetData({required this.periodDays, required this.estimate});

  final List<String> periodDays;
  final PeriodLengthEstimate estimate;
}
