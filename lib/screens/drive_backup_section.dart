import 'dart:async';

import 'package:flutter/material.dart';

import '../data/backup/auto_drive_backup_service.dart';
import '../data/backup/drive_api_client.dart';
import '../data/backup/drive_backup_settings_store.dart';
import '../utils/app_snackbar.dart';
import '../utils/aura_localizations.dart';
import '../utils/date_labels.dart';
import '../utils/day_key.dart';
import '../utils/drive_client_config.dart';
import '../widgets/protect_backup_dialog.dart';

/// Seccion "Respaldar automaticamente en Google Drive" (HU-09) de
/// Ajustes > Tus datos.
///
/// Apagada: explica que sube un respaldo cifrado una vez al dia y pide la
/// contrasena una sola vez (la clave queda sellada en el Keystore; ver
/// AutoDriveBackupService). Encendida: muestra cuenta, ultimo respaldo y
/// fallo, con "Respaldar ahora" para forzarlo y el interruptor para
/// quitarlo. Nunca muestra el texto de una excepcion: los mensajes salen
/// de AutoBackupStatus y DriveApiFailure.
class DriveBackupSection extends StatefulWidget {
  const DriveBackupSection({
    super.key,
    required this.service,
    this.settingsStore,
    this.clientId,
  });

  final AutoDriveBackupService service;

  /// Para tests. Por defecto el que trae la compilacion (dart-define).
  final String? clientId;

  final DriveBackupSettingsStore? settingsStore;

  @override
  State<DriveBackupSection> createState() => _DriveBackupSectionState();
}

class _DriveBackupSectionState extends State<DriveBackupSection> {
  late final DriveBackupSettingsStore _store =
      widget.settingsStore ?? driveBackupSettingsStore;
  late final String _clientId = widget.clientId ?? driveClientId();

  StreamSubscription<DriveBackupSettings>? _sub;
  DriveBackupSettings? _ajustes;
  bool _ocupado = false;

  @override
  void initState() {
    super.initState();
    _sub = _store.watch().listen(
      (ajustes) {
        if (!mounted) return;
        setState(() => _ajustes = ajustes);
      },
      onError: (Object _) {
        // Sin leer el archivo: valores por defecto (apagado), como en
        // Ajustes con los ajustes del telefono.
        if (!mounted) return;
        setState(() => _ajustes ??= const DriveBackupSettings());
      },
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ajustes = _ajustes;
    if (ajustes == null) return const SizedBox.shrink();

    final sinConfigurar = _clientId.isEmpty;
    final errorColor = Theme.of(context).colorScheme.error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          key: const Key('respaldo_drive_switch'),
          title: Text(tr('Respaldar automáticamente en Google Drive',
              'Back up automatically to Google Drive')),
          subtitle: Text(sinConfigurar
              ? tr(
                  'Configuración pendiente: esta compilación no tiene el '
                      'client ID de Google (ver docs/DRIVE_SETUP.md).',
                  'Setup pending: this build has no Google client ID '
                      '(see docs/DRIVE_SETUP.md).')
              : ajustes.habilitado
                  ? tr('Cuenta: ${ajustes.cuenta}\n${_ultimoTexto(ajustes)}',
                      'Account: ${ajustes.cuenta}\n${_ultimoTexto(ajustes)}')
                  : tr(
                      'Una vez al día sube a tu Google Drive un respaldo '
                          'cifrado con una contraseña que eliges una sola vez. '
                          'Los archivos solo los puedes abrir con esa contraseña.',
                      'Once a day, Aura uploads an encrypted backup to your '
                          'Google Drive, protected by a password you choose '
                          'once. Only that password can open the files.')),
          value: ajustes.habilitado,
          onChanged: (_ocupado || sinConfigurar) ? null : _cambiar,
        ),
        if (ajustes.habilitado && ajustes.ultimoFallo != null)
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 4),
            child: Text(
              tr('Último intento falló: ${_falloTexto(ajustes.ultimoFallo!)}.',
                  'Last attempt failed: ${_falloTexto(ajustes.ultimoFallo!)}.'),
              key: const Key('respaldo_drive_fallo'),
              style: TextStyle(color: errorColor),
            ),
          ),
        if (ajustes.habilitado)
          ListTile(
            key: const Key('respaldar_ahora'),
            leading: const Icon(Icons.cloud_upload_outlined),
            title: Text(tr('Respaldar ahora', 'Back up now')),
            enabled: !_ocupado,
            onTap: _respaldarAhora,
          ),
        if (_ocupado)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: LinearProgressIndicator(),
          ),
      ],
    );
  }

  /// "hoy" si fue hoy; si no, "el 4 de octubre" (con ano si toca).
  String _ultimoTexto(DriveBackupSettings ajustes) {
    final ultimo = ajustes.ultimoRespaldo;
    if (ultimo == null) {
      return tr('Aún no se ha hecho un respaldo.', 'No backup yet.');
    }
    final hoy = DayKey.fromDate(DateTime.now());
    if (ultimo == hoy) return tr('Último respaldo: hoy.', 'Last backup: today.');
    final fecha = dayMonthLabelWithYear(ultimo, today: hoy);
    return tr('Último respaldo: el $fecha.', 'Last backup: $fecha.');
  }

  String _falloTexto(DriveApiFailure fallo) => switch (fallo) {
        DriveApiFailure.offline => tr(
            'sin conexión; el próximo intento automático lo reintentará',
            'no connection; the next automatic attempt will retry'),
        DriveApiFailure.unauthorized => tr(
            'la sesión de Google caducó; vuelve a entrar en la cuenta',
            'your Google session expired; sign in to your account again'),
        DriveApiFailure.failed => tr(
            'Google rechazó el intento; prueba más tarde',
            'Google rejected the attempt; try again later'),
      };

  String _mensaje(AutoBackupStatus status) => switch (status) {
        AutoBackupStatus.ok =>
          tr('Respaldo subido a Google Drive.', 'Backup uploaded to Google Drive.'),
        AutoBackupStatus.sinCambios =>
          tr('Ya hay un respaldo de hoy.', "There's already a backup from today."),
        AutoBackupStatus.deshabilitado => tr(
            'El respaldo automático está apagado.',
            'Automatic backup is off.'),
        AutoBackupStatus.claveNoDisponible => tr(
            'Este teléfono ya no tiene la clave de cifrado; vuelve a '
                'activar el respaldo con tu contraseña.',
            'This phone no longer has the encryption key; turn backup '
                'on again with your password.'),
        AutoBackupStatus.offline => tr(
            'Sin conexión: el próximo respaldo automático lo reintentará.',
            'No connection: the next automatic backup will retry.'),
        AutoBackupStatus.unauthorized => tr(
            'La sesión de Google caducó; vuelve a entrar en la cuenta.',
            'Your Google session expired; sign in to your account again.'),
        AutoBackupStatus.failed => tr(
            'Google rechazó el respaldo; inténtalo más tarde.',
            'Google rejected the backup; try again later.'),
      };

  Future<void> _cambiar(bool value) async {
    if (value) {
      await _activar();
    } else {
      await _desactivar();
    }
  }

  Future<void> _activar() async {
    final choice = await showDriveBackupPasswordDialog(context);
    if (choice is! ProtectWithPassword || !mounted) return;

    setState(() => _ocupado = true);
    final result = await widget.service.enable(password: choice.password);
    if (!mounted) return;
    setState(() => _ocupado = false);

    switch (result) {
      case EnableDriveCancelled():
        // Sin cuenta elegida no hay respaldo; no es un error.
        break;
      case EnableDriveFailed():
        showAppSnackBar(
            context, tr('No se pudo conectar con Google; no se activó el '
            'respaldo.', "Couldn't connect to Google; backup wasn't turned on."));
      case EnableClaveNoDisponible():
        showAppSnackBar(context, tr(
            'El Keystore de Android no pudo guardar la clave; '
            'inténtalo de nuevo.',
            "The Android Keystore couldn't save the key; please try again."));
      case DriveEnabled(:final primerRespaldo):
        showAppSnackBar(context, switch (primerRespaldo) {
          null => tr('Respaldo automático activado.', 'Automatic backup turned on.'),
          AutoBackupStatus.ok => tr(
              'Respaldo automático activado: primer respaldo subido a '
                  'Google Drive.',
              'Automatic backup turned on: first backup uploaded to '
                  'Google Drive.'),
          _ => tr('Respaldo automático activado. ${_mensaje(primerRespaldo)}',
              'Automatic backup turned on. ${_mensaje(primerRespaldo)}'),
        });
    }
  }

  Future<void> _respaldarAhora() async {
    setState(() => _ocupado = true);
    final status = await widget.service.maybeBackup(force: true);
    if (!mounted) return;
    setState(() => _ocupado = false);
    showAppSnackBar(context, _mensaje(status));
  }

  Future<void> _desactivar() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('¿Quitar el respaldo automático?',
            'Turn off automatic backup?')),
        content: Text(tr(
          'Aura dejará de subir respaldos a Google Drive y cerrará la '
          'sesión de Google en este teléfono. Los archivos que ya subiste '
          'quedan en tu Google Drive y puedes borrarlos desde ahí.',
          'Aura will stop uploading backups to Google Drive and sign out of '
          'Google on this phone. Files you already uploaded stay in your '
          'Google Drive, and you can delete them there.',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Cancelar', 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Quitar respaldo', 'Turn off backup')),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    setState(() => _ocupado = true);
    await widget.service.disable();
    if (!mounted) return;
    setState(() => _ocupado = false);
    showAppSnackBar(context,
        tr('Respaldo automático desactivado.', 'Automatic backup turned off.'));
  }
}
