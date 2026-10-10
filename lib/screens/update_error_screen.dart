import 'package:flutter/material.dart';

import '../utils/colors.dart';

/// Pantalla que se muestra si la base no se pudo abrir al arrancar (la
/// copia previa a la migracion no se pudo escribir, o la migracion fallo
/// y se revirtio). Los datos no cambiaron.
class UpdateErrorScreen extends StatelessWidget {
  const UpdateErrorScreen({
    super.key,
    required this.outOfSpace,
    required this.retrying,
    required this.onRetry,
  });

  final bool outOfSpace;
  final bool retrying;
  final VoidCallback onRetry;

  static const String title = 'No se pudo actualizar Aura';
  static const String safeMessage =
      'Aura no pudo abrir tus datos, pero no borró nada. Cierra la app y '
      'vuelve a abrirla. Si el problema sigue, no desinstales la app, '
      'porque se perderían tus datos, y escribe a sofia.menzel.dev@gmail.com';
  static const String outOfSpaceMessage =
      'Libera espacio en el teléfono e inténtalo de nuevo';
  static const String outOfSpaceSafeMessage =
      'Tus datos están a salvo: no se borró ni se cambió nada.';

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline,
                    size: 56, color: AppColors.primary),
                const SizedBox(height: 16),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 16),
                // Seleccionable: permite copiar el correo.
                SelectableText(
                  outOfSpace ? outOfSpaceMessage : safeMessage,
                  textAlign: TextAlign.center,
                  style: textTheme.bodyLarge,
                ),
                if (outOfSpace) ...[
                  const SizedBox(height: 12),
                  Text(
                    outOfSpaceSafeMessage,
                    textAlign: TextAlign.center,
                    style: textTheme.bodyMedium,
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  height: 48,
                  child: FilledButton(
                    onPressed: retrying ? null : onRetry,
                    child: retrying
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Reintentar'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
