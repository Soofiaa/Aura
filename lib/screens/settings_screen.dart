import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/backup/backup_file_gateway.dart' show BackupFileGateway;
import '../data/backup/backup_reminder_store.dart' show BackupReminderStore;
import '../data/backup/backup_service.dart';
import '../data/backup/auto_drive_backup_service.dart';
import '../data/device_settings_store.dart';
import '../data/models/day_enums.dart';
import '../data/notifications/notification_reconciler.dart';
import '../data/repositories/cycle_repository.dart';
import '../domain/contraceptive.dart';
import '../domain/cycle_predictor.dart' show PregnancySpan;
import '../domain/notification_planner.dart';
import '../utils/android_system.dart';
import '../utils/app_version.dart';
import '../utils/aura_localizations.dart';
import '../utils/colors.dart';
import '../utils/date_labels.dart';
import '../utils/day_key.dart';
import '../utils/notifications.dart';
import 'backup_section.dart';
import 'drive_backup_section.dart';
import '../utils/app_snackbar.dart';

/// Politica de privacidad publicada (GitHub Pages). Se abre en el
/// navegador del telefono con una intencion del sistema.
const String privacyPolicyUrl = 'https://soofiaa.github.io/Aura/privacy.html';

class SettingsScreen extends StatefulWidget {
  /// Inyectables para tests (base en memoria / scheduler falso /
  /// directorios temporales). En la app real se usan los singletons
  /// globales.
  final CycleRepository? repository;
  final NotificationScheduler? scheduler;
  final BackupService? backupService;
  final BackupFileGateway? fileGateway;
  final BackupReminderStore? reminderStore;
  final DeviceSettingsStore? deviceSettings;
  final AndroidSystem? androidSystem;
  final AutoDriveBackupService? driveBackup;

  const SettingsScreen({
    super.key,
    this.repository,
    this.scheduler,
    this.backupService,
    this.fileGateway,
    this.reminderStore,
    this.deviceSettings,
    this.androidSystem,
    this.driveBackup,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  late final CycleRepository _repository = widget.repository ?? cycleRepository;
  late final NotificationScheduler _scheduler =
      widget.scheduler ?? notificationScheduler;
  late final BackupService _backupService =
      widget.backupService ?? backupService;
  late final DeviceSettingsStore _deviceSettings =
      widget.deviceSettings ?? deviceSettingsStore;
  late final AndroidSystem _system = widget.androidSystem ?? androidSystem;
  late final AutoDriveBackupService _driveBackup =
      widget.driveBackup ?? autoDriveBackupService;

  // Ajustes de este telefono (aviso de atraso y Recientes), en vivo como
  // los demas. Null si todavia no se leyeron.
  StreamSubscription<DeviceSettings>? _deviceSub;
  DeviceSettings? _ajustesTelefono;

  // Los interruptores siguen a app_settings en vivo: importar un
  // respaldo (o deshacerlo) cambia los ajustes por fuera de esta
  // pantalla, que dentro del IndexedStack nunca se reconstruye.
  StreamSubscription<NotificationSettings>? _settingsSub;
  // Duracion habitual (HU-01): tambien en vivo, por el mismo motivo
  // (importar un respaldo v4 trae su propio valor). Null hasta la
  // primera lectura.
  StreamSubscription<PredictionInputs>? _duracionSub;
  int? _duracionHabitual;
  // Modo embarazo: los mismos datos en vivo (embarazos y ciclos).
  PredictionInputs? _inputs;

  bool _notificaciones = false;
  bool _recordatorioPeriodo = true;
  bool _recordatorioFertil = false;
  // "Mostrar ovulacion y ventana fertil" (HU-05, H5-3).
  bool _mostrarFertil = true;
  bool _mostrarDetalles = false;
  int _horaRecordatorio = 9;
  int _minutoRecordatorio = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _settingsSub =
        _repository.watchNotificationSettings().listen(_aplicarPreferencias);
    _duracionSub = _repository.watchPredictionInputs().listen((inputs) {
      if (!mounted) return;
      setState(() {
        _duracionHabitual = inputs.typicalPeriodLengthDays;
        _inputs = inputs;
      });
    });
    _deviceSub = _deviceSettings.watch().listen((ajustes) {
      if (!mounted) return;
      setState(() => _ajustesTelefono = ajustes);
    }, onError: (Object _) {
      // Sin leer el archivo se muestran los valores por defecto.
      if (!mounted) return;
      setState(() => _ajustesTelefono ??= const DeviceSettings());
    });
  }

  @override
  void dispose() {
    _settingsSub?.cancel();
    _duracionSub?.cancel();
    _deviceSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _revisarPermisoAlVolver();
    }
  }

  /// Android permite revocar el permiso de notificaciones desde Ajustes
  /// del sistema sin pasar por la app. Si eso paso mientras estabamos en
  /// segundo plano, el interruptor general en pantalla quedaria
  /// mostrando "activado" sin que en los hechos vaya a notificar nada.
  Future<void> _revisarPermisoAlVolver() async {
    if (!_notificaciones) return;
    final tienePermiso = await _scheduler.hasPermission();
    if (tienePermiso || !mounted) return;

    setState(() => _notificaciones = false);
    await _guardar(() => _repository.setNotificationsEnabled(false));
    if (!mounted) return;
    showAppSnackBar(
      context,
      tr('El permiso de notificaciones fue revocado desde Ajustes del '
      'sistema; se desactivaron los recordatorios.',
      'Notification permission was revoked in system settings, so '
      'reminders were turned off.'),
      action: _accionAbrirAjustes(),
    );
  }

  /// "Abrir ajustes": los ajustes de notificaciones de Aura en Android.
  /// Si se nego el permiso dos veces, Android ya no vuelve a preguntar y
  /// es el unico camino para activarlo.
  SnackBarAction _accionAbrirAjustes() => SnackBarAction(
        label: tr('Abrir ajustes', 'Open settings'),
        onPressed: () => _system.openNotificationSettings(),
      );

  /// Guarda un ajuste. Si falla, avisa y devuelve false; quien llama no
  /// cambia lo que muestra, y el stream de ajustes deja el valor guardado.
  Future<bool> _guardar(Future<void> Function() escritura) async {
    try {
      await escritura();
      return true;
    } catch (_) {
      if (mounted) {
        showAppSnackBar(
            context, tr('No se pudo guardar el cambio. Inténtalo de nuevo.',
                "Couldn't save the change. Please try again."));
      }
      return false;
    }
  }

  void _aplicarPreferencias(NotificationSettings settings) {
    if (!mounted) return;
    setState(() {
      _notificaciones = settings.notificationsEnabled;
      _recordatorioPeriodo = settings.periodReminderEnabled;
      _recordatorioFertil = settings.fertileWindowRemindersEnabled;
      _mostrarFertil = settings.showFertileWindow;
      _mostrarDetalles = settings.showDetailsEnabled;
      _horaRecordatorio = settings.reminderHour;
      _minutoRecordatorio = settings.reminderMinute;
    });
  }

  Future<void> _cambiarNotificacionesGeneral(bool value) async {
    if (value) {
      final concedido = await _scheduler.requestPermission();
      if (!concedido) {
        await _guardar(() => _repository.setNotificationsEnabled(false));
        if (!mounted) return;
        setState(() => _notificaciones = false);
        showAppSnackBar(
          context,
          tr('No se activaron las notificaciones: permiso denegado.',
              "Notifications weren't turned on: permission denied."),
          action: _accionAbrirAjustes(),
        );
        return;
      }
    }
    if (!await _guardar(() => _repository.setNotificationsEnabled(value))) {
      return;
    }
    if (!mounted) return;
    setState(() => _notificaciones = value);
  }

  Future<void> _cambiarRecordatorioPeriodo(bool value) async {
    if (!await _guardar(() => _repository.setPeriodReminderEnabled(value))) {
      return;
    }
    if (!mounted) return;
    setState(() => _recordatorioPeriodo = value);
  }

  Future<void> _cambiarRecordatorioFertil(bool value) async {
    if (!await _guardar(
        () => _repository.setFertileWindowRemindersEnabled(value))) {
      return;
    }
    if (!mounted) return;
    setState(() => _recordatorioFertil = value);
  }

  Future<void> _cambiarAvisoAtraso(bool value) async {
    if (!await _guardar(() => _deviceSettings.setAvisoAtraso(value))) return;
    if (!mounted) return;
    setState(() => _ajustesTelefono =
        (_ajustesTelefono ?? const DeviceSettings()).copyWith(avisoAtraso: value));
  }

  Future<void> _cambiarRecordatorioDiario(bool value) async {
    if (!await _guardar(() => _deviceSettings.setRecordatorioDiario(value))) {
      return;
    }
    if (!mounted) return;
    setState(() => _ajustesTelefono = (_ajustesTelefono ??
            const DeviceSettings())
        .copyWith(recordatorioDiario: value));
  }

  /// Metodo, el dia de inicio (salvo la pastilla) y la hora; o apagarlo.
  Future<void> _elegirAnticonceptivo() async {
    final actual = _ajustesTelefono?.anticonceptivo;
    // Un registro para distinguir "Apagado" (null) de cerrar el dialogo.
    final eleccion = await showDialog<(ContraceptiveMethod?,)>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(tr("Recordatorio de anticonceptivo",
            "Birth control reminder")),
        children: [
          RadioGroup<ContraceptiveMethod?>(
            groupValue: actual?.method,
            onChanged: (v) => Navigator.pop(context, (v,)),
            child: Column(
              children: [
                RadioListTile<ContraceptiveMethod?>(
                    value: null, title: Text(tr("Apagado", "Off"))),
                for (final m in ContraceptiveMethod.values)
                  RadioListTile<ContraceptiveMethod?>(
                      value: m, title: Text(m.label)),
              ],
            ),
          ),
        ],
      ),
    );
    if (eleccion == null || !mounted) return;
    final metodo = eleccion.$1;
    ContraceptiveReminder? nuevo;
    if (metodo != null) {
      final hoy = DateTime.now();
      String? inicio;
      if (metodo != ContraceptiveMethod.pill) {
        var previo = actual?.method == metodo ? actual?.startDate : null;
        final primero = DayKey.addDays(_hoy, -365);
        // Un inicio de hace mas de un ano: el ultimo inicio de ciclo dentro
        // del rango, para no correr el calendario de la usuaria.
        while (previo != null && DayKey.isBefore(previo, primero)) {
          previo = DayKey.addDays(previo, metodo.cycleDays);
        }
        final dia = await showDatePicker(
          context: context,
          helpText: switch (metodo) {
            ContraceptiveMethod.patch => tr(
                "Día en que pusiste el primer parche de este ciclo",
                "Day you put on this cycle's first patch"),
            ContraceptiveMethod.ring => tr(
                "Día en que te pusiste el anillo de este ciclo",
                "Day you inserted this cycle's ring"),
            _ => tr("Día de tu última inyección", "Day of your last injection"),
          },
          initialDate: previo != null ? DateTime.parse(previo) : hoy,
          firstDate: DateTime.parse(primero),
          lastDate: hoy.add(const Duration(days: 31)),
          currentDate: hoy,
        );
        if (dia == null || !mounted) return;
        inicio = DayKey.fromDate(dia);
      }
      final hora = await showTimePicker(
        context: context,
        helpText: tr("Hora del aviso", "Reminder time"),
        initialTime: actual != null
            ? TimeOfDay(hour: actual.hour, minute: actual.minute)
            : TimeOfDay(hour: _horaRecordatorio, minute: _minutoRecordatorio),
      );
      if (hora == null || !mounted) return;
      nuevo = ContraceptiveReminder(
          method: metodo,
          startDate: inicio,
          hour: hora.hour,
          minute: hora.minute);
    }
    if (nuevo == actual) return;
    if (!await _guardar(() => _deviceSettings.setAnticonceptivo(nuevo))) {
      return;
    }
    if (!mounted) return;
    setState(() => _ajustesTelefono = (_ajustesTelefono ??
            const DeviceSettings())
        .copyWith(anticonceptivo: () => nuevo));
  }

  static String _nombreTema(ThemeMode tema) => switch (tema) {
        ThemeMode.system => tr("Según el teléfono", "System default"),
        ThemeMode.light => tr("Claro", "Light"),
        ThemeMode.dark => tr("Oscuro", "Dark"),
      };

  /// main.dart escucha el mismo almacen y cambia el tema.
  Future<void> _elegirTema() async {
    final actual = _ajustesTelefono?.tema ?? ThemeMode.system;
    final tema = await showDialog<ThemeMode>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(tr("Tema", "Theme")),
        children: [
          RadioGroup<ThemeMode>(
            groupValue: actual,
            onChanged: (v) => Navigator.pop(context, v),
            child: Column(
              children: [
                for (final m in ThemeMode.values)
                  RadioListTile<ThemeMode>(
                      value: m, title: Text(_nombreTema(m))),
              ],
            ),
          ),
        ],
      ),
    );
    if (tema == null || tema == actual) return;
    if (!await _guardar(() => _deviceSettings.setTema(tema))) return;
    if (!mounted) return;
    setState(() => _ajustesTelefono =
        (_ajustesTelefono ?? const DeviceSettings()).copyWith(tema: tema));
  }

  /// main.dart escucha el mismo almacen y aplica FLAG_SECURE.
  Future<void> _cambiarOcultarEnRecientes(bool value) async {
    if (!await _guardar(() => _deviceSettings.setOcultarEnRecientes(value))) {
      return;
    }
    if (!mounted) return;
    setState(() => _ajustesTelefono = (_ajustesTelefono ?? const DeviceSettings())
        .copyWith(ocultarEnRecientes: value));
  }

  /// main.dart (startHomeWidgetSync) escucha el mismo almacen.
  Future<void> _cambiarWidgetDiscreto(bool value) async {
    if (!await _guardar(() => _deviceSettings.setWidgetDiscreto(value))) {
      return;
    }
    if (!mounted) return;
    setState(() => _ajustesTelefono = (_ajustesTelefono ?? const DeviceSettings())
        .copyWith(widgetDiscreto: value));
  }

  /// Solo guarda el ajuste: el NotificationReconciler (que escucha
  /// app_settings) quita el aviso fertil del plan y el scheduler lo
  /// cancela. No toca "Ventana fertil": al volver a encenderlo, ese
  /// recordatorio vuelve a su valor guardado.
  Future<void> _cambiarMostrarFertil(bool value) async {
    if (!await _guardar(() => _repository.setShowFertileWindow(value))) return;
    if (!mounted) return;
    setState(() => _mostrarFertil = value);
  }

  Future<void> _cambiarMostrarDetalles(bool value) async {
    if (!await _guardar(() => _repository.setShowDetailsEnabled(value))) return;
    if (!mounted) return;
    setState(() => _mostrarDetalles = value);
  }

  /// Suma [delta] a la duracion habitual. Los botones se deshabilitan en
  /// los limites, asi que nunca se pide un valor fuera de 1 a 15.
  Future<void> _cambiarDuracion(int delta) async {
    final actual = _duracionHabitual;
    if (actual == null) return;
    final nueva = actual + delta;
    if (nueva < minTypicalPeriodLength || nueva > maxTypicalPeriodLength) {
      return;
    }
    setState(() => _duracionHabitual = nueva);
    if (!await _guardar(() => _repository.setTypicalPeriodLength(nueva)) &&
        mounted) {
      setState(() => _duracionHabitual = actual);
    }
  }

  Widget _seccionTuCiclo() {
    final duracion = _duracionHabitual;
    final textoDias = duracion == null
        ? ''
        : (duracion == 1
            ? tr('1 día', '1 day')
            : tr('$duracion días', '$duracion days'));
    final puedeBajar =
        duracion != null && duracion > minTypicalPeriodLength;
    final puedeSubir =
        duracion != null && duracion < maxTypicalPeriodLength;
    const tamanoMinimo = BoxConstraints(minWidth: 48, minHeight: 48);
    final embarazo =
        _inputs?.isPregnant ?? false ? _inputs!.pregnancies.last : null;
    final ultimoTerminado = embarazo == null &&
            (_inputs?.pregnancies.isNotEmpty ?? false)
        ? _inputs!.pregnancies.last
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr("Tu ciclo", "Your cycle"),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        Text(
          tr("Duración habitual del período", "Usual period length"),
          style: TextStyle(fontSize: 16, color: context.aura.textPrimary),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            IconButton(
              key: const Key('duracion_menos'),
              constraints: tamanoMinimo,
              color: AppColors.accentStrong,
              disabledColor: context.aura.textSecondary,
              icon: Icon(Icons.remove_circle_outline,
                  semanticLabel: tr("Disminuir duración", "Decrease length")),
              onPressed: puedeBajar ? () => _cambiarDuracion(-1) : null,
            ),
            Expanded(
              child: Semantics(
                container: true,
                label: duracion == null
                    ? null
                    : tr("Duración habitual del período: $textoDias",
                        "Usual period length: $textoDias"),
                liveRegion: true,
                excludeSemantics: true,
                child: Text(
                  textoDias,
                  key: const Key('duracion_valor'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: context.aura.textPrimary,
                  ),
                ),
              ),
            ),
            IconButton(
              key: const Key('duracion_mas'),
              constraints: tamanoMinimo,
              color: AppColors.accentStrong,
              disabledColor: context.aura.textSecondary,
              icon: Icon(Icons.add_circle_outline,
                  semanticLabel: tr("Aumentar duración", "Increase length")),
              onPressed: puedeSubir ? () => _cambiarDuracion(1) : null,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          tr(
          "Aura la usa para estimar cuántos días dura tu período "
          "mientras todavía no tienes períodos terminados registrados; "
          "después usa el promedio de los tuyos. Cambiarla no modifica "
          "tus registros.",
          "Aura uses this to estimate how many days your period lasts "
          "until you've logged some complete periods; after that it uses "
          "your own average. Changing it doesn't affect your logs."),
          style: TextStyle(fontSize: 14, color: context.aura.textSecondary),
        ),
        const SizedBox(height: 10),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(tr("Mostrar ovulación y ventana fértil",
              "Show ovulation and fertile window")),
          subtitle: Text(tr(
            "Son estimaciones, no un método anticonceptivo. Si lo apagas, "
            "no se muestran en Inicio ni en el Calendario.",
            "These are estimates, not a method of birth control. If you turn "
            "this off, they won't appear on Home or in the Calendar.",
          )),
          value: _mostrarFertil,
          onChanged: _cambiarMostrarFertil,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(tr("Modo embarazo", "Pregnancy mode")),
          subtitle: Text(embarazo == null
              ? tr(
                  "Muestra las semanas de embarazo y pausa las predicciones "
                      "y los avisos del ciclo.",
                  "Shows how far along you are and pauses cycle predictions "
                      "and reminders.")
              : tr(
                  "Desde tu última regla del "
                      "${dayMonthLabelWithYear(embarazo.start, today: _hoy)}. "
                      "Las predicciones vuelven cuando registres un período "
                      "después de terminarlo.",
                  "Since your last period on "
                      "${dayMonthLabelWithYear(embarazo.start, today: _hoy)}. "
                      "Predictions resume when you log a period after "
                      "ending it.")),
          value: embarazo != null,
          onChanged: _inputs == null
              ? null
              : (on) => on ? _iniciarEmbarazo() : _terminarEmbarazo(embarazo!),
        ),
        // shortcut: solo se corrige el ultimo terminado; si hace falta
        // corregir uno anterior, agregar una lista de embarazos.
        if (ultimoTerminado != null)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr("Corregir último embarazo", "Edit last pregnancy")),
            subtitle: Text(tr(
                "Del ${dayMonthLabelWithYear(ultimoTerminado.start, today: _hoy)} "
                    "al ${dayMonthLabelWithYear(ultimoTerminado.end!, today: _hoy)}.",
                "From ${dayMonthLabelWithYear(ultimoTerminado.start, today: _hoy)} "
                    "to ${dayMonthLabelWithYear(ultimoTerminado.end!, today: _hoy)}.")),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () => _terminarEmbarazo(ultimoTerminado),
          ),
      ],
    );
  }

  String get _hoy => DayKey.fromDate(DateTime.now());

  /// Pide la fecha de la ultima regla (por defecto, el inicio del ultimo
  /// periodo registrado). No puede ser antes del fin del embarazo anterior.
  Future<void> _iniciarEmbarazo() async {
    final inputs = _inputs!;
    final hoy = DateTime.parse(_hoy);
    var primero = hoy.subtract(const Duration(days: 300));
    final finAnterior =
        inputs.pregnancies.isEmpty ? null : inputs.pregnancies.last.end;
    if (finAnterior != null) {
      final despues = DateTime.parse(DayKey.addDays(finAnterior, 1));
      if (despues.isAfter(primero)) primero = despues;
    }
    if (primero.isAfter(hoy)) {
      showAppSnackBar(
          context,
          tr("Puedes activarlo desde mañana.",
              "You can turn it on starting tomorrow."));
      return;
    }
    var inicial = inputs.cycles.isEmpty
        ? hoy
        : DateTime.parse(inputs.cycles
            .map((c) => c.startDate)
            .reduce((a, b) => DayKey.isBefore(a, b) ? b : a));
    if (inicial.isBefore(primero)) inicial = hoy;
    final elegido = await showDatePicker(
      context: context,
      helpText: tr("Primer día de tu última regla",
          "First day of your last period"),
      initialDate: inicial,
      firstDate: primero,
      lastDate: hoy,
      currentDate: hoy,
    );
    if (elegido == null || !mounted) return;
    await _guardar(() => _repository.startPregnancy(DayKey.fromDate(elegido)));
  }

  /// Como termino (o "lo active por error", que lo borra) y cuando. Sin
  /// textos de celebracion: el aviso es el mismo para cualquier final.
  /// Con un embarazo ya terminado, corrige ambas cosas o lo borra.
  Future<void> _terminarEmbarazo(PregnancySpan embarazo) async {
    final terminado = embarazo.end != null;
    const porError = 'porError';
    final eleccion = await showDialog<Object>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(terminado
            ? tr("Corregir último embarazo", "Edit last pregnancy")
            : tr("Terminar modo embarazo", "End pregnancy mode")),
        children: [
          for (final o in PregnancyOutcome.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, o),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(o.label),
              ),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, porError),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                  terminado
                      ? tr("Borrar este embarazo", "Delete this pregnancy")
                      : tr("Lo activé por error", "I turned it on by mistake"),
                  style: TextStyle(color: context.aura.textSecondary)),
            ),
          ),
        ],
      ),
    );
    if (eleccion == null || !mounted) return;
    if (eleccion == porError) {
      if (terminado && !await _confirmarBorrarEmbarazo()) return;
      await _guardar(() => _repository.deletePregnancy(embarazo.start));
      return;
    }
    final hoy = DateTime.parse(_hoy);
    final fin = await showDatePicker(
      context: context,
      helpText: tr("¿Cuándo terminó?", "When did it end?"),
      // Un fin futuro (respaldo restaurado) queda fuera del rango.
      initialDate: terminado && DayKey.isBefore(embarazo.end!, _hoy)
          ? DateTime.parse(embarazo.end!)
          : hoy,
      firstDate: DateTime.parse(embarazo.start),
      lastDate: hoy,
      currentDate: hoy,
    );
    if (fin == null || !mounted) return;
    final outcome = eleccion as PregnancyOutcome;
    final guardado = await _guardar(() => terminado
        ? _repository.editEndedPregnancy(
            embarazo.start, DayKey.fromDate(fin), outcome)
        : _repository.endPregnancy(DayKey.fromDate(fin), outcome));
    if (guardado && mounted) {
      showAppSnackBar(
          context,
          terminado
              ? tr("Cambio guardado.", "Change saved.")
              : tr("Modo embarazo terminado.", "Pregnancy mode ended."));
    }
  }

  Future<bool> _confirmarBorrarEmbarazo() async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(tr("¿Borrar este embarazo?", "Delete this pregnancy?")),
          content: Text(tr(
              "Los ciclos de esas fechas volverán a contar en tus promedios. "
                  "No se puede deshacer.",
              "Cycles from those dates will count toward your averages "
                  "again. This can't be undone.")),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr("Cancelar", "Cancel")),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr("Borrar", "Delete")),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _elegirHora() async {
    final elegido = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _horaRecordatorio, minute: _minutoRecordatorio),
    );
    if (elegido == null) return;
    if (!await _guardar(() => _repository.setReminderTime(
        hour: elegido.hour, minute: elegido.minute))) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _horaRecordatorio = elegido.hour;
      _minutoRecordatorio = elegido.minute;
    });
  }

  /// Abre la politica de privacidad en una app externa (el navegador).
  /// Si no hay app que la abra (o la plataforma falla), deja la
  /// direccion visible para copiarla a mano.
  Future<void> _abrirPoliticaDePrivacidad() async {
    bool abierto;
    try {
      abierto = await launchUrl(
        Uri.parse(privacyPolicyUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      abierto = false;
    }
    if (abierto || !mounted) return;
    showAppSnackBar(
      context,
      tr('No se pudo abrir el enlace. Puedes abrirlo desde un navegador: '
      '$privacyPolicyUrl',
      "Couldn't open the link. You can open it in a browser: "
      '$privacyPolicyUrl'),
    );
  }

  Future<void> _confirmarYBorrarDatos() async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr("¿Borrar todos los datos?", "Delete all data?")),
        content: Text(tr(
          "Se eliminarán todos los días registrados, síntomas y ajustes, "
          "y la copia guardada antes de la última importación. "
          "Esta acción no se puede deshacer.",
          "This deletes every logged day, your symptoms and settings, "
          "and the copy saved before your last import. "
          "This can't be undone.",
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr("Cancelar", "Cancel")),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              tr("Borrar todo", "Delete all"),
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirmado != true) return;

    try {
      await _backupService.deleteAllData();
      // HU-09: los ajustes del respaldo en Drive (cuenta y clave sellada)
      // tambien son datos de la usuaria y se borran con todo. La seccion
      // los ve llegar por watch().
      await _driveBackup.deleteAllData();
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        tr("No se pudieron borrar todos los datos. Inténtalo de nuevo.",
            "Couldn't delete all data. Please try again."),
      );
      return;
    }

    if (!mounted) return;
    // BackupSection vuelve a leer si hay copia previa (ya no la hay).
    setState(() => _datosBorrados++);
    showAppSnackBar(context,
        tr("Datos borrados correctamente.", "Data deleted successfully."));
  }

  int _datosBorrados = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr("Ajustes", "Settings")),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _seccionTuCiclo(),

          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 20),

          Text(
            tr("Notificaciones", "Notifications"),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),

          SwitchListTile(
            title: Text(tr("Notificaciones", "Notifications")),
            subtitle: Text(tr(
              "Interruptor general. Actívalo para habilitar los "
              "recordatorios de abajo.",
              "Main switch. Turn it on to enable the reminders below.",
            )),
            value: _notificaciones,
            onChanged: (val) => _cambiarNotificacionesGeneral(val),
          ),

          SwitchListTile(
            title: Text(tr("Recordatorio de período", "Period reminder")),
            subtitle: Text(tr(
              "Un aviso el día antes del inicio estimado de tu período.",
              "A heads-up the day before your period is estimated to start.",
            )),
            value: _recordatorioPeriodo,
            onChanged: _notificaciones
                ? (val) => _cambiarRecordatorioPeriodo(val)
                : null,
          ),

          // Necesita tambien "Mostrar ovulacion y ventana fertil" (Tu
          // ciclo). Si esta apagado, se ve apagado y deshabilitado, pero
          // conserva su valor guardado.
          SwitchListTile(
            title: Text(tr("Ventana fértil", "Fertile window")),
            subtitle: _mostrarFertil
                ? Text(tr(
                    "Aviso opcional al comenzar tu ventana de mayor fertilidad "
                    "(estimación, no método anticonceptivo). Solo se envía "
                    "cuando tu estimación es confiable.",
                    "Optional heads-up when your fertile window begins "
                    "(an estimate, not birth control). Only sent when your "
                    "estimate is reliable.",
                  ))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr(
                        "Aviso opcional al comenzar tu ventana de mayor "
                        "fertilidad (estimación, no método anticonceptivo).",
                        "Optional heads-up when your fertile window begins "
                        "(an estimate, not birth control).",
                      )),
                      const SizedBox(height: 4),
                      Text(
                        tr("Para usarlo, activa la opción Mostrar ovulación y "
                        "ventana fértil en Tu ciclo.",
                        "To use it, turn on Show ovulation and fertile window "
                        "in Your cycle."),
                        style:
                            TextStyle(fontSize: 13, color: context.aura.textSecondary),
                      ),
                    ],
                  ),
            value: _recordatorioFertil && _mostrarFertil,
            onChanged: _notificaciones && _mostrarFertil
                ? (val) => _cambiarRecordatorioFertil(val)
                : null,
          ),

          SwitchListTile(
            title: Text(tr("Aviso si tu período se atrasa",
                "Heads-up if your period is late")),
            subtitle: Text(tr(
              "Un aviso el primer día de atraso, por si te llegó y no lo "
              "registraste.",
              "A heads-up on the first late day, in case it started and you "
              "didn't log it.",
            )),
            value: _ajustesTelefono?.avisoAtraso ?? false,
            onChanged: _notificaciones && _ajustesTelefono != null
                ? _cambiarAvisoAtraso
                : null,
          ),

          SwitchListTile(
            title: Text(tr("Recordatorio diario", "Daily reminder")),
            subtitle: Text(tr(
              "Un aviso cada día a la hora del recordatorio, si todavía no "
              "registraste ese día.",
              "A heads-up every day at the reminder time, if you haven't "
              "logged that day yet.",
            )),
            value: _ajustesTelefono?.recordatorioDiario ?? false,
            onChanged: _notificaciones && _ajustesTelefono != null
                ? _cambiarRecordatorioDiario
                : null,
          ),

          ListTile(
            title: Text(tr("Recordatorio de anticonceptivo",
                "Birth control reminder")),
            subtitle: Text(switch (_ajustesTelefono?.anticonceptivo) {
              null => tr("Apagado", "Off"),
              final a => '${a.method.label} · '
                  '${a.hour.toString().padLeft(2, '0')}:'
                  '${a.minute.toString().padLeft(2, '0')}',
            }),
            trailing: const Icon(Icons.medication_outlined),
            enabled: _notificaciones && _ajustesTelefono != null,
            onTap: _elegirAnticonceptivo,
          ),

          SwitchListTile(
            title: Text(tr("Mostrar detalles en la notificación",
                "Show details in notifications")),
            subtitle: Text(tr(
              "Sin esto, la notificación solo dice que es un recordatorio "
              "de Aura. El detalle puede verse en relojes u otros "
              "dispositivos conectados.",
              "Without this, the notification only says it's a reminder "
              "from Aura. Details may be visible on watches or other "
              "connected devices.",
            )),
            value: _mostrarDetalles,
            onChanged:
                _notificaciones ? (val) => _cambiarMostrarDetalles(val) : null,
          ),

          ListTile(
            title: Text(tr("Hora del recordatorio", "Reminder time")),
            subtitle: Text(
              '${_horaRecordatorio.toString().padLeft(2, '0')}:'
              '${_minutoRecordatorio.toString().padLeft(2, '0')}',
            ),
            trailing: const Icon(Icons.access_time),
            enabled: _notificaciones,
            onTap: _notificaciones ? _elegirHora : null,
          ),

          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 20),

          Text(
            tr("Apariencia", "Appearance"),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr("Tema", "Theme")),
            subtitle: Text(_nombreTema(
                _ajustesTelefono?.tema ?? ThemeMode.system)),
            trailing: const Icon(Icons.brightness_6_outlined),
            enabled: _ajustesTelefono != null,
            onTap: _elegirTema,
          ),

          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 20),

          Text(
            tr("Privacidad", "Privacy"),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          SwitchListTile(
            title: Text(tr("Ocultar Aura en Recientes", "Hide Aura in Recents")),
            subtitle: Text(tr(
              "La vista previa de Aura en Recientes sale en blanco y no se "
              "pueden hacer capturas de pantalla de la app.",
              "Aura's preview in Recents is blank, and screenshots of the "
              "app are blocked.",
            )),
            value: _ajustesTelefono?.ocultarEnRecientes ?? true,
            onChanged:
                _ajustesTelefono != null ? _cambiarOcultarEnRecientes : null,
          ),
          SwitchListTile(
            title: Text(tr("Widget discreto", "Discreet widget")),
            subtitle: Text(tr(
              "El widget de Aura en la pantalla de inicio no muestra datos, "
              "solo \"Aura\".",
              "Aura's home screen widget shows no data, just \"Aura\".",
            )),
            value: _ajustesTelefono?.widgetDiscreto ?? false,
            onChanged: _ajustesTelefono != null ? _cambiarWidgetDiscreto : null,
          ),

          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 20),

          Text(
            tr("Tus datos", "Your data"),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          BackupSection(
            key: ValueKey(_datosBorrados),
            service: _backupService,
            gateway: widget.fileGateway,
            reminderStore: widget.reminderStore,
          ),
          const SizedBox(height: 10),
          DriveBackupSection(service: _driveBackup),
          const SizedBox(height: 20),
          // Accion destructiva: boton con borde en el color de error del
          // tema, compacto y menos prominente que "Crear respaldo". El
          // dialogo de confirmacion no cambia.
          Center(
            child: OutlinedButton.icon(
              key: const Key('borrar_todos_los_datos'),
              onPressed: _confirmarYBorrarDatos,
              icon: const Icon(Icons.delete_forever),
              label: Text(tr("Borrar todos los datos", "Delete all data")),
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
                side: BorderSide(color: Theme.of(context).colorScheme.error),
                minimumSize: const Size(48, 48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),

          const SizedBox(height: 20),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: Text(tr("Política de privacidad", "Privacy policy")),
            trailing: const Icon(Icons.open_in_new),
            onTap: _abrirPoliticaDePrivacidad,
          ),
          const SizedBox(height: 10),
          Text(
            tr("Versión $appVersionName • Aura", "Version $appVersionName • Aura"),
            textAlign: TextAlign.center,
            style: TextStyle(color: context.aura.textSecondary, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
