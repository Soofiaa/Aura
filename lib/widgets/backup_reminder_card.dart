import 'package:flutter/material.dart';

import '../data/backup/backup_reminder_store.dart';
import '../utils/aura_localizations.dart';
import '../utils/colors.dart';
import '../utils/date_labels.dart';
import '../utils/day_key.dart';

/// Tarjeta "Guarda una copia de tus registros" de Inicio (recordatorio de
/// respaldo). Quien la muestra decide cuando (deberiaRecordarRespaldo);
/// esta solo arma los textos y los botones. Un contenedor semantico con
/// el titulo como encabezado, sin liveRegion: aparece al abrir Inicio, no
/// interrumpe.
class BackupReminderCard extends StatelessWidget {
  const BackupReminderCard({
    super.key,
    required this.estado,
    required this.today,
    required this.onCrear,
    required this.onAhoraNo,
    required this.onNoRecordar,
  });

  final BackupReminderState estado;
  final String today;

  /// null mientras hay otra operacion de respaldo en curso.
  final VoidCallback? onCrear;
  final VoidCallback onAhoraNo;
  final VoidCallback onNoRecordar;

  @override
  Widget build(BuildContext context) {
    final ultimo = estado.ultimoRespaldo;
    final titulo = ultimo == null
        ? tr('Guarda una copia de tus registros', 'Save a copy of your logs')
        : tr('Hace ${DayKey.diffInDays(ultimo, today)} días que no creas un '
            'respaldo',
            "It's been ${DayKey.diffInDays(ultimo, today)} days since your "
            'last backup');
    final texto = ultimo == null
        ? tr('Aura guarda todo solo en este teléfono. Si lo pierdes o se daña, '
            'tus registros no se pueden recuperar. Un respaldo crea una '
            'copia en el lugar que elijas.',
            'Aura keeps everything only on this phone. If you lose it or it '
            "breaks, your logs can't be recovered. A backup makes a copy "
            'wherever you choose.')
        : tr('Tu último respaldo es del '
            '${dayMonthLabelWithYear(ultimo, today: today)}. Lo que '
            'registraste después está solo en este teléfono.',
            'Your last backup is from '
            '${dayMonthLabelWithYear(ultimo, today: today)}. Anything you '
            'logged after that is only on this phone.');
    const minimo = Size(48, 48);

    return Semantics(
      container: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            // Decorativo: el titulo ya dice de que se trata.
            const ExcludeSemantics(
              child: Icon(Icons.save_outlined,
                  color: AppColors.accentStrong, size: 32),
            ),
            const SizedBox(height: 8),
            Semantics(
              container: true,
              header: true,
              child: Text(
                titulo,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 4),
            // Nodo propio: si no, el texto se funde en el contenedor y se
            // lee antes que el titulo.
            Semantics(
              container: true,
              child: Text(
                texto,
                style: const TextStyle(
                    fontSize: 14, color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 12),
            // Wrap, como en "¿Sigue tu período hoy?": con letra grande,
            // "Ahora no" baja a la linea siguiente en vez de desbordar.
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                ElevatedButton(
                  onPressed: onCrear,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.textPrimary,
                    minimumSize: minimo,
                  ),
                  child: Text(tr('Crear respaldo', 'Create backup')),
                ),
                OutlinedButton(
                  onPressed: onAhoraNo,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    minimumSize: minimo,
                  ),
                  child: Text(tr('Ahora no', 'Not now')),
                ),
              ],
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: onNoRecordar,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                minimumSize: minimo,
              ),
              child: Text(
                tr('No recordármelo más', "Don't remind me again"),
                textAlign: TextAlign.center,
                style: const TextStyle(decoration: TextDecoration.underline),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
