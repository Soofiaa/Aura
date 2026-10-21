import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:aura/data/database/app_database.dart';

void main() {
  test('la conexion real activa foreign_keys y secure_delete', () {
    final db = sqlite3.openInMemory();
    addTearDown(db.dispose);

    configureConnection(db);

    expect(db.select('PRAGMA foreign_keys').single.values.single, 1);
    expect(db.select('PRAGMA secure_delete').single.values.single, 1);
  });
}
