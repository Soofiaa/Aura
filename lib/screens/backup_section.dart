import 'package:flutter/material.dart';

import '../data/backup/backup_file_gateway.dart';
import '../data/backup/backup_reminder_store.dart';
import '../data/backup/backup_service.dart';
import '../domain/backup_codec.dart';
import '../domain/backup_reminder.dart';
import '../utils/date_labels.dart';
import '../utils/day_key.dart';
import '../utils/app_snackbar.dart';
import '../widgets/unlock_backup_dialog.dart';
import 'backup_create_flow.dart';

/// "Crear respaldo" (ver [CreateBackupFlow]) y "Restaurar un respaldo" de
/// la seccion "Tus datos" de Ajustes (HU-06). Nunca usa share_plus ni
/// file_picker directamente:
/// todo pasa por [BackupFileGateway]. Los mensajes a la usuaria se arman
/// con datos estructurados (BackupError, BackupWriteException.cause),
/// nunca con el texto de una excepcion.
class BackupSection extends StatefulWidget {
  const BackupSection({
    super.key,
    required this.service,
    this.gateway,
    this.reminderStore,
  });

  final BackupService service;

  /// Inyectable para tests; en la app real se usa [backupFileGateway]
  /// (asignado en main.dart), resuelto recien al usarlo.
  final BackupFileGateway? gateway;

  /// Inyectable para tests; en la app real, [backupReminderStore].
  final BackupReminderStore? reminderStore;

  @override
  State<BackupSection> createState() => _BackupSectionState();
}

class _BackupSectionState extends State<BackupSection> {
  /// true mientras se exporta, importa o deshace: impide empezar otra
  /// operacion (doble toque) hasta que termine la anterior. Compartido con
  /// Inicio si hay un [BackupBusyScope]; si no, uno propio. El propio no
  /// se libera: el flujo lo vuelve a false al terminar, aunque esta
  /// pantalla ya no este.
  late ValueNotifier<bool> _busy;
  ValueNotifier<bool>? _busyPropio;

  bool get _ocupada => _busy.value;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _busy = BackupBusyScope.maybeOf(context) ??
        (_busyPropio ??= ValueNotifier<bool>(false));
  }

  BackupFileGateway get _gateway => widget.gateway ?? backupFileGateway;

  BackupReminderStore get _store => widget.reminderStore ?? backupReminderStore;

  /// Fecha del ultimo respaldo y el interruptor, en vivo: crear un
  /// respaldo (aqui o desde Inicio) o borrar los datos los cambia.
  late final Stream<BackupReminderState> _recordatorio = _store.watch();

  // --- Crear respaldo ---

  Future<void> _crearRespaldo() => CreateBackupFlow(
        service: widget.service,
        busy: _busy,
        gateway: widget.gateway,
        reminderStore: widget.reminderStore,
      ).run(context);

  /// Interruptor "Recordarme crear un respaldo". La pantalla cambia
  /// cuando el almacen confirma (watch).
  Future<void> _cambiarRecordatorio(bool value) async {
    try {
      await _store.setEnabled(value);
    } catch (_) {
      _aviso('No se pudo guardar el cambio. Inténtalo de nuevo.');
    }
  }

  // --- Restaurar un respaldo ---

  Future<void> _restaurar() async {
    if (_ocupada) return;
    _busy.value = true;
    try {
      final String? path;
      try {
        path = await _gateway.pickBackupFile();
      } catch (_) {
        _aviso('No se pudo abrir el selector de archivos.');
        return;
      }
      if (path == null || !mounted) return;

      ImportPreview? preview;
      BackupNeedsPassword? protegido;
      try {
        final result = await _conProgreso('Revisando el archivo…', () async {
          final parsed = await widget.service.readBackupFile(path!);
          return switch (parsed) {
            BackupParseSuccess(:final data) => (
              null,
              await widget.service.previewImport(data),
              null,
            ),
            BackupParseFailure(:final error) => (error, null, null),
            // Respaldo cifrado (HU-06b CP4): se pide la contrasena despues.
            BackupNeedsPassword() => (null, null, parsed),
          };
        });
        if (result.$1 != null) {
          _aviso(_mensajeArchivoInvalido(result.$1!));
          return;
        }
        preview = result.$2;
        protegido = result.$3;
      } catch (_) {
        _aviso('No se pudo revisar el archivo. No se cambió nada.');
        return;
      }
      if (!mounted) return;

      if (protegido != null) {
        preview = await _abrirProtegido(protegido);
        if (preview == null || !mounted) return;
      }

      // Desde aqui, el mismo camino con o sin cifrado.
      final vista = preview!;
      final confirmado = await _confirmarReemplazo(vista);
      if (!confirmado || !mounted) return;

      // Un "Deshacer" pendiente de Inicio o del Calendario restauraria una
      // foto de antes de la importacion encima de los datos nuevos.
      ScaffoldMessenger.of(context).clearSnackBars();
      try {
        await _conProgreso(
          'Importando tu respaldo…',
          () => widget.service.importBackup(vista.data),
        );
      } on BackupWriteException catch (e) {
        _aviso(
          e.cause == BackupWriteCause.dateOutOfRange
              ? 'No se pudo importar: en tus datos actuales hay un día con una '
                    'fecha fuera de rango (${backupDayLabel(e.outOfRangeDate)}). '
                    'Tus datos no cambiaron.'
              : 'No se pudo importar. Tus datos no cambiaron.',
        );
        return;
      } catch (_) {
        _aviso('No se pudo importar. Tus datos no cambiaron.');
        return;
      }
      _mostrarExito(vista.incomingDayCount);
    } finally {
      _busy.value = false;
    }
  }

  /// Pide la contrasena y abre el respaldo cifrado (HU-06b CP4). Devuelve
  /// la vista previa para el mismo camino que un respaldo sin cifrar, o
  /// null si se cancela o el contenido no es importable (con su mensaje).
  /// Con la contrasena incorrecta vuelve a pedirla, con el error y lo
  /// escrito, sin volver a elegir el archivo. No escribe nada: ni la copia
  /// previa ni la base. [pending] y la contrasena viven solo en esta
  /// llamada.
  Future<ImportPreview?> _abrirProtegido(BackupNeedsPassword pending) async {
    String? escrita;
    String? error;
    while (mounted) {
      final password = await showUnlockBackupDialog(
        context,
        initialPassword: escrita,
        errorText: error,
      );
      if (password == null || !mounted) return null;

      final (BackupUnlockResult, ImportPreview?) resultado;
      try {
        Future<(BackupUnlockResult, ImportPreview?)> tarea() async {
          final r = await widget.service.unlockBackup(pending, password);
          return switch (r) {
            BackupUnlocked(:final data) => (
              r,
              await widget.service.previewImport(data),
            ),
            _ => (r, null),
          };
        }

        resultado = await _conProgreso(
          'Abriendo tu respaldo…',
          tarea,
          detalle: 'Esto puede tardar unos segundos.',
        );
      } catch (_) {
        _aviso('No se pudo revisar el archivo. No se cambió nada.');
        return null;
      }
      if (!mounted) return null;

      switch (resultado.$1) {
        case BackupUnlocked():
          return resultado.$2;
        case BackupUnlockWrongPasswordOrDamaged(:final message):
          escrita = password;
          error = message;
        case BackupUnlockInvalid(:final error):
          _aviso(_mensajeArchivoInvalido(error));
          return null;
      }
    }
    return null;
  }

  String _mensajeArchivoInvalido(BackupError error) {
    switch (error) {
      case BackupError.notABackup:
        return 'Este archivo no es un respaldo de Aura. No se cambió nada.';
      case BackupError.damaged:
        return 'El respaldo está dañado o incompleto. No se cambió nada.';
      case BackupError.newerVersion:
        return 'Este respaldo es de una versión más nueva de Aura. Actualiza '
            'la app y vuelve a intentarlo. No se cambió nada.';
      case BackupError.tooLarge:
        return 'El archivo es demasiado grande para ser un respaldo de Aura. '
            'No se cambió nada.';
      case BackupError.unreadable:
        return 'No se pudo leer el archivo. No se cambió nada.';
    }
  }

  Future<bool> _confirmarReemplazo(ImportPreview preview) async {
    final resultado = await showDialog<bool>(
      context: context,
      builder: (ctx) => _ConfirmarReemplazoDialog(preview: preview),
    );
    return resultado ?? false;
  }

  void _mostrarExito(int dias) {
    if (!mounted) return;
    final texto = dias == 1
        ? 'Listo: se importó 1 día.'
        : 'Listo: se importaron $dias días.';
    showAppSnackBar(
      context,
      '$texto\nSi te equivocaste, toca Deshacer.',
      // No se cierra sola: "Deshacer" debe seguir disponible hasta que
      // la usuaria lo use o cierre el mensaje con la "x".
      persistent: true,
      action: SnackBarAction(label: 'Deshacer', onPressed: _deshacer),
    );
  }

  Future<void> _deshacer() async {
    if (_ocupada || !mounted) return;
    _busy.value = true;
    try {
      await _conProgreso(
        'Restaurando tus datos anteriores…',
        widget.service.undoLastImport,
      );
      _aviso('Se restauraron tus datos anteriores.');
    } catch (_) {
      _aviso('No se pudo deshacer la importación. Tus datos no cambiaron.');
    } finally {
      _busy.value = false;
    }
  }

  // --- Utilidades ---

  Future<T> _conProgreso<T>(String texto, Future<T> Function() tarea,
          {String? detalle}) =>
      showBlockingProgress(context, texto, tarea, detalle: detalle);

  void _aviso(String texto) {
    if (!mounted) return;
    showBackupNotice(context, texto);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _busy,
      builder: (context, _, _) => _contenido(),
    );
  }

  Widget _contenido() {
    return StreamBuilder<BackupReminderState>(
      stream: _recordatorio,
      builder: (context, snapshot) {
        // Sin leer (o sin poder leer) el estado: solo la primera linea y
        // el interruptor en su valor por defecto, sin poder cambiarlo.
        final estado = snapshot.hasError ? null : snapshot.data;
        return Column(
          children: [
            _crearRespaldoTile(estado),
            SwitchListTile(
              title: const Text('Recordarme crear un respaldo'),
              subtitle: const Text(
                'Un aviso en Inicio si pasan $diasUmbralRecordatorioRespaldo '
                'días sin respaldo',
              ),
              value: estado?.activado ?? true,
              onChanged: estado == null ? null : _cambiarRecordatorio,
            ),
            _restaurarTile(),
          ],
        );
      },
    );
  }

  Widget _crearRespaldoTile(BackupReminderState? estado) {
    final ultimo = estado?.ultimoRespaldo;
    final segundaLinea = estado == null
        ? null
        : ultimo == null
            ? 'Todavía no has creado un respaldo en este teléfono'
            : 'Último respaldo: '
                '${dayMonthLabelWithYear(ultimo, today: _store.today())}';
    return ListTile(
      leading: const Icon(Icons.upload_file),
      title: const Text('Crear respaldo'),
      subtitle: segundaLinea == null
          ? const Text('Guarda tus registros en un archivo')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Guarda tus registros en un archivo'),
                Text(segundaLinea),
              ],
            ),
      enabled: !_ocupada,
      onTap: _crearRespaldo,
    );
  }

  Widget _restaurarTile() {
    return ListTile(
      leading: const Icon(Icons.restore),
      title: const Text('Restaurar un respaldo'),
      subtitle: const Text('Reemplaza tus datos por los de un archivo'),
      enabled: !_ocupada,
      onTap: _restaurar,
    );
  }
}

/// "¿Reemplazar tus datos?" con la fecha del respaldo, los conteos y, si
/// el respaldo trae menos dias, un aviso destacado. Responde una sola
/// vez: un segundo toque en "Reemplazar" durante la animacion de cierre
/// no hace pop de la pantalla de abajo.
class _ConfirmarReemplazoDialog extends StatefulWidget {
  const _ConfirmarReemplazoDialog({required this.preview});

  final ImportPreview preview;

  @override
  State<_ConfirmarReemplazoDialog> createState() =>
      _ConfirmarReemplazoDialogState();
}

class _ConfirmarReemplazoDialogState extends State<_ConfirmarReemplazoDialog> {
  bool _respondido = false;

  void _responder(bool valor) {
    if (_respondido) return;
    _respondido = true;
    Navigator.pop(context, valor);
  }

  @override
  Widget build(BuildContext context) {
    final preview = widget.preview;
    final fecha = _fechaRespaldo(preview.data.exportedAt);
    final perdidos = preview.daysLost;
    final enRespaldo = _diasConRegistro(
        preview.incomingDayCount, preview.incomingPeriodDayCount);
    final enTelefono = _diasConRegistro(
        preview.currentDayCount, preview.currentPeriodDayCount);
    return AlertDialog(
      title: const Text('¿Reemplazar tus datos?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'El respaldo es del $fecha y tiene $enRespaldo. En este '
              'teléfono tienes $enTelefono, que se reemplazarán por los '
              'del respaldo. Antes, Aura guardará una copia de tus datos '
              'actuales.',
            ),
            if (perdidos > 0) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        perdidos == 1
                            ? 'El respaldo tiene 1 día menos que los que '
                                  'tienes ahora; se perderá.'
                            : 'El respaldo tiene $perdidos días menos que los '
                                  'que tienes ahora; se perderán.',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => _responder(false),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: () => _responder(true),
          child: const Text('Reemplazar', style: TextStyle(color: Colors.red)),
        ),
      ],
    );
  }
}

/// "7 días con registro (5 de período)". [total] cuenta tambien los dias
/// de "no hubo sangrado", que el calendario no marca.
String _diasConRegistro(int total, int periodo) =>
    '${total == 1 ? '1 día' : '$total días'} con registro '
    '($periodo de período)';

/// Fecha de exportacion tal como la vio el telefono que la creo (la parte
/// yyyy-MM-dd de exportedAt, sin convertir de zona).
String _fechaRespaldo(String exportedAt) {
  final dia = exportedAt.length >= 10 ? exportedAt.substring(0, 10) : '';
  try {
    return backupDateFormat.format(DayKey.toUtcAnchor(dia));
  } on FormatException {
    return backupDateFormat.format(DateTime.parse(exportedAt));
  }
}
