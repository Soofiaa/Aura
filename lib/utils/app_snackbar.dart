import 'package:flutter/material.dart';

/// Cuanto dura un aviso con "Deshacer" transitorio. Esos SnackBar deben
/// llevar ademas `persist: false` explicito: si no se indica, Flutter
/// (>= 3.29) lo toma como `persist: true` cuando hay accion y el aviso
/// nunca se cierra solo. El unico persistente a proposito es el exito
/// de la importacion (backup_section.dart).
const Duration undoSnackBarDuration = Duration(seconds: 8);

/// Unica forma de mostrar un SnackBar en la app: descarta los que haya
/// (visible y en cola) y muestra [snackBar] enseguida.
///
/// ScaffoldMessenger encola los mensajes; sin esto, uno persistente (el
/// exito de la importacion con "Deshacer") bloquearia a todos los
/// siguientes hasta que la usuaria lo cierre.
ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showAppSnackBar(
  BuildContext context,
  SnackBar snackBar,
) {
  final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
  return messenger.showSnackBar(snackBar);
}
