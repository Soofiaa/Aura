import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import '../data/notifications/notification_reconciler.dart';
import '../data/repositories/cycle_repository.dart';
import '../utils/notifications.dart';

class SettingsScreen extends StatefulWidget {
  /// Inyectables para tests (base en memoria / scheduler falso). En la
  /// app real se usan los singletons globales.
  final CycleRepository? repository;
  final NotificationScheduler? scheduler;

  const SettingsScreen({super.key, this.repository, this.scheduler});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  late final CycleRepository _repository = widget.repository ?? cycleRepository;
  late final NotificationScheduler _scheduler =
      widget.scheduler ?? notificationScheduler;

  bool _notificaciones = false;
  bool _recordatorioPeriodo = true;
  bool _recordatorioFertil = false;
  bool _mostrarDetalles = false;
  int _horaRecordatorio = 9;
  int _minutoRecordatorio = 0;

  // dark_mode todavia no tiene columna en app_settings (fase 2, punto 4):
  // queda como estado local de la pantalla, no persistido, igual que
  // antes no afectaba el tema de la app.
  bool _modoOscuro = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cargarPreferencias();
  }

  @override
  void dispose() {
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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'El permiso de notificaciones fue revocado desde Ajustes del '
          'sistema; se desactivaron los recordatorios.',
        ),
      ),
    );
  }

  Future<void> _cargarPreferencias() async {
    final settings = await _repository.getNotificationSettings();
    if (!mounted) return;
    setState(() {
      _notificaciones = settings.notificationsEnabled;
      _recordatorioPeriodo = settings.periodReminderEnabled;
      _recordatorioFertil = settings.fertileWindowRemindersEnabled;
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se activaron las notificaciones: permiso denegado.',
            ),
          ),
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

  Future<void> _cambiarMostrarDetalles(bool value) async {
    await _repository.setShowDetailsEnabled(value);
    if (!mounted) return;
    setState(() => _mostrarDetalles = value);
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

  Future<void> _probarNotificacion() async {
    await _scheduler.scheduleTestNotification(delay: const Duration(seconds: 10));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Notificación de prueba programada en 10 segundos.'),
      ),
    );
  }

  Future<void> _guardarPreferencias() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Preferencias guardadas 🩵")),
    );
  }

  Future<void> _confirmarYBorrarDatos() async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("¿Borrar todos los datos?"),
        content: const Text(
          "Se eliminaran todos los dias registrados, sintomas y ajustes. "
          "Esta accion no se puede deshacer.",
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

    await _repository.deleteAllData();

    if (!mounted) return;
    setState(() {
      _notificaciones = false;
      _recordatorioPeriodo = true;
      _recordatorioFertil = false;
      _mostrarDetalles = false;
      _horaRecordatorio = 9;
      _minutoRecordatorio = 0;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Datos borrados correctamente 💧")),
    );
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
            activeColor: const Color(0xFFA8D8EA),
            value: _notificaciones,
            onChanged: (val) => _cambiarNotificacionesGeneral(val),
          ),

          SwitchListTile(
            title: const Text("Recordatorio de período"),
            subtitle: const Text(
              "Un aviso el día antes del inicio estimado de tu período.",
            ),
            activeColor: const Color(0xFFA8D8EA),
            value: _recordatorioPeriodo,
            onChanged: _notificaciones
                ? (val) => _cambiarRecordatorioPeriodo(val)
                : null,
          ),

          SwitchListTile(
            title: const Text("Ventana fértil"),
            subtitle: const Text(
              "Aviso opcional al comenzar tu ventana de mayor fertilidad "
              "(estimación, no método anticonceptivo).",
            ),
            activeColor: const Color(0xFFA8D8EA),
            value: _recordatorioFertil,
            onChanged:
                _notificaciones ? (val) => _cambiarRecordatorioFertil(val) : null,
          ),

          SwitchListTile(
            title: const Text("Mostrar detalles en la notificación"),
            subtitle: const Text(
              "Sin esto, la notificación solo dice 'Aura: recordatorio'. "
              "El detalle puede verse en relojes u otros dispositivos "
              "conectados.",
            ),
            activeColor: const Color(0xFFA8D8EA),
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

          if (kDebugMode) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _probarNotificacion,
              icon: const Icon(Icons.bug_report),
              label: const Text("Probar notificación en 10 segundos"),
            ),
          ],

          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 10),

          const Text(
            "Preferencias generales",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),

          // 🌙 Tema
          SwitchListTile(
            title: const Text("Modo oscuro"),
            subtitle: const Text("Reduce brillo y usa fondo oscuro"),
            activeColor: const Color(0xFFA8D8EA),
            value: _modoOscuro,
            onChanged: (val) {
              setState(() => _modoOscuro = val);
            },
          ),

          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _guardarPreferencias,
            icon: const Icon(Icons.save),
            label: const Text("Guardar preferencias"),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFA8D8EA),
              foregroundColor: Colors.black,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),

          const SizedBox(height: 40),
          const Divider(),
          const SizedBox(height: 20),

          const Text(
            "Gestión de datos",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: _confirmarYBorrarDatos,
            icon: const Icon(Icons.delete_forever),
            label: const Text("Borrar todos los datos"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.pinkAccent.withValues(alpha: 0.8),
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),

          const SizedBox(height: 20),
          const Text(
            "Versión 1.0.0 • Aura 🌸",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
