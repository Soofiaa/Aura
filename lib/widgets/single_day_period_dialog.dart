import 'package:flutter/material.dart';

import '../utils/aura_localizations.dart';

/// Decision 14: antes de terminar un periodo que quedaria de 1 dia se
/// pregunta si de verdad duro solo 1 dia. True si la usuaria confirma.
/// Lo usan Inicio ("Termino hoy", "Ya termino antes") y el Calendario
/// ("Termino este dia").
Future<bool> confirmSingleDayPeriod(BuildContext context) async {
  final resultado = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr('¿Tu período duró solo 1 día?',
          'Did your period last only 1 day?')),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(tr('Cancelar', 'Cancel')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(tr('Sí, duró 1 día', 'Yes, it lasted 1 day')),
        ),
      ],
    ),
  );
  return resultado ?? false;
}
