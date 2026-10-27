import 'package:flutter/material.dart';

import '../data/backup/backup_file_gateway.dart';
import '../data/backup/backup_reminder_store.dart';
import '../data/backup/backup_service.dart';
import '../domain/backup_codec.dart';
import '../domain/backup_reminder.dart';
import '../utils/aura_localizations.dart';
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

  /// Cuando se importo por ultima vez, mientras exista la copia previa:
  /// "Deshacer la ultima importacion" sigue disponible aunque el aviso de
  /// la importacion ya no este (otro aviso lo reemplaza). Null si no hay.
  DateTime? _copiaPrevia;

  @override
  void initState() {
    super.initState();
    _leerCopiaPrevia();
  }

  Future<void> _leerCopiaPrevia() async {
    DateTime? fecha;
    try {
      fecha = await widget.service.preImportCopyDate();
    } catch (_) {
      fecha = null;
    }
    if (!mounted) return;
    setState(() => _copiaPrevia = fecha);
  }

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
      _aviso(tr('No se pudo guardar el cambio. Inténtalo de nuevo.',
          "Couldn't save the change. Please try again."));
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
        _aviso(tr('No se pudo abrir el selector de archivos.',
            "Couldn't open the file picker."));
        return;
      }
      if (path == null || !mounted) return;

      ImportPreview? preview;
      BackupNeedsPassword? protegido;
      try {
        final result = await _conProgreso(
            tr('Revisando el archivo…', 'Checking the file…'), () async {
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
        _aviso(tr('No se pudo revisar el archivo. No se cambió nada.',
            "Couldn't check the file. Nothing was changed."));
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
          tr('Importando tu respaldo…', 'Importing your backup…'),
          () => widget.service.importBackup(vista.data),
        );
      } on BackupWriteException catch (e) {
        _aviso(
          e.cause == BackupWriteCause.dateOutOfRange
              ? tr('No se pudo importar: en tus datos actuales hay un día con una '
                    'fecha fuera de rango (${backupDayLabel(e.outOfRangeDate)}). '
                    'Tus datos no cambiaron.',
                  "Couldn't import: your current data has a day with an "
                    'out-of-range date (${backupDayLabel(e.outOfRangeDate)}). '
                    "Your data wasn't changed.")
              : tr('No se pudo importar. Tus datos no cambiaron.',
                  "Couldn't import. Your data wasn't changed."),
        );
        return;
      } catch (_) {
        _aviso(tr('No se pudo importar. Tus datos no cambiaron.',
            "Couldn't import. Your data wasn't changed."));
        return;
      }
      _mostrarExito(vista.incomingDayCount);
      await _leerCopiaPrevia();
    } finally {
      _busy.value = false;
    }
  }

  /// "Deshacer la ultima importacion" desde Ajustes: puede ser dias
  /// despues, asi que antes se confirma (lo registrado desde entonces se
  /// pierde).
  Future<void> _deshacerDesdeAjustes() async {
    final fecha = _copiaPrevia;
    if (fecha == null || _ocupada) return;
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('¿Deshacer la última importación?',
            'Undo the last import?')),
        content: Text(
          tr('Tus datos vuelven a como estaban antes de importar, el '
          '${dayMonthLabelWithYear(DayKey.fromDate(fecha), today: _store.today())}. '
          'Lo que registraste después de esa fecha se perderá.',
          'Your data goes back to how it was before the import, on '
          '${dayMonthLabelWithYear(DayKey.fromDate(fecha), today: _store.today())}. '
          'Anything you logged after that date will be lost.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Cancelar', 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Deshacer', 'Undo')),
          ),
        ],
      ),
    );
    if (confirmado != true || !mounted) return;
    await _deshacer();
  }

  /// Pide la contrasena y abre el respaldo cifrado (HU-06b CP4). Devuelve
  /// la vista previa para el mismo camino que un respaldo sin cifrar, o
  /// null si se cancela o el contenido no es importable (con su mensaje).
  /// Con la contrasena incorrecta, o si falto memoria para abrirlo, vuelve
  /// a pedirla, con el error y lo escrito, sin volver a elegir el archivo. No escribe nada: ni la copia
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
          tr('Abriendo tu respaldo…', 'Opening your backup…'),
          tarea,
          detalle: tr('Esto puede tardar unos segundos.',
              'This may take a few seconds.'),
        );
      } catch (_) {
        _aviso(tr('No se pudo revisar el archivo. No se cambió nada.',
            "Couldn't check the file. Nothing was changed."));
        return null;
      }
      if (!mounted) return null;

      switch (resultado.$1) {
        case BackupUnlocked():
          return resultado.$2;
        case BackupUnlockWrongPasswordOrDamaged(:final message):
          escrita = password;
          error = message;
        case BackupUnlockInvalid(error: BackupError.insufficientMemory):
          // El archivo puede estar bien: se reintenta igual que con la
          // contrasena incorrecta.
          escrita = password;
          error = _mensajeArchivoInvalido(BackupError.insufficientMemory);
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
        return tr('Este archivo no es un respaldo de Aura. No se cambió nada.',
            "This file isn't an Aura backup. Nothing was changed.");
      case BackupError.damaged:
        return tr('El respaldo está dañado o incompleto. No se cambió nada.',
            'The backup is damaged or incomplete. Nothing was changed.');
      case BackupError.newerVersion:
        return tr('Este respaldo es de una versión más nueva de Aura. Actualiza '
            'la app y vuelve a intentarlo. No se cambió nada.',
            'This backup is from a newer version of Aura. Update the app '
            'and try again. Nothing was changed.');
      case BackupError.tooLarge:
        return tr('El archivo es demasiado grande para ser un respaldo de Aura. '
            'No se cambió nada.',
            'The file is too large to be an Aura backup. Nothing was '
            'changed.');
      case BackupError.unreadable:
        return tr('No se pudo leer el archivo. No se cambió nada.',
            "Couldn't read the file. Nothing was changed.");
      case BackupError.insufficientMemory:
        return tr('Este teléfono no tiene memoria suficiente para abrir este '
            'respaldo ahora. Cierra otras apps y vuelve a intentarlo. No se '
            'cambió nada.',
            "This phone doesn't have enough memory to open this backup "
            'right now. Close other apps and try again. Nothing was '
            'changed.');
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
        ? tr('Listo: se importó 1 día.', 'Done: 1 day imported.')
        : tr('Listo: se importaron $dias días.',
            'Done: $dias days imported.');
    showAppSnackBar(
      context,
      tr('$texto\nSi te equivocaste, toca Deshacer.',
          '$texto\nIf you made a mistake, tap Undo.'),
      // No se cierra sola: "Deshacer" debe seguir disponible hasta que
      // la usuaria lo use o cierre el mensaje con la "x".
      persistent: true,
      action:
          SnackBarAction(label: tr('Deshacer', 'Undo'), onPressed: _deshacer),
    );
  }

  Future<void> _deshacer() async {
    if (_ocupada || !mounted) return;
    _busy.value = true;
    try {
      await _conProgreso(
        tr('Restaurando tus datos anteriores…',
            'Restoring your previous data…'),
        widget.service.undoLastImport,
      );
      _aviso(tr('Se restauraron tus datos anteriores.',
          'Your previous data was restored.'));
    } catch (_) {
      _aviso(tr('No se pudo deshacer la importación. Tus datos no cambiaron.',
          "Couldn't undo the import. Your data wasn't changed."));
    } finally {
      _busy.value = false;
    }
    await _leerCopiaPrevia();
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
              title: Text(tr('Recordarme crear un respaldo',
                  'Remind me to create a backup')),
              subtitle: Text(
                tr('Un aviso en Inicio si pasan $diasUmbralRecordatorioRespaldo '
                'días sin respaldo',
                'A reminder on Home after $diasUmbralRecordatorioRespaldo '
                'days without a backup'),
              ),
              value: estado?.activado ?? true,
              onChanged: estado == null ? null : _cambiarRecordatorio,
            ),
            _restaurarTile(),
            if (_copiaPrevia != null)
              ListTile(
                leading: const Icon(Icons.undo),
                title: Text(tr('Deshacer la última importación',
                    'Undo the last import')),
                subtitle: Text(tr('Vuelve a tus datos de antes de importar',
                    'Go back to your data from before the import')),
                enabled: !_ocupada,
                onTap: _deshacerDesdeAjustes,
              ),
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
            ? tr('Todavía no has creado un respaldo en este teléfono',
                "You haven't created a backup on this phone yet")
            : tr('Último respaldo: '
                '${dayMonthLabelWithYear(ultimo, today: _store.today())}',
                'Last backup: '
                '${dayMonthLabelWithYear(ultimo, today: _store.today())}');
    return ListTile(
      leading: const Icon(Icons.upload_file),
      title: Text(tr('Crear respaldo', 'Create backup')),
      subtitle: segundaLinea == null
          ? Text(tr('Guarda tus registros en un archivo',
              'Save your logs to a file'))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('Guarda tus registros en un archivo',
                    'Save your logs to a file')),
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
      title: Text(tr('Restaurar un respaldo', 'Restore a backup')),
      subtitle: Text(tr('Reemplaza tus datos por los de un archivo',
          'Replace your data with the data in a file')),
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
      title: Text(tr('¿Reemplazar tus datos?', 'Replace your data?')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr('El respaldo es del $fecha y tiene $enRespaldo. En este '
              'teléfono tienes $enTelefono, que se reemplazarán por los '
              'del respaldo. Antes, Aura guardará una copia de tus datos '
              'actuales.',
              'The backup is from $fecha and has $enRespaldo. On this '
              'phone you have $enTelefono, which will be replaced by the '
              "backup's. First, Aura will save a copy of your current "
              'data.'),
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
                            ? tr('El respaldo tiene 1 día menos que los que '
                                  'tienes ahora; se perderá.',
                                'The backup has 1 day fewer than you have '
                                  'now; it will be lost.')
                            : tr('El respaldo tiene $perdidos días menos que los '
                                  'que tienes ahora; se perderán.',
                                'The backup has $perdidos days fewer than you '
                                  'have now; they will be lost.'),
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
          child: Text(tr('Cancelar', 'Cancel')),
        ),
        TextButton(
          onPressed: () => _responder(true),
          child: Text(tr('Reemplazar', 'Replace'),
              style: const TextStyle(color: Colors.red)),
        ),
      ],
    );
  }
}

/// "7 días con registro (5 de período)". [total] cuenta tambien los dias
/// de "no hubo sangrado", que el calendario no marca.
String _diasConRegistro(int total, int periodo) => tr(
    '${total == 1 ? '1 día' : '$total días'} con registro '
    '($periodo de período)',
    '${total == 1 ? '1 logged day' : '$total logged days'} '
    '($periodo period ${periodo == 1 ? 'day' : 'days'})');

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
