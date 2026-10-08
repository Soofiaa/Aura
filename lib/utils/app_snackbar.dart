import 'package:flutter/material.dart';

/// Cuanto dura un aviso simple (sin accion).
const Duration snackBarDuration = Duration(seconds: 5);

/// Cuanto dura un aviso con "Deshacer" transitorio.
const Duration undoSnackBarDuration = Duration(seconds: 7);

/// Unica forma de mostrar un aviso en la app: descarta los que haya
/// (visible y en cola) y muestra [message] enseguida.
///
/// - Sin [action]: se cierra solo a los [snackBarDuration].
/// - Con [action] ("Deshacer"): se cierra solo a los
///   [undoSnackBarDuration]. `persist: false` va explicito: si no se
///   indica, Flutter (>= 3.29) lo toma como `persist: true` cuando hay
///   accion y el aviso nunca se cierra solo.
/// - Con [persistent]: no se cierra solo y lleva una "x" para cerrarlo
///   (etiqueta "Cerrar", ver aura_localizations.dart). Solo lo usa el
///   exito de la importacion: su "Deshacer" es la unica forma de
///   revertirla.
///
/// ScaffoldMessenger encola los mensajes; sin la limpieza, uno
/// persistente bloquearia a todos los siguientes hasta que la usuaria lo
/// cierre.
ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showAppSnackBar(
  BuildContext context,
  String message, {
  SnackBarAction? action,
  bool persistent = false,
}) {
  final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
  return messenger.showSnackBar(SnackBar(
    content: Text(message),
    action: action,
    persist: persistent,
    showCloseIcon: persistent,
    duration: action == null ? snackBarDuration : undoSnackBarDuration,
  ));
}
