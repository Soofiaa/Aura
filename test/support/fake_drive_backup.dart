import 'package:aura/data/backup/drive_backup_gateway.dart';
import 'package:aura/utils/keystore_vault.dart';

/// Gateway de Drive en blanco: para tests que solo necesitan que exista el
/// servicio de respaldo en Drive (el comportamiento de verdad se prueba en
/// test/screens/drive_backup_section_test.dart, con dobles que observan).
class FakeBlankDriveBackupGateway implements DriveBackupGateway {
  @override
  Future<DriveSignInResult> signIn() async => const DriveSignedIn('x@y.z');

  @override
  Future<void> signOut() async {}

  @override
  Future<String?> restoreSession() async => null;

  @override
  Future<void> uploadBackup({
    required String fileName,
    required List<int> bytes,
  }) async {}
}

/// Keystore en blanco para el mismo fin.
class FakeBlankKeystoreVault implements KeystoreVault {
  @override
  Future<String> seal(String plaintext) async => 'sellada:$plaintext';

  @override
  Future<String> open(String blob) async => blob.substring('sellada:'.length);
}
