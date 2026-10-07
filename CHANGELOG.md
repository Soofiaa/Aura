# Cambios

## Sin publicar

### Nuevo

- **Duración habitual del período** en Ajustes → "Tu ciclo", con botones − y + (de 1 a 15 días). Aura la usa para estimar cuántos días dura tu período mientras todavía no tienes períodos terminados; después usa el promedio de los tuyos. Cambiarla no modifica tus registros.
- **"Me llegó hoy"** en el Calendario y en Inicio (cuando no hay un período en curso): eliges Hoy, Ayer u Otro día y se guarda solo el primer día. Avisa si el día queda tan cerca de otro período que se sumará a él.
- **Días estimados** en el Calendario: los días que faltan del período en curso se ven con borde punteado y no se guardan. La leyenda distingue "Período registrado" y "Estimado sin confirmar".
- **"Confirmar días"** en el Calendario: cuando el último día estimado ya llegó, los estimados pasan a registrados y el período queda terminado.
- **Terminar el período** desde Inicio ("Sigue", "Terminó hoy" y "Ya terminó antes") y desde el Calendario ("Terminó este día"). Se completan los días sin registro y se respetan los días que marcaste sin sangrado. Si el período quedaría de 1 día, Aura lo pregunta.
- **Elegir varios días** en el Calendario: el panel guía cada paso, un tercer toque alarga, mueve o acorta el rango sin perderlo, y un rango que termina hace 2 días o más deja el período terminado solo si su último día es el último del período resultante; si quedan días marcados después, solo se marcan. Si termina hoy o ayer, Aura pregunta.
- Todas estas acciones tienen **"Deshacer"** durante 8 segundos.
- **Respaldo y restauración** de tus datos en un archivo JSON:
  - **Crear respaldo** guarda el archivo en el teléfono ("Guardar en el teléfono") o lo comparte con la hoja de compartir del sistema, después de avisar que contiene datos de salud.
  - **Restaurar un respaldo** revisa el archivo antes de tocar nada y pide confirmación con la fecha del respaldo y los días que se reemplazan. Si el respaldo trae menos días que los actuales, lo avisa.
  - **Deshacer** en el mensaje de éxito vuelve a los datos que tenías antes de importar. El mensaje no se cierra solo.
- Nueva sección **"Tus datos"** en Ajustes, con las dos opciones de respaldo antes de "Borrar todos los datos".
- La confirmación de importar cuenta los **días con registro (M de período)**: los días marcados como "no hubo sangrado" cuentan como registro, pero no como período.
- **Copia de seguridad al actualizar:** antes de convertir tus datos al formato nuevo, Aura guarda una copia dentro del teléfono. Si no puede guardarla, no convierte nada y muestra "No se pudo actualizar Aura" con el botón "Reintentar"; si falta espacio, lo dice. La copia se borra cuando guardas un respaldo en el teléfono, al abrir la app si tiene más de 30 días, o con "Borrar todos los datos".

### Cambiado

- La pregunta de Inicio "¿Sigue tu período hoy?" cambia "Sí" y "No" por "Sigue", "Terminó hoy" y "Ya terminó antes", e indica el día del período y la duración estimada.
- En el Calendario, el botón "Seleccionar varios días" pasa a llamarse "Elegir varios días" y está siempre visible junto a "Me llegó hoy". Hoy se distingue con un borde en vez de un relleno, para no confundirlo con un día registrado.
- Marcar un día o un rango en el Calendario ahora tiene "Deshacer".
- Los avisos con "Deshacer" (Inicio y "Marca quitada" del Calendario) ahora se cierran solos a los 8 segundos.
- Un mensaje nuevo reemplaza al anterior en vez de esperar en cola.
- El Calendario y Ajustes se actualizan solos cuando los datos cambian en otra pestaña (por ejemplo, al importar o borrar todo).
- La versión que muestra Ajustes sale de una constante única, comprobada con un test contra `pubspec.yaml`.
- "Borrar todos los datos" también borra la copia guardada antes de la última importación, la copia guardada antes de actualizar y los archivos temporales del respaldo.
- La duración del período que se usa para estimar la fase menstrual solo cuenta períodos terminados: registrar solo el primer día ya no la acorta. Si no hay ningún período terminado, se usa la duración habitual de Ajustes (5 días si no la cambias).
- Al actualizar, los períodos que ya tenías se marcan como terminados solo cuando se puede deducir con seguridad: dos o más días marcados, sin huecos de más de un día y, si es el más reciente, terminado hace más de 7 días. Los demás quedan abiertos. Ningún día ni síntoma cambia.
- Los respaldos nuevos usan un formato que incluye el fin de cada período. Los respaldos anteriores se siguen pudiendo restaurar; una versión anterior de Aura rechaza un respaldo nuevo sin tocar tus datos.

## 1.0.1

### Corregido

- Registrar solo síntomas ya no marca el día como de sangrado: el interruptor "Día de sangrado" ahora empieza apagado en un día sin registro, así que solo cuenta como período si lo enciendes.
- El flujo ya no se guarda como "Ligero" si no lo eliges: queda "Sin especificar" y no cambia el promedio de flujo de Estadísticas.
- El estado de ánimo ya no se guarda como "Normal" si no lo eliges: queda "Sin registrar" y no cuenta en el gráfico de ánimo.
- Ya no se pueden registrar días futuros desde el formulario.
- Los datos que ya tenías guardados no se modifican.
