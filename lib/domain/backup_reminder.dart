import '../utils/day_key.dart';

// Recordatorio local de respaldo (1.1.0, sin notificacion del sistema).

/// Dias desde el ultimo respaldo a partir de los que se recuerda (un ciclo).
const int diasUmbralRecordatorioRespaldo = 30;

/// Dias de uso antes del primer recordatorio, contados desde primerUso.
const int diasGraciaRecordatorioRespaldo = 7;

/// Dias que "Ahora no" pospone el recordatorio.
const int diasPosponerRecordatorioRespaldo = 7;

/// true si hay que recordar crear un respaldo hoy. Funcion pura: sin
/// reloj propio ni plataforma; [today] es el "hoy" inyectado en formato
/// DayKey (misma filosofia que planNotifications).
///
/// - [activado]: el interruptor de Ajustes. Apagado, nunca se recuerda.
/// - [hayRegistros]: sin ningun dia registrado no hay nada que respaldar.
/// - [primerUso]: primera vez que esta version abrio la app (o desde el
///   ultimo "Borrar todos los datos"). Antes de cumplir
///   [diasGraciaRecordatorioRespaldo] dias no se recuerda.
/// - [ultimoRespaldo]: ultimo respaldo guardado o compartido con exito
///   desde este telefono; null si nunca hubo uno. Se recuerda cuando
///   pasaron [diasUmbralRecordatorioRespaldo] dias o mas.
/// - [pospuestoHasta]: "Ahora no" lo oculta hasta ese dia, exclusive: el
///   mismo dia de [pospuestoHasta] vuelve a recordarse.
///
/// Una fecha guardada en el futuro (reloj del telefono atrasado despues)
/// cuenta como reciente: nunca hace aparecer el recordatorio.
bool deberiaRecordarRespaldo({
  required String today,
  required bool activado,
  required bool hayRegistros,
  required String primerUso,
  String? ultimoRespaldo,
  String? pospuestoHasta,
}) {
  if (!activado || !hayRegistros) return false;
  if (DayKey.diffInDays(primerUso, today) < diasGraciaRecordatorioRespaldo) {
    return false;
  }
  if (pospuestoHasta != null && DayKey.isBefore(today, pospuestoHasta)) {
    return false;
  }
  if (ultimoRespaldo == null) return true;
  return DayKey.diffInDays(ultimoRespaldo, today) >=
      diasUmbralRecordatorioRespaldo;
}
