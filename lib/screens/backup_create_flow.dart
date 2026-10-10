import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/backup/backup_file_gateway.dart';
import '../data/backup/backup_reminder_store.dart';
import '../data/backup/backup_service.dart';
import '../utils/app_snackbar.dart';
import '../utils/day_key.dart';
import '../widgets/protect_backup_dialog.dart';

/// true mientras se crea, importa o deshace un respaldo: impide empezar
/// otra operacion (doble toque) hasta que termine la anterior, tambien
/// desde otra pantalla. MainNavigationScreen comparte uno entre Ajustes e
/// Inicio con [BackupBusyScope]; sin el, cada pantalla usa el suyo.
class BackupBusyScope extends InheritedWidget {
  const BackupBusyScope({super.key, required this.busy, required super.child});

  final ValueNotifier<bool> busy;

  static ValueNotifier<bool>? maybeOf(BuildContext context) => context
      .getInheritedWidgetOfExactType<BackupBusyScope>()
      ?.busy;

  @override
  bool updateShouldNotify(BackupBusyScope oldWidget) =>
      busy != oldWidget.busy;
}

enum _AccionRespaldo { guardar, compartir }

/// "Crear respaldo" (HU-06): aviso de datos de salud -> proteger con
/// contrasena o no -> guardar en el telefono o compartir -> anotar la
/// fecha para el recordatorio. Lo usan Ajustes y la tarjeta de Inicio.
/// Nunca usa share_plus ni file_picker directamente: todo pasa por
/// [BackupFileGateway]. Los mensajes se arman con datos estructurados,
/// nunca con el texto de una excepcion.
class CreateBackupFlow {
  CreateBackupFlow({
    required this.service,
    required this.busy,
    BackupFileGateway? gateway,
    BackupReminderStore? reminderStore,
  })  : _gateway = gateway,
        _reminderStore = reminderStore;

  final BackupService service;
  final ValueNotifier<bool> busy;
  final BackupFileGateway? _gateway;
  final BackupReminderStore? _reminderStore;

  // Resueltos recien al usarlos (en la app real se asignan en main.dart).
  BackupFileGateway get _archivos => _gateway ?? backupFileGateway;
  BackupReminderStore get _store => _reminderStore ?? backupReminderStore;

  /// Corre el flujo con los dialogos y avisos sobre [context]. Si
  /// [context] se desmonta a mitad de camino, no muestra nada mas.
  Future<void> run(BuildContext context) async {
    if (busy.value) return;
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
    if (accion == null || !context.mounted || busy.value) return;

    // HU-06b CP3: con contrasena (cifrado) o, tras confirmarlo, sin ella.
    final eleccion = await showProtectBackupDialog(context);
    if (eleccion == null || !context.mounted || busy.value) return;

    // Avisos sin usar [context] despues de cada espera: nada si ya no esta.
    void avisar(String texto) {
      if (context.mounted) showAppSnackBar(context, texto);
    }

    busy.value = true;
    try {
      switch ((accion, eleccion)) {
        case (_AccionRespaldo.compartir, ProtectWithoutPassword()):
          final file = await service.writeExportFile();
          await _compartir(file, avisar, protegido: false);
        case (_AccionRespaldo.compartir, ProtectWithPassword(:final password)):
          final file = await _protegiendo(context, password);
          await _compartir(file, avisar, protegido: true);
        case (_AccionRespaldo.guardar, ProtectWithoutPassword()):
          final json = await service.buildExportJson();
          final guardado = await _archivos.saveToDevice(
            fileName: service.exportFileName(),
            bytes: Uint8List.fromList(utf8.encode(json)),
          );
          await _despuesDeGuardar(guardado, avisar, protegido: false);
        case (_AccionRespaldo.guardar, ProtectWithPassword(:final password)):
          // Se guardan los bytes del archivo ya verificado (HU6b-10) y el
          // temporal se borra siempre, tambien si guardar falla.
          final file = await _protegiendo(context, password);
          try {
            final guardado = await _archivos.saveToDevice(
              fileName: service.exportFileName(protected: true),
              bytes: await service.readExportFile(file),
            );
            await _despuesDeGuardar(guardado, avisar, protegido: true);
          } finally {
            await service.deleteExportFile(file);
          }
      }
    } on BackupEncryptionException catch (e) {
      avisar(e.message);
    } on BackupWriteException catch (e) {
      avisar(backupNotCreatedMessage(e));
    } catch (_) {
      avisar(
        accion == _AccionRespaldo.guardar
            ? 'No se pudo guardar el respaldo.'
            : 'No se pudo compartir el respaldo.',
      );
    } finally {
      busy.value = false;
    }
  }

  /// Cifra y verifica el respaldo con la pantalla bloqueada (puede tardar
  /// unos segundos: la derivacion corre en otro isolate).
  Future<File> _protegiendo(BuildContext context, String password) =>
      showBlockingProgress(
        context,
        'Protegiendo tu respaldo…',
        () => service.writeExportFile(password: password),
        detalle: 'Esto puede tardar unos segundos.',
      );

  // Con contrasena, el aviso final recuerda que no hay recuperacion
  // (HU-06b). Sin contrasena, los mensajes de siempre.
  static const _recuerda =
      'Recuerda tu contraseña: Aura no puede recuperarla.';

  Future<void> _compartir(File file, void Function(String) avisar,
      {required bool protegido}) async {
    final resultado = await _archivos.shareFile(file);
    // Cerrar la hoja sin elegir destino no es un error: sin mensaje.
    if (resultado == BackupShareResult.dismissed) return;
    // Solo "success" cuenta para el recordatorio: "unavailable" no dice si
    // se envio algo. El mensaje se muestra igual, para no esconder un
    // exito real.
    if (resultado == BackupShareResult.success) await _anotarRespaldo();
    avisar(protegido
        ? 'Respaldo protegido listo. $_recuerda'
        : 'Respaldo listo. Guárdalo en un lugar seguro.');
  }

  Future<void> _despuesDeGuardar(bool guardado, void Function(String) avisar,
      {required bool protegido}) async {
    // Cancelar el "Guardar como" no es un error: sin mensaje.
    if (!guardado) return;
    await _anotarRespaldo();
    avisar(protegido
        ? 'Respaldo protegido guardado. $_recuerda'
        : 'Respaldo guardado.');
    // Ya hay una copia completa fuera de la app: la copia previa a la
    // migracion v4 deja de hacer falta. Si no se puede borrar, se
    // reintenta a los 30 dias o al borrar los datos.
    try {
      await service.deletePreMigrationCopy();
    } catch (_) {}
  }

  /// Anota hoy como ultimo respaldo para el recordatorio. Si no se puede
  /// anotar, el respaldo igual quedo hecho: no se avisa nada y, en el peor
  /// caso, el recordatorio aparece antes de tiempo.
  Future<void> _anotarRespaldo() async {
    try {
      await _store.recordBackup();
    } catch (_) {}
  }
}

/// Aviso de las operaciones de respaldo; nada si [context] ya no esta.
void showBackupNotice(BuildContext context, String texto) {
  if (!context.mounted) return;
  showAppSnackBar(context, texto);
}

/// Bloquea la pantalla con un dialogo de progreso que no se puede cerrar
/// (ni con "atras") mientras corre [tarea], para que no entren otras
/// escrituras a mitad de camino.
Future<T> showBlockingProgress<T>(
    BuildContext context, String texto, Future<T> Function() tarea,
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
                      children: [
                        Text(
                          texto,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        Text(detalle),
                      ],
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

/// Mensaje cuando no se pudo crear el respaldo (o la copia previa).
String backupNotCreatedMessage(BackupWriteException e) {
  switch (e.cause) {
    case BackupWriteCause.dateOutOfRange:
      return 'No se pudo crear el respaldo: hay un día con una fecha fuera '
          'de rango (${backupDayLabel(e.outOfRangeDate)}).';
    case BackupWriteCause.invalidData:
      return 'No se pudo crear el respaldo: hay datos guardados que no son '
          'válidos.';
    case BackupWriteCause.fileSystem:
      return 'No se pudo crear el respaldo.';
  }
}

/// Formato de fechas de los mensajes del respaldo: "4 de octubre de 2026".
final DateFormat backupDateFormat = DateFormat("d 'de' MMMM 'de' y", 'es');

String backupDayLabel(String? dayKey) {
  if (dayKey == null) return 'fecha desconocida';
  return backupDateFormat.format(DayKey.toUtcAnchor(dayKey));
}
