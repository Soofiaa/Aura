import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

import 'backup_file_gateway.dart';

/// [BackupFileGateway] real, con share_plus y file_picker. Unico archivo
/// de la app que importa esos plugins.
class PluginBackupFileGateway implements BackupFileGateway {
  const PluginBackupFileGateway();

  @override
  Future<void> shareFile(File file) async {
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'application/json')],
    ));
  }

  @override
  Future<bool> saveToDevice({
    required String fileName,
    required Uint8List bytes,
  }) async {
    // Escribe directo en el destino elegido (SAF): no deja copia en la
    // cache. null = la usuaria cancelo.
    final path = await FilePicker.saveFile(
      fileName: fileName,
      bytes: bytes,
    );
    return path != null;
  }

  @override
  Future<String?> pickBackupFile() async {
    // FileType.any y no custom/json: algunos proveedores (HyperOS, Drive)
    // informan un .json con un tipo MIME generico y el filtro lo dejaria
    // gris. El contenido se valida igual en decodeBackup.
    final result = await FilePicker.pickFiles(type: FileType.any);
    return result?.files.single.path;
  }
}
