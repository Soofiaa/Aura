import 'package:flutter/material.dart';

/// Abre "Respaldo protegido" (HU-06b, CP4). Devuelve la contrasena escrita
/// o null si se cancela. [initialPassword] y [errorText] sirven para el
/// reintento: lo escrito vuelve seleccionado, para corregirlo o
/// reemplazarlo, junto con el error (HU6b-8).
Future<String?> showUnlockBackupDialog(
  BuildContext context, {
  String? initialPassword,
  String? errorText,
}) => showDialog<String>(
  context: context,
  // Tocar fuera no cierra: se perderia lo escrito. "Cancelar" y
  // "atras" si cierran.
  barrierDismissible: false,
  builder: (_) => UnlockBackupDialog(
    initialPassword: initialPassword,
    errorText: errorText,
  ),
);

/// Pide la contrasena de un respaldo cifrado. Sin largo minimo ni
/// indicador de fortaleza: el archivo ya existe. La contrasena vive solo
/// en el TextEditingController de este dialogo, que se limpia y se libera
/// al cerrarse (mejor esfuerzo: Dart no puede borrar un String).
class UnlockBackupDialog extends StatefulWidget {
  const UnlockBackupDialog({super.key, this.initialPassword, this.errorText});

  final String? initialPassword;
  final String? errorText;

  @override
  State<UnlockBackupDialog> createState() => _UnlockBackupDialogState();
}

class _UnlockBackupDialogState extends State<UnlockBackupDialog> {
  late final TextEditingController _password;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialPassword ?? '';
    _password = TextEditingController(text: initial)
      ..selection = TextSelection(baseOffset: 0, extentOffset: initial.length);
    _password.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    // Primero se quita el listener: limpiar el campo no debe reconstruir
    // un dialogo que ya se esta cerrando.
    _password.removeListener(_refresh);
    _password
      ..clear()
      ..dispose();
    super.dispose();
  }

  bool get _canOpen => _password.text.isNotEmpty;

  void _open() {
    if (!_canOpen) return;
    Navigator.pop(context, _password.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      // scrollable: titulo y contenido se desplazan juntos y las acciones
      // quedan fijas; asi caben con el teclado abierto (360x640).
      scrollable: true,
      title: const Text('Respaldo protegido'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Este respaldo está protegido con contraseña. Escríbela para '
            'abrirlo.',
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('unlock-password'),
            controller: _password,
            autofocus: true,
            obscureText: !_visible,
            autocorrect: false,
            enableSuggestions: false,
            enableIMEPersonalizedLearning: false,
            autofillHints: null,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _open(),
            decoration: InputDecoration(
              labelText: 'Contraseña',
              border: const OutlineInputBorder(),
              errorText: widget.errorText,
              errorMaxLines: 4,
              suffixIcon: IconButton(
                tooltip: _visible ? 'Ocultar contraseña' : 'Mostrar contraseña',
                icon: Icon(_visible ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _visible = !_visible),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _canOpen ? _open : null,
          child: const Text('Abrir respaldo'),
        ),
      ],
    );
  }
}
