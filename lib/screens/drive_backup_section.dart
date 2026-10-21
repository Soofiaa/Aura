import 'dart:async';

import 'package:flutter/material.dart';

import '../data/backup/auto_drive_backup_service.dart';
import '../data/backup/drive_api_client.dart';
import '../data/backup/drive_backup_settings_store.dart';
import '../utils/app_snackbar.dart';
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
          title: const Text('Respaldar automáticamente en Google Drive'),
          subtitle: Text(sinConfigurar
              ? 'Configuración pendiente: esta compilación no tiene el '
                  'client ID de Google (ver docs/DRIVE_SETUP.md).'
              : ajustes.habilitado
                  ? 'Cuenta: ${ajustes.cuenta}\n${_ultimoTexto(ajustes)}'
                  : 'Una vez al día sube a tu Google Drive un respaldo '
                      'cifrado con una contraseña que eliges una sola vez. '
                      'Los archivos solo los puedes abrir con esa contraseña.'),
          value: ajustes.habilitado,
          onChanged: (_ocupado || sinConfigurar) ? null : _cambiar,
        ),
        if (ajustes.habilitado && ajustes.ultimoFallo != null)
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 4),
            child: Text(
              'Último intento falló: ${_falloTexto(ajustes.ultimoFallo!)}.',
              key: const Key('respaldo_drive_fallo'),
              style: TextStyle(color: errorColor),
            ),
          ),
        if (ajustes.habilitado)
          ListTile(
            key: const Key('respaldar_ahora'),
            leading: const Icon(Icons.cloud_upload_outlined),
            title: const Text('Respaldar ahora'),
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
    if (ultimo == null) return 'Aún no se ha hecho un respaldo.';
    final hoy = DayKey.fromDate(DateTime.now());
    if (ultimo == hoy) return 'Último respaldo: hoy.';
    return 'Último respaldo: el ${dayMonthLabelWithYear(ultimo, today: hoy)}.';
  }

  String _falloTexto(DriveApiFailure fallo) => switch (fallo) {
        DriveApiFailure.offline =>
          'sin conexión; el próximo intento automático lo reintentará',
        DriveApiFailure.unauthorized =>
          'la sesión de Google caducó; vuelve a entrar en la cuenta',
        DriveApiFailure.failed =>
          'Google rechazó el intento; prueba más tarde',
      };

  String _mensaje(AutoBackupStatus status) => switch (status) {
        AutoBackupStatus.ok => 'Respaldo subido a Google Drive.',
        AutoBackupStatus.sinCambios => 'Ya hay un respaldo de hoy.',
        AutoBackupStatus.deshabilitado =>
          'El respaldo automático está apagado.',
        AutoBackupStatus.claveNoDisponible =>
          'Este teléfono ya no tiene la clave de cifrado; vuelve a '
          'activar el respaldo con tu contraseña.',
        AutoBackupStatus.offline =>
          'Sin conexión: el próximo respaldo automático lo reintentará.',
        AutoBackupStatus.unauthorized =>
          'La sesión de Google caducó; vuelve a entrar en la cuenta.',
        AutoBackupStatus.failed =>
          'Google rechazó el respaldo; inténtalo más tarde.',
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
            context, 'No se pudo conectar con Google; no se activó el '
            'respaldo.');
      case EnableClaveNoDisponible():
        showAppSnackBar(context,
            'El Keystore de Android no pudo guardar la clave; '
            'inténtalo de nuevo.');
      case DriveEnabled(:final primerRespaldo):
        showAppSnackBar(context, switch (primerRespaldo) {
          null => 'Respaldo automático activado.',
          AutoBackupStatus.ok =>
            'Respaldo automático activado: primer respaldo subido a '
            'Google Drive.',
          _ => 'Respaldo automático activado. ${_mensaje(primerRespaldo)}',
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
        title: const Text('¿Quitar el respaldo automático?'),
        content: const Text(
          'Aura dejará de subir respaldos a Google Drive y cerrará la '
          'sesión de Google en este teléfono. Los archivos que ya subiste '
          'quedan en tu Google Drive y puedes borrarlos desde ahí.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Quitar respaldo'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    setState(() => _ocupado = true);
    await widget.service.disable();
    if (!mounted) return;
    setState(() => _ocupado = false);
    showAppSnackBar(context, 'Respaldo automático desactivado.');
  }
}
