import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/backup/backup_file_gateway.dart' show BackupFileGateway;
import '../data/backup/backup_reminder_store.dart' show BackupReminderStore;
import '../data/backup/backup_service.dart';
import '../data/models/day_enums.dart';
import '../data/notifications/notification_reconciler.dart';
import '../data/repositories/cycle_repository.dart';
import '../domain/notification_planner.dart';
import '../utils/app_version.dart';
import '../utils/colors.dart';
import '../utils/notifications.dart';
import 'backup_section.dart';
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

  const SettingsScreen({
    super.key,
    this.repository,
    this.scheduler,
    this.backupService,
    this.fileGateway,
    this.reminderStore,
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

  // Los interruptores siguen a app_settings en vivo: importar un
  // respaldo (o deshacerlo) cambia los ajustes por fuera de esta
  // pantalla, que dentro del IndexedStack nunca se reconstruye.
  StreamSubscription<NotificationSettings>? _settingsSub;
  // Duracion habitual (HU-01): tambien en vivo, por el mismo motivo
  // (importar un respaldo v4 trae su propio valor). Null hasta la
  // primera lectura.
  StreamSubscription<PredictionInputs>? _duracionSub;
  int? _duracionHabitual;

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
      setState(() => _duracionHabitual = inputs.typicalPeriodLengthDays);
    });
  }

  @override
  void dispose() {
    _settingsSub?.cancel();
    _duracionSub?.cancel();
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
    await _repository.setNotificationsEnabled(false);
    if (!mounted) return;
    showAppSnackBar(
      context,
      'El permiso de notificaciones fue revocado desde Ajustes del '
      'sistema; se desactivaron los recordatorios.',
    );
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
        await _repository.setNotificationsEnabled(false);
        if (!mounted) return;
        setState(() => _notificaciones = false);
        showAppSnackBar(
          context,
          'No se activaron las notificaciones: permiso denegado.',
        );
        return;
      }
    }
    await _repository.setNotificationsEnabled(value);
    if (!mounted) return;
    setState(() => _notificaciones = value);
  }

  Future<void> _cambiarRecordatorioPeriodo(bool value) async {
    await _repository.setPeriodReminderEnabled(value);
    if (!mounted) return;
    setState(() => _recordatorioPeriodo = value);
  }

  Future<void> _cambiarRecordatorioFertil(bool value) async {
    await _repository.setFertileWindowRemindersEnabled(value);
    if (!mounted) return;
    setState(() => _recordatorioFertil = value);
  }

  /// Solo guarda el ajuste: el NotificationReconciler (que escucha
  /// app_settings) quita el aviso fertil del plan y el scheduler lo
  /// cancela. No toca "Ventana fertil": al volver a encenderlo, ese
  /// recordatorio vuelve a su valor guardado.
  Future<void> _cambiarMostrarFertil(bool value) async {
    await _repository.setShowFertileWindow(value);
    if (!mounted) return;
    setState(() => _mostrarFertil = value);
  }

  Future<void> _cambiarMostrarDetalles(bool value) async {
    await _repository.setShowDetailsEnabled(value);
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
    await _repository.setTypicalPeriodLength(nueva);
  }

  Widget _seccionTuCiclo() {
    final duracion = _duracionHabitual;
    final textoDias = duracion == null
        ? ''
        : (duracion == 1 ? '1 día' : '$duracion días');
    final puedeBajar =
        duracion != null && duracion > minTypicalPeriodLength;
    final puedeSubir =
        duracion != null && duracion < maxTypicalPeriodLength;
    const tamanoMinimo = BoxConstraints(minWidth: 48, minHeight: 48);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Tu ciclo",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        const Text(
          "Duración habitual del período",
          style: TextStyle(fontSize: 16, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            IconButton(
              key: const Key('duracion_menos'),
              constraints: tamanoMinimo,
              color: AppColors.accentStrong,
              disabledColor: AppColors.textSecondary,
              icon: const Icon(Icons.remove_circle_outline,
                  semanticLabel: "Disminuir duración"),
              onPressed: puedeBajar ? () => _cambiarDuracion(-1) : null,
            ),
            Expanded(
              child: Semantics(
                container: true,
                label: duracion == null
                    ? null
                    : "Duración habitual del período: $textoDias",
                liveRegion: true,
                excludeSemantics: true,
                child: Text(
                  textoDias,
                  key: const Key('duracion_valor'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ),
            IconButton(
              key: const Key('duracion_mas'),
              constraints: tamanoMinimo,
              color: AppColors.accentStrong,
              disabledColor: AppColors.textSecondary,
              icon: const Icon(Icons.add_circle_outline,
                  semanticLabel: "Aumentar duración"),
              onPressed: puedeSubir ? () => _cambiarDuracion(1) : null,
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          "Aura la usa para estimar cuántos días dura tu período "
          "mientras todavía no tienes períodos terminados registrados; "
          "después usa el promedio de los tuyos. Cambiarla no modifica "
          "tus registros.",
          style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 10),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text("Mostrar ovulación y ventana fértil"),
          subtitle: const Text(
            "Son estimaciones, no un método anticonceptivo. Si lo apagas, "
            "no se muestran en Inicio ni en el Calendario.",
          ),
          value: _mostrarFertil,
          onChanged: _cambiarMostrarFertil,
        ),
      ],
    );
  }

  Future<void> _elegirHora() async {
    final elegido = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _horaRecordatorio, minute: _minutoRecordatorio),
    );
    if (elegido == null) return;
    await _repository.setReminderTime(hour: elegido.hour, minute: elegido.minute);
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
      'No se pudo abrir el enlace. Puedes abrirlo desde un navegador: '
      '$privacyPolicyUrl',
    );
  }

  Future<void> _confirmarYBorrarDatos() async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("¿Borrar todos los datos?"),
        content: const Text(
          "Se eliminarán todos los días registrados, síntomas y ajustes, "
          "y la copia guardada antes de la última importación. "
          "Esta acción no se puede deshacer.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancelar"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              "Borrar todo",
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirmado != true) return;

    try {
      await _backupService.deleteAllData();
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        "No se pudieron borrar todos los datos. Inténtalo de nuevo.",
      );
      return;
    }

    if (!mounted) return;
    showAppSnackBar(context, "Datos borrados correctamente 💧");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Configuración"),
        backgroundColor: const Color(0xFFA8D8EA),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _seccionTuCiclo(),

          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 20),

          const Text(
            "Notificaciones",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),

          SwitchListTile(
            title: const Text("Notificaciones"),
            subtitle: const Text(
              "Interruptor general. Actívalo para habilitar los "
              "recordatorios de abajo.",
            ),
            value: _notificaciones,
            onChanged: (val) => _cambiarNotificacionesGeneral(val),
          ),

          SwitchListTile(
            title: const Text("Recordatorio de período"),
            subtitle: const Text(
              "Un aviso el día antes del inicio estimado de tu período.",
            ),
            value: _recordatorioPeriodo,
            onChanged: _notificaciones
                ? (val) => _cambiarRecordatorioPeriodo(val)
                : null,
          ),

          // Necesita tambien "Mostrar ovulacion y ventana fertil" (Tu
          // ciclo). Si esta apagado, se ve apagado y deshabilitado, pero
          // conserva su valor guardado.
          SwitchListTile(
            title: const Text("Ventana fértil"),
            subtitle: _mostrarFertil
                ? const Text(
                    "Aviso opcional al comenzar tu ventana de mayor fertilidad "
                    "(estimación, no método anticonceptivo). Solo se envía "
                    "cuando tu estimación es confiable.",
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Aviso opcional al comenzar tu ventana de mayor "
                        "fertilidad (estimación, no método anticonceptivo).",
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Para usarlo, activa «Mostrar ovulación y ventana "
                        "fértil» en Tu ciclo.",
                        style:
                            TextStyle(fontSize: 13, color: Colors.grey[700]),
                      ),
                    ],
                  ),
            value: _recordatorioFertil && _mostrarFertil,
            onChanged: _notificaciones && _mostrarFertil
                ? (val) => _cambiarRecordatorioFertil(val)
                : null,
          ),

          SwitchListTile(
            title: const Text("Mostrar detalles en la notificación"),
            subtitle: const Text(
              "Sin esto, la notificación solo dice 'Aura: recordatorio'. "
              "El detalle puede verse en relojes u otros dispositivos "
              "conectados.",
            ),
            value: _mostrarDetalles,
            onChanged:
                _notificaciones ? (val) => _cambiarMostrarDetalles(val) : null,
          ),

          ListTile(
            title: const Text("Hora del recordatorio"),
            subtitle: Text(
              '${_horaRecordatorio.toString().padLeft(2, '0')}:'
              '${_minutoRecordatorio.toString().padLeft(2, '0')}',
            ),
            trailing: const Icon(Icons.access_time),
            enabled: _notificaciones,
            onTap: _notificaciones ? _elegirHora : null,
          ),

          const SizedBox(height: 40),
          const Divider(),
          const SizedBox(height: 20),

          const Text(
            "Tus datos",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          BackupSection(
            service: _backupService,
            gateway: widget.fileGateway,
            reminderStore: widget.reminderStore,
          ),
          const SizedBox(height: 20),
          // Accion destructiva: boton con borde en el color de error del
          // tema, compacto y menos prominente que "Crear respaldo". El
          // dialogo de confirmacion no cambia.
          Center(
            child: OutlinedButton.icon(
              key: const Key('borrar_todos_los_datos'),
              onPressed: _confirmarYBorrarDatos,
              icon: const Icon(Icons.delete_forever),
              label: const Text("Borrar todos los datos"),
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
            title: const Text("Política de privacidad"),
            trailing: const Icon(Icons.open_in_new),
            onTap: _abrirPoliticaDePrivacidad,
          ),
          const SizedBox(height: 10),
          const Text(
            "Versión $appVersionName • Aura 🌸",
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
