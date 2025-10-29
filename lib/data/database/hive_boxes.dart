import 'package:hive_flutter/hive_flutter.dart';

class HiveBoxes {
  // Nombres de las cajas (bases locales)
  static const String diasMenstruacion = 'diasMenstruacion';
  static const String ciclos = 'ciclos';
  static const String configuracion = 'configuracion';

  // Métodos para acceder a las cajas reales de Hive
  static Box getDiasBox() => Hive.box(diasMenstruacion);
  static Box getCiclosBox() => Hive.box(ciclos);
  static Box getConfigBox() => Hive.box(configuracion);
}
