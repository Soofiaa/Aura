class Ciclo {
  int id;
  DateTime inicio;
  int duracionCiclo;
  int duracionMenstruacion;
  List<String> sintomas;
  String estadoAnimo;

  Ciclo({
    required this.id,
    required this.inicio,
    required this.duracionCiclo,
    required this.duracionMenstruacion,
    required this.sintomas,
    required this.estadoAnimo,
  });
}
