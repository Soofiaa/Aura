import 'dart:async';

import 'package:aura/data/backup/drive_backup_settings_store.dart';

/// Ajustes del respaldo en Drive en memoria para tests de widget (la E/S
/// real no avanza dentro del reloj falso de testWidgets). El almacen real
/// se prueba en test/data/backup/drive_backup_settings_store_test.dart.
class FakeDriveBackupSettingsStore extends DriveBackupSettingsStore {
  FakeDriveBackupSettingsStore(
      [DriveBackupSettings initial = const DriveBackupSettings()])
      : super(supportDirectory: () => throw UnimplementedError()) {
    _state = initial;
  }

  late DriveBackupSettings _state;
  final StreamController<DriveBackupSettings> _cambios =
      StreamController<DriveBackupSettings>.broadcast();

  DriveBackupSettings get current => _state;

  @override
  Stream<DriveBackupSettings> watch() => Stream.multi((controller) {
        final sub = _cambios.stream.listen(controller.add);
        read().then(controller.add, onError: controller.addError);
        controller.onCancel = sub.cancel;
      });

  @override
  Future<DriveBackupSettings> read() async => _state;

  @override
  Future<DriveBackupSettings> guardar(DriveBackupSettings nuevo) async {
    _state = nuevo;
    _cambios.add(nuevo);
    return nuevo;
  }

  @override
  Future<void> delete() async => guardar(const DriveBackupSettings());
}
