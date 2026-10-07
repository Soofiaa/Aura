# Cambios

## Sin publicar

### Nuevo

- **Respaldo y restauración** de tus datos en un archivo JSON:
  - **Crear respaldo** guarda el archivo en el teléfono ("Guardar en el teléfono") o lo comparte con la hoja de compartir del sistema, después de avisar que contiene datos de salud.
  - **Restaurar un respaldo** revisa el archivo antes de tocar nada y pide confirmación con la fecha del respaldo y los días que se reemplazan. Si el respaldo trae menos días que los actuales, lo avisa.
  - **Deshacer** en el mensaje de éxito vuelve a los datos que tenías antes de importar. El mensaje no se cierra solo.
- Nueva sección **"Tus datos"** en Ajustes, con las dos opciones de respaldo antes de "Borrar todos los datos".
- La confirmación de importar cuenta los **días con registro (M de período)**: los días marcados como "no hubo sangrado" cuentan como registro, pero no como período.
- **Copia de seguridad al actualizar:** antes de convertir tus datos al formato nuevo, Aura guarda una copia dentro del teléfono. Si no puede guardarla, no convierte nada y muestra "No se pudo actualizar Aura" con el botón "Reintentar"; si falta espacio, lo dice. La copia se borra cuando guardas un respaldo en el teléfono, al abrir la app si tiene más de 30 días, o con "Borrar todos los datos".

### Cambiado

- Los avisos con "Deshacer" (Inicio y "Marca quitada" del Calendario) ahora se cierran solos a los 8 segundos.
- Un mensaje nuevo reemplaza al anterior en vez de esperar en cola.
- El Calendario y Ajustes se actualizan solos cuando los datos cambian en otra pestaña (por ejemplo, al importar o borrar todo).
- La versión que muestra Ajustes sale de una constante única, comprobada con un test contra `pubspec.yaml`.
- "Borrar todos los datos" también borra la copia guardada antes de la última importación, la copia guardada antes de actualizar y los archivos temporales del respaldo.
- La duración del período que se usa para estimar la fase menstrual solo cuenta períodos terminados: registrar solo el primer día ya no la acorta. Si no hay ningún período terminado, se usa una duración de 5 días.
- Al actualizar, los períodos que ya tenías se marcan como terminados solo cuando se puede deducir con seguridad: dos o más días marcados, sin huecos de más de un día y, si es el más reciente, terminado hace más de 7 días. Los demás quedan abiertos. Ningún día ni síntoma cambia.
- Los respaldos nuevos usan un formato que incluye el fin de cada período. Los respaldos anteriores se siguen pudiendo restaurar; una versión anterior de Aura rechaza un respaldo nuevo sin tocar tus datos.

## 1.0.1

### Corregido

- Registrar solo síntomas ya no marca el día como de sangrado: el interruptor "Día de sangrado" ahora empieza apagado en un día sin registro, así que solo cuenta como período si lo enciendes.
- El flujo ya no se guarda como "Ligero" si no lo eliges: queda "Sin especificar" y no cambia el promedio de flujo de Estadísticas.
- El estado de ánimo ya no se guarda como "Normal" si no lo eliges: queda "Sin registrar" y no cuenta en el gráfico de ánimo.
- Ya no se pueden registrar días futuros desde el formulario.
- Los datos que ya tenías guardados no se modifican.
