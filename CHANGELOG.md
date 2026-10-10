# Cambios

## 1.1.0 (sin publicar)

### Nuevo

- **Duración habitual del período** en Ajustes → "Tu ciclo", con botones − y + (de 1 a 15 días). Aura la usa para estimar cuántos días dura tu período mientras todavía no tienes períodos terminados; después usa el promedio de los tuyos. Cambiarla no modifica tus registros.
- **"Me llegó hoy"** en el Calendario y en Inicio (cuando no hay un período en curso): eliges Hoy, Ayer u Otro día y se guarda solo el primer día. Avisa si el día queda tan cerca de otro período que se sumará a él.
- **Días estimados** en el Calendario: los días que faltan del período en curso se ven con borde punteado y no se guardan. La leyenda distingue "Período registrado" y "Estimado sin confirmar".
- **"Confirmar días"** en el Calendario: cuando el último día estimado ya llegó, los estimados pasan a registrados y el período queda terminado.
- **Terminar el período** desde Inicio ("Sigue", "Terminó hoy" y "Ya terminó antes") y desde el Calendario ("Terminó este día"). Se completan los días sin registro y se respetan los días que marcaste sin sangrado. Si el período quedaría de 1 día, Aura lo pregunta.
- **Elegir varios días** en el Calendario: el panel guía cada paso, un tercer toque alarga, mueve o acorta el rango sin perderlo, y un rango que termina hace 2 días o más deja el período terminado solo si su último día es el último del período resultante; si quedan días marcados después, solo se marcan. Si termina hoy o ayer, Aura pregunta.
- Todas estas acciones tienen **"Deshacer"** durante 7 segundos.
- **Respaldo y restauración** de tus datos en un archivo JSON:
  - **Crear respaldo** guarda el archivo en el teléfono ("Guardar en el teléfono") o lo comparte con la hoja de compartir del sistema, después de avisar que contiene datos de salud.
  - **Restaurar un respaldo** revisa el archivo antes de tocar nada y pide confirmación con la fecha del respaldo y los días que se reemplazan. Si el respaldo trae menos días que los actuales, lo avisa.
  - **Deshacer** en el mensaje de éxito vuelve a los datos que tenías antes de importar. El mensaje no se cierra solo: se cierra con una ×.
- **Respaldo protegido con contraseña (opcional):**
  - Al crear un respaldo, Aura ofrece protegerlo con una contraseña de al menos 10 caracteres, con un indicador de fortaleza orientativo ("Débil", "Aceptable" o "Fuerte"). El archivo se cifra en el teléfono antes de guardarlo o compartirlo, con un formato nuevo (versión 2 del formato del archivo), y se llama `aura_respaldo_protegido_<fecha>.json`. Antes de avisar que está listo, Aura comprueba que se puede abrir con esa contraseña.
  - **Aura no guarda la contraseña y no puede recuperarla: si la olvidas, ese respaldo no se puede abrir.**
  - Se puede seguir sin contraseña, después de una advertencia: ese archivo queda sin cifrar, como antes, y cualquiera que lo abra puede leerlo.
  - Al restaurar un respaldo protegido, Aura pide la contraseña. Si no es correcta o el archivo está dañado, lo dice sin cambiar nada y permite volver a intentarlo sin elegir el archivo otra vez.
  - La contraseña protege solo el archivo del respaldo: los datos dentro de la app y la copia que Aura guarda antes de importar no se cifran.
- **"Política de privacidad"** al pie de Ajustes, junto a la versión: abre la política en el navegador del teléfono. Aura no se conecta a Internet: la página la abre el navegador. Si no se puede abrir, Aura muestra la dirección para abrirla desde un navegador.
- Nueva sección **"Tus datos"** en Ajustes, con las dos opciones de respaldo antes de "Borrar todos los datos".
- La confirmación de importar cuenta los **días con registro (M de período)**: los días marcados como "no hubo sangrado" cuentan como registro, pero no como período.
- **"Tus ciclos"** en Estadísticas: cuántos ciclos se consideran, la duración típica del ciclo, el más corto y el más largo, la regularidad ("Regular", "Algo variable" o "Muy variable") y la duración típica del período, indicando si sale de tus períodos o de tu ajuste. Avisa cuántos ciclos no se cuentan por durar menos de 15 o más de 60 días. La duración típica del ciclo es el mismo número que usa la predicción.
- **"Mostrar ovulación y ventana fértil"** en Ajustes → "Tu ciclo", activado por defecto. Si lo apagas, Inicio y el Calendario no las muestran y no se envía el aviso de la ventana fértil; ese aviso conserva su valor y vuelve cuando enciendes el interruptor.
- **Ovulación y ventana fértil en el Calendario:** una barra bajo el número en los días de la ventana, y la barra más un punto en el de la ovulación. La leyenda suma "Ventana fértil estimada" y "Ovulación estimada", con el aviso "Estimación; no es un método anticonceptivo.". Siguen las mismas condiciones que Inicio (confianza, período atrasado e interruptor), salvo que Inicio además no las muestra mientras la fase mostrada es la menstrual; y no se dibujan sobre un día seleccionado, registrado o estimado.
- **Copia de seguridad al actualizar:** antes de convertir tus datos al formato nuevo, Aura guarda una copia dentro del teléfono. Si no puede guardarla, no convierte nada y muestra "No se pudo actualizar Aura" con el botón "Reintentar"; si falta espacio, lo dice. La copia se borra cuando guardas un respaldo en el teléfono, al abrir la app si tiene más de 30 días, o con "Borrar todos los datos".

### Cambiado

- Se quita el botón "Enviar notificación de prueba" de Ajustes. Los recordatorios no cambian.
- **"Síntomas más frecuentes"** en Estadísticas pasa a barras horizontales: el nombre a la izquierda, la barra y el número de días a la derecha, sin etiquetas que se pisen. Muestra solo los síntomas registrados, de mayor a menor (a igual cantidad, por orden alfabético), y el lector de pantalla lee el nombre y la cantidad de cada uno.
- La leyenda del Calendario muestra "Estimado sin confirmar" solo cuando hay días estimados, igual que la ventana fértil y la ovulación.
- La pantalla de registro se titula "Registrar día", como el botón de Inicio que la abre (antes decía "Registrar síntomas").
- La pregunta de Inicio "¿Sigue tu período hoy?" cambia "Sí" y "No" por "Sigue", "Terminó hoy" y "Ya terminó antes", e indica el día del período y la duración estimada.
- En el Calendario, el botón "Seleccionar varios días" pasa a llamarse "Elegir varios días" y está siempre visible junto a "Me llegó hoy". Hoy se distingue con un borde en vez de un relleno, para no confundirlo con un día registrado.
- Marcar un día o un rango en el Calendario ahora tiene "Deshacer".
- Los avisos se cierran solos: los simples a los 5 segundos (antes 4) y los que tienen "Deshacer" (Inicio, Calendario y "Me llegó hoy") a los 7. El de éxito de la importación sigue sin cerrarse solo y se cierra con una ×; el lector de pantalla la anuncia como "Cerrar".
- Un mensaje nuevo reemplaza al anterior en vez de esperar en cola.
- El Calendario y Ajustes se actualizan solos cuando los datos cambian en otra pestaña (por ejemplo, al importar o borrar todo).
- La versión que muestra Ajustes sale de una constante única, comprobada con un test contra `pubspec.yaml`.
- "Borrar todos los datos" también borra la copia guardada antes de la última importación, la copia guardada antes de actualizar y los archivos temporales del respaldo.
- La duración del período que se usa para estimar la fase menstrual solo cuenta períodos terminados: registrar solo el primer día ya no la acorta. Si no hay ningún período terminado, se usa la duración habitual de Ajustes (5 días si no la cambias).
- Al actualizar, los períodos que ya tenías se marcan como terminados solo cuando se puede deducir con seguridad: dos o más días marcados, sin huecos de más de un día y, si es el más reciente, terminado hace más de 7 días. Los demás quedan abiertos. Ningún día ni síntoma cambia.
- Con confianza baja, Inicio ya no muestra la ovulación, la ventana fértil ni la fase ovulatoria: muestra el próximo período con su rango ("(valor por defecto)" si hay menos de 2 ciclos) y una línea que explica por qué no hay ventana.
- Con el período atrasado, Inicio no muestra ninguna fase, ni la ovulación ni la ventana fértil, y el Calendario no las marca.
- La tarjeta de Inicio dice "Estimación; no es un método anticonceptivo." justo debajo de la ventana fértil, y la notificación de la ventana fértil con detalles termina en "No es un método anticonceptivo.". Sin detalles, los avisos dicen "Abre la app para ver el detalle." en vez de "Abrí la app…".
- Con datos de hace más de 60 días, Inicio dice "Tu último período empezó el …" en vez de "Tu último registro fue el …".
- Los números de los días futuros del Calendario se ven en un gris más oscuro, más fácil de leer.
- Los datos pasan a un formato nuevo (v5) que guarda el interruptor de la ovulación y la ventana fértil; no cambia ningún día ni síntoma. Los respaldos nuevos lo incluyen, y los anteriores se restauran con el interruptor activado. Una versión anterior de Aura rechaza un respaldo nuevo sin tocar tus datos, y no puede abrir los datos ya actualizados: hay que seguir con esta versión o una más nueva.
- Los respaldos nuevos usan un formato que incluye el fin de cada período. Los respaldos anteriores se siguen pudiendo restaurar; una versión anterior de Aura rechaza un respaldo nuevo sin tocar tus datos.
- Los chips de síntomas tienen un área táctil de 48 dp sin cambiar su aspecto, y su ícono crece con el tamaño de texto del sistema.
- Los interruptores de Ajustes tienen el mismo estilo que el de "Registrar día". "Borrar todos los datos" pasa a ser un botón con borde y texto rojos, más discreto; su confirmación no cambia.
- Más contraste, manteniendo los colores pastel: los textos de "Confianza", "Período atrasado", la versión y los textos secundarios son más oscuros, y los bordes e íconos usan un rosa más profundo (hoy, días estimados, − y +, síntoma marcado). El período registrado del Calendario, el rango elegido y las barras de síntomas tienen un borde fino, y la pestaña seleccionada de la barra inferior, un borde azul.

### Corregido

- Inicio se contradecía con un período en curso, por ejemplo al volver a marcar sangrado pocos días después de cerrarlo: mostraba "Fase folicular" junto a "Día 9 de tu período" y la ventana fértil. Ahora el período en curso se muestra como fase menstrual; mientras la fase mostrada es la menstrual no se muestran la ovulación ni la ventana fértil; y si el período ya superó su duración estimada, la tarjeta lo dice en vez de mostrar una duración menor que el día actual.
- El selector de fecha y otros textos del sistema ("Back", "Tab 1 of 4") aparecían en inglés: ahora están en español.
- El lector de pantalla no decía si un síntoma estaba marcado, no leía el gráfico de ánimo y en el Calendario no distinguía el período registrado ni el día de hoy. Ahora anuncia el estado de cada síntoma, cada ánimo con su porcentaje, "período registrado" y "hoy", y las flechas "Mes anterior" y "Mes siguiente"; el título del mes ya no se anuncia como un botón.
- "Registrar día" no mostraba marcados los síntomas ya guardados al abrir un día registrado: ahora se ven marcados. Además, si en ese día tocabas otro síntoma, al guardar se borraban los que ya estaban guardados; eso ya no pasa.

## 1.0.1

### Corregido

- Registrar solo síntomas ya no marca el día como de sangrado: el interruptor "Día de sangrado" ahora empieza apagado en un día sin registro, así que solo cuenta como período si lo enciendes.
- El flujo ya no se guarda como "Ligero" si no lo eliges: queda "Sin especificar" y no cambia el promedio de flujo de Estadísticas.
- El estado de ánimo ya no se guarda como "Normal" si no lo eliges: queda "Sin registrar" y no cuenta en el gráfico de ánimo.
- Ya no se pueden registrar días futuros desde el formulario.
- Los datos que ya tenías guardados no se modifican.
