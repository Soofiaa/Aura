import 'package:flutter/material.dart';

/// Decision 14: antes de terminar un periodo que quedaria de 1 dia se
/// pregunta si de verdad duro solo 1 dia. True si la usuaria confirma.
/// Lo usan Inicio ("Termino hoy", "Ya termino antes") y el Calendario
/// ("Termino este dia").
Future<bool> confirmSingleDayPeriod(BuildContext context) async {
  final resultado = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('¿Tu período duró solo 1 día?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Sí, duró 1 día'),
        ),
      ],
    ),
  );
  return resultado ?? false;
}
