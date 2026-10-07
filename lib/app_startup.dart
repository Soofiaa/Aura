import 'data/backup/pre_migration_copy.dart';
import 'data/database/app_database.dart';
import 'data/repositories/cycle_repository.dart';

/// Resultado de abrir la base al arrancar la app.
sealed class StartupResult {
  const StartupResult();
}

/// La base abrio (y migro, si hacia falta).
final class StartupReady extends StartupResult {
  const StartupReady({required this.onboardingSeen});
  final bool onboardingSeen;
}

/// La base no abrio: no se pudo escribir la copia previa a la migracion,
/// o la migracion fallo (su transaccion se revirtio).
final class StartupFailed extends StartupResult {
  const StartupFailed({required this.outOfSpace, required this.error});

  /// El telefono no tiene espacio (mensaje propio en la pantalla).
  final bool outOfSpace;

  /// Solo para depurar; nunca se muestra.
  final Object error;
}

/// Abre la base ANTES que cualquier otra cosa que la use (notificaciones,
/// limpieza de temporales, pantallas): asi un fallo de la migracion se
/// muestra en una pantalla de error en vez de dejar la app congelada.
class AppStartup {
  AppStartup({
    AppDatabase Function()? createDatabase,
    required void Function() onReady,
  })  : _createDatabase = createDatabase ?? AppDatabase.new,
        _onReady = onReady;

  final AppDatabase Function() _createDatabase;

  /// Lo que arranca recien con la base abierta. Se llama una sola vez.
  final void Function() _onReady;

  AppDatabase? _database;

  /// Intenta abrir la base. Cada reintento cierra la anterior y crea una
  /// nueva: drift guarda el error de una apertura fallida y lo repetiria
  /// en cada consulta. Si abre, la deja como instancia global de la app.
  Future<StartupResult> open() async {
    final previous = _database;
    if (previous != null) {
      try {
        await previous.close();
      } catch (_) {
        // Una base que no llego a abrir puede fallar al cerrarse.
      }
      _database = null;
    }
    try {
      // Dentro del try: un fallo al crear la base tambien termina en
      // StartupFailed y no en una app congelada.
      final db = _createDatabase();
      _database = db;
      final repository = CycleRepository(db);
      // Primera consulta: dispara la copia previa y la migracion.
      final onboardingSeen = await repository.getOnboardingSeen();
      appDatabase = db;
      cycleRepository = repository;
      _onReady();
      return StartupReady(onboardingSeen: onboardingSeen);
    } catch (e) {
      return StartupFailed(outOfSpace: isOutOfSpaceError(e), error: e);
    }
  }
}
