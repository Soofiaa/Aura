import 'package:flutter/material.dart';

import '../domain/password_strength.dart';

/// Lo que eligio la usuaria en "Proteger tu respaldo" (HU-06b, CP3).
/// null (dialogo cerrado con "Cancelar") = no exportar nada.
sealed class ProtectBackupChoice {
  const ProtectBackupChoice();
}

/// Exportar cifrado con [password]. La contrasena viaja solo de aqui a
/// BackupService.writeExportFile; no se guarda en ningun otro lado.
class ProtectWithPassword extends ProtectBackupChoice {
  const ProtectWithPassword(this.password);
  final String password;

  @override
  String toString() => 'ProtectWithPassword';
}

/// Exportar sin cifrar, tras confirmarlo.
class ProtectWithoutPassword extends ProtectBackupChoice {
  const ProtectWithoutPassword();
}

/// Abre "Proteger tu respaldo". Devuelve null si se cancela.
Future<ProtectBackupChoice?> showProtectBackupDialog(BuildContext context) =>
    showDialog<ProtectBackupChoice>(
      context: context,
      // Tocar fuera no cierra: se perderia lo escrito. "Cancelar" y
      // "atras" si cierran.
      barrierDismissible: false,
      builder: (_) => const ProtectBackupDialog(),
    );

/// Dialogo para elegir la contrasena del respaldo cifrado (HU6b-1, HU6b-3,
/// HU6b-4). La contrasena vive solo en los TextEditingController de este
/// dialogo; al cerrarse se limpian y se liberan (mejor esfuerzo: Dart no
/// puede borrar un String de la memoria).
class ProtectBackupDialog extends StatefulWidget {
  const ProtectBackupDialog({super.key});

  @override
  State<ProtectBackupDialog> createState() => _ProtectBackupDialogState();
}

class _ProtectBackupDialogState extends State<ProtectBackupDialog> {
  final _password = TextEditingController();
  final _repeat = TextEditingController();
  final _passwordFocus = FocusNode();
  final _repeatFocus = FocusNode();

  bool _visible = false;

  // Los errores se muestran solo despues de salir de cada campo (no
  // mientras se escribe).
  bool _passwordTouched = false;
  bool _repeatTouched = false;

  @override
  void initState() {
    super.initState();
    _password.addListener(_refresh);
    _repeat.addListener(_refresh);
    _passwordFocus.addListener(_onPasswordFocus);
    _repeatFocus.addListener(_onRepeatFocus);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _onPasswordFocus() {
    if (!_passwordFocus.hasFocus && mounted) {
      setState(() => _passwordTouched = true);
    }
  }

  void _onRepeatFocus() {
    if (!_repeatFocus.hasFocus && mounted) {
      setState(() => _repeatTouched = true);
    }
  }

  @override
  void dispose() {
    // Primero se quitan los listeners: limpiar los campos no debe
    // reconstruir un dialogo que ya se esta cerrando.
    _password.removeListener(_refresh);
    _repeat.removeListener(_refresh);
    _passwordFocus.removeListener(_onPasswordFocus);
    _repeatFocus.removeListener(_onRepeatFocus);
    _password
      ..clear()
      ..dispose();
    _repeat
      ..clear()
      ..dispose();
    _passwordFocus.dispose();
    _repeatFocus.dispose();
    super.dispose();
  }

  bool get _longEnough => isPasswordLongEnough(_password.text);

  // Igualdad exacta, sin normalizar (HU6b-11).
  bool get _matches => _password.text == _repeat.text;

  bool get _valid => _longEnough && _matches;

  void _continue() {
    if (!_valid) {
      setState(() {
        _passwordTouched = true;
        _repeatTouched = true;
      });
      return;
    }
    Navigator.pop(context, ProtectWithPassword(_password.text));
  }

  Future<void> _withoutPassword() async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Continuar sin contraseña?'),
        content: const Text(
          'El archivo contendrá tus datos sin cifrar. Cualquiera que lo '
          'obtenga podrá leerlos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Volver'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continuar sin contraseña'),
          ),
        ],
      ),
    );
    if (confirmado == true && mounted) {
      Navigator.pop(context, const ProtectWithoutPassword());
    }
  }

  InputDecoration _decoration(String label, {String? helper, String? error}) =>
      InputDecoration(
        labelText: label,
        helperText: helper,
        helperMaxLines: 3,
        errorText: error,
        errorMaxLines: 3,
        border: const OutlineInputBorder(),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showLengthError = _passwordTouched && !_longEnough;
    final showMatchError = _repeatTouched && !_matches;
    return AlertDialog(
      // scrollable: titulo y contenido se desplazan juntos y las acciones
      // quedan fijas; asi caben con el teclado abierto (360x640).
      scrollable: true,
      title: const Text('Proteger tu respaldo'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Elige una contraseña para cifrar el archivo. Sin ella, nadie '
            'podrá leerlo aunque lo obtenga.',
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: Icon(
                    Icons.warning_amber_rounded,
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Aura no guarda tu contraseña y no puede recuperarla. '
                    'Si la olvidas, no podrás abrir este respaldo.',
                    style: TextStyle(
                      color: theme.colorScheme.onErrorContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('protect-password'),
            controller: _password,
            focusNode: _passwordFocus,
            obscureText: !_visible,
            autocorrect: false,
            enableSuggestions: false,
            enableIMEPersonalizedLearning: false,
            autofillHints: null,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => _repeatFocus.requestFocus(),
            decoration:
                _decoration(
                  'Contraseña',
                  helper:
                      'Mínimo 10 caracteres. Una frase con varias '
                      'palabras es fácil de recordar y difícil de adivinar.',
                  error: showLengthError ? 'Usa al menos 10 caracteres.' : null,
                ).copyWith(
                  suffixIcon: IconButton(
                    tooltip: _visible
                        ? 'Ocultar contraseña'
                        : 'Mostrar contraseña',
                    icon: Icon(
                      _visible ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () => setState(() => _visible = !_visible),
                  ),
                ),
          ),
          const SizedBox(height: 8),
          _StrengthIndicator(password: _password.text),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('protect-repeat'),
            controller: _repeat,
            focusNode: _repeatFocus,
            obscureText: !_visible,
            autocorrect: false,
            enableSuggestions: false,
            enableIMEPersonalizedLearning: false,
            autofillHints: null,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _continue(),
            decoration: _decoration(
              'Repite la contraseña',
              error: showMatchError ? 'Las contraseñas no coinciden.' : null,
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _withoutPassword,
            child: const Text('Continuar sin contraseña'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _valid ? _continue : null,
          child: const Text('Proteger y continuar'),
        ),
      ],
    );
  }
}

/// Barra y etiqueta de fortaleza (HU6b-4). El color nunca es la unica
/// senal: la etiqueta dice el nivel y el lector de pantalla la anuncia.
class _StrengthIndicator extends StatelessWidget {
  const _StrengthIndicator({required this.password});

  final String password;

  @override
  Widget build(BuildContext context) {
    if (password.isEmpty) return const SizedBox.shrink();
    final strength = passwordStrength(password);
    final scheme = Theme.of(context).colorScheme;
    final (value, color) = switch (strength) {
      PasswordStrength.weak => (1 / 3, scheme.error),
      PasswordStrength.acceptable => (2 / 3, scheme.tertiary),
      PasswordStrength.strong => (1.0, scheme.primary),
    };
    // liveRegion: el lector de pantalla anuncia la etiqueta cuando cambia,
    // es decir, solo cuando cambia el nivel.
    return Semantics(
      container: true,
      liveRegion: true,
      label: 'Fortaleza: ${strength.label}. Es solo una orientación.',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(
              value: value,
              minHeight: 6,
              color: color,
              backgroundColor: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(3),
            ),
            const SizedBox(height: 4),
            Text(
              'Fortaleza: ${strength.label}',
              key: const ValueKey('protect-strength'),
              style: TextStyle(color: scheme.onSurface),
            ),
            Text(
              'Es solo una orientación.',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
