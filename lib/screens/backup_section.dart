import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/backup/backup_file_gateway.dart';
import '../data/backup/backup_service.dart';
import '../domain/backup_codec.dart';
import '../utils/day_key.dart';
import '../utils/app_snackbar.dart';
import '../widgets/protect_backup_dialog.dart';

enum _AccionRespaldo { guardar, compartir }

/// "Crear respaldo" y "Restaurar un respaldo" de la seccion "Tus datos"
/// de Ajustes (HU-06). Nunca usa share_plus ni file_picker directamente:
/// todo pasa por [BackupFileGateway]. Los mensajes a la usuaria se arman
/// con datos estructurados (BackupError, BackupWriteException.cause),
/// nunca con el texto de una excepcion.
class BackupSection extends StatefulWidget {
  const BackupSection({super.key, required this.service, this.gateway});

  final BackupService service;

  /// Inyectable para tests; en la app real se usa [backupFileGateway]
  /// (asignado en main.dart), resuelto recien al usarlo.
  final BackupFileGateway? gateway;

  @override
  State<BackupSection> createState() => _BackupSectionState();
}

class _BackupSectionState extends State<BackupSection> {
  /// true mientras se exporta, importa o deshace: impide empezar otra
  /// operacion (doble toque) hasta que termine la anterior.
  bool _ocupada = false;

  BackupFileGateway get _gateway => widget.gateway ?? backupFileGateway;

  // --- Crear respaldo ---

  Future<void> _crearRespaldo() async {
    if (_ocupada) return;
    final accion = await showDialog<_AccionRespaldo>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tu respaldo tiene datos de salud'),
        content: const Text(
          'Incluye tus días de período, síntomas, ánimo y notas. Guárdalo en '
          'un lugar que solo tú uses. Si lo compartes con una app, esa app '
          'tendrá una copia.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _AccionRespaldo.guardar),
            child: const Text('Guardar en el teléfono'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _AccionRespaldo.compartir),
            child: const Text('Compartir'),
          ),
        ],
      ),
    );
    if (accion == null || !mounted || _ocupada) return;

    // HU-06b CP3: con contrasena (cifrado) o, tras confirmarlo, sin ella.
    final eleccion = await showProtectBackupDialog(context);
    if (eleccion == null || !mounted || _ocupada) return;

    setState(() => _ocupada = true);
    try {
      switch ((accion, eleccion)) {
        case (_AccionRespaldo.compartir, ProtectWithoutPassword()):
          final file = await widget.service.writeExportFile();
          await _compartir(file, protegido: false);
        case (_AccionRespaldo.compartir, ProtectWithPassword(:final password)):
          final file = await _protegiendo(password);
          await _compartir(file, protegido: true);
        case (_AccionRespaldo.guardar, ProtectWithoutPassword()):
          final json = await widget.service.buildExportJson();
          final guardado = await _gateway.saveToDevice(
            fileName: widget.service.exportFileName(),
            bytes: Uint8List.fromList(utf8.encode(json)),
          );
          await _despuesDeGuardar(guardado, protegido: false);
        case (_AccionRespaldo.guardar, ProtectWithPassword(:final password)):
          // Se guardan los bytes del archivo ya verificado (HU6b-10) y el
          // temporal se borra siempre, tambien si guardar falla.
          final file = await _protegiendo(password);
          try {
            final guardado = await _gateway.saveToDevice(
              fileName: widget.service.exportFileName(protected: true),
              bytes: await widget.service.readExportFile(file),
            );
            await _despuesDeGuardar(guardado, protegido: true);
          } finally {
            await widget.service.deleteExportFile(file);
          }
      }
    } on BackupEncryptionException catch (e) {
      _aviso(e.message);
    } on BackupWriteException catch (e) {
      _aviso(_mensajeNoSeCreo(e));
    } catch (_) {
      _aviso(
        accion == _AccionRespaldo.guardar
            ? 'No se pudo guardar el respaldo.'
            : 'No se pudo compartir el respaldo.',
      );
    } finally {
      if (mounted) setState(() => _ocupada = false);
    }
  }

  /// Cifra y verifica el respaldo con la pantalla bloqueada (puede tardar
  /// unos segundos: la derivacion corre en otro isolate).
  Future<File> _protegiendo(String password) => _conProgreso(
        'Protegiendo tu respaldo…',
        () => widget.service.writeExportFile(password: password),
        detalle: 'Esto puede tardar unos segundos.',
      );

  // Con contrasena, el aviso final recuerda que no hay recuperacion
  // (HU-06b). Sin contrasena, los mensajes de siempre.
  static const _recuerda =
      'Recuerda tu contraseña: Aura no puede recuperarla.';

  Future<void> _compartir(File file, {required bool protegido}) async {
    final compartido = await _gateway.shareFile(file);
    // Cerrar la hoja sin elegir destino no es un error: sin mensaje.
    if (compartido) {
      _aviso(protegido
          ? 'Respaldo protegido listo. $_recuerda'
          : 'Respaldo listo. Guárdalo en un lugar seguro.');
    }
  }

  Future<void> _despuesDeGuardar(bool guardado,
      {required bool protegido}) async {
    // Cancelar el "Guardar como" no es un error: sin mensaje.
    if (!guardado) return;
    _aviso(protegido
        ? 'Respaldo protegido guardado. $_recuerda'
        : 'Respaldo guardado.');
    // Ya hay una copia completa fuera de la app: la copia previa a la
    // migracion v4 deja de hacer falta. Si no se puede borrar, se
    // reintenta a los 30 dias o al borrar los datos.
    try {
      await widget.service.deletePreMigrationCopy();
    } catch (_) {}
  }

  String _mensajeNoSeCreo(BackupWriteException e) {
    switch (e.cause) {
      case BackupWriteCause.dateOutOfRange:
        return 'No se pudo crear el respaldo: hay un día con una fecha fuera '
            'de rango (${_fechaLegible(e.outOfRangeDate)}).';
      case BackupWriteCause.invalidData:
        return 'No se pudo crear el respaldo: hay datos guardados que no son '
            'válidos.';
      case BackupWriteCause.fileSystem:
        return 'No se pudo crear el respaldo.';
    }
  }

  // --- Restaurar un respaldo ---

  Future<void> _restaurar() async {
    if (_ocupada) return;
    setState(() => _ocupada = true);
    try {
      final String? path;
      try {
        path = await _gateway.pickBackupFile();
      } catch (_) {
        _aviso('No se pudo abrir el selector de archivos.');
        return;
      }
      if (path == null || !mounted) return;

      final ImportPreview preview;
      try {
        final result = await _conProgreso('Revisando el archivo…', () async {
          final parsed = await widget.service.readBackupFile(path!);
          return switch (parsed) {
            BackupParseSuccess(:final data) => (
              null,
              await widget.service.previewImport(data),
            ),
            BackupParseFailure(:final error) => (error, null),
            // TEMPORAL CP4: hasta que la pantalla pida la contrasena, un
            // respaldo cifrado muestra el mismo mensaje que antes ("version
            // mas nueva") y no se importa nada.
            BackupNeedsPassword() => (BackupError.newerVersion, null),
          };
        });
        if (result.$1 != null) {
          _aviso(_mensajeArchivoInvalido(result.$1!));
          return;
        }
        preview = result.$2!;
      } catch (_) {
        _aviso('No se pudo revisar el archivo. No se cambió nada.');
        return;
      }
      if (!mounted) return;

      final confirmado = await _confirmarReemplazo(preview);
      if (!confirmado || !mounted) return;

      // Un "Deshacer" pendiente de Inicio o del Calendario restauraria una
      // foto de antes de la importacion encima de los datos nuevos.
      ScaffoldMessenger.of(context).clearSnackBars();
      try {
        await _conProgreso(
          'Importando tu respaldo…',
          () => widget.service.importBackup(preview.data),
        );
      } on BackupWriteException catch (e) {
        _aviso(
          e.cause == BackupWriteCause.dateOutOfRange
              ? 'No se pudo importar: en tus datos actuales hay un día con una '
                    'fecha fuera de rango (${_fechaLegible(e.outOfRangeDate)}). '
                    'Tus datos no cambiaron.'
              : 'No se pudo importar. Tus datos no cambiaron.',
        );
        return;
      } catch (_) {
        _aviso('No se pudo importar. Tus datos no cambiaron.');
        return;
      }
      _mostrarExito(preview.incomingDayCount);
    } finally {
      if (mounted) setState(() => _ocupada = false);
    }
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
    setState(() => _ocupada = true);
    try {
      await _conProgreso(
        'Restaurando tus datos anteriores…',
        widget.service.undoLastImport,
      );
      _aviso('Se restauraron tus datos anteriores.');
    } catch (_) {
      _aviso('No se pudo deshacer la importación. Tus datos no cambiaron.');
    } finally {
      if (mounted) setState(() => _ocupada = false);
    }
  }

  // --- Utilidades ---

  /// Bloquea la pantalla con un dialogo de progreso que no se puede
  /// cerrar (ni con "atras") mientras corre [tarea], para que no entren
  /// otras escrituras a mitad de camino.
  Future<T> _conProgreso<T>(String texto, Future<T> Function() tarea,
      {String? detalle}) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 20),
              Expanded(
                child: detalle == null
                    ? Text(texto)
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [Text(texto), Text(detalle)],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
    try {
      return await tarea();
    } finally {
      navigator.pop();
    }
  }

  void _aviso(String texto) {
    if (!mounted) return;
    showAppSnackBar(context, texto);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.upload_file),
          title: const Text('Crear respaldo'),
          subtitle: const Text('Guarda tus registros en un archivo'),
          enabled: !_ocupada,
          onTap: _crearRespaldo,
        ),
        ListTile(
          leading: const Icon(Icons.restore),
          title: const Text('Restaurar un respaldo'),
          subtitle: const Text('Reemplaza tus datos por los de un archivo'),
          enabled: !_ocupada,
          onTap: _restaurar,
        ),
      ],
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

final DateFormat _formatoFecha = DateFormat("d 'de' MMMM 'de' y", 'es');

/// Fecha de exportacion tal como la vio el telefono que la creo (la parte
/// yyyy-MM-dd de exportedAt, sin convertir de zona).
String _fechaRespaldo(String exportedAt) {
  final dia = exportedAt.length >= 10 ? exportedAt.substring(0, 10) : '';
  try {
    return _formatoFecha.format(DayKey.toUtcAnchor(dia));
  } on FormatException {
    return _formatoFecha.format(DateTime.parse(exportedAt));
  }
}

String _fechaLegible(String? dayKey) {
  if (dayKey == null) return 'fecha desconocida';
  return _formatoFecha.format(DayKey.toUtcAnchor(dayKey));
}
