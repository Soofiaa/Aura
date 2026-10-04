import 'package:flutter/material.dart';

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
