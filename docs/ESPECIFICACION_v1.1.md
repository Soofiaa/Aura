# Aura v1.1 — Especificación funcional

> Documento de requisitos para la versión 1.1 (y el alcance previsto de la 1.2).
> Autora: Sofia Menzel · Estado: borrador para aprobación · Base: Aura v1.0 (`main`, schema drift v3)
> Mockups de referencia: lienzo "Aura v1.1 — Mockups" (pantallas numeradas 1 a 6 en este documento).

## 1. Contexto y objetivo

Aura v1.0 registra el ciclo menstrual, predice el próximo período y funciona 100 % en el teléfono, sin cuenta ni servidor.
El uso real mostró cuatro fricciones o carencias:

| # | Observación de uso | Tipo |
|---|---|---|
| O1 | Marcar el sangrado día por día es molesto | Fricción diaria |
| O2 | La app no sabe cuánto dura habitualmente el período de la usuaria | Dato faltante |
| O3 | Las estadísticas son pobres y no siguen la paleta de la app | Calidad percibida |
| O4 | Los datos viven solo en el teléfono: perderlo o desinstalar borra todo el historial | Riesgo de pérdida de datos |
| O5 | No hay forma de llevar historial de anticonceptivos | Funcionalidad nueva (v1.2) |

**Objetivo de la v1.1:** que registrar un período tome 2 toques en vez de uno por día, que las estadísticas respondan
"¿qué tan regular soy?", y que la usuaria pueda respaldar su información sin salir del modelo 100 % local.

## 2. Estado actual verificado en el código

Hechos comprobados leyendo `main` (no supuestos). Condicionan el diseño.

1. El calendario **ya soporta selección de rango** ("Seleccionar varios días" → `markPeriodDays`). El problema de O1 es en parte de **descubribilidad**, no de capacidad.
2. Inicio **ya pregunta "¿Sigue tu período hoy?"** (Sí/No) solo durante la fase menstrual y mientras hoy no tenga respuesta (`setPeriodDayExplicitly`).
3. Un ciclo se deriva de los días con `is_period_day = true`; un día nuevo inicia ciclo si el hueco con el anterior supera `maxGapWithinPeriod = 7` (`deriveCycles`).
4. `CycleSummary.periodConfirmedEnded` es `true` solo si existe un día **explícitamente sin sangrado** (`period_day_explicit = true`, `is_period_day = false`) dentro de los 7 días posteriores al último día de sangrado. Marcar un rango en el calendario **no** activa este indicador.
5. `predictCycle` calcula `averagePeriodLengthDays` con el promedio ponderado de `periodLengthDays` de los ciclos completos **válidos (15–60 días)** de la ventana (máx. 6). **No filtra por `periodConfirmedEnded`.**
6. Estadísticas (`stats_screen.dart`): flujo promedio como texto en `Colors.pinkAccent`, barras de síntomas con un solo color (`0xFFFAD4D8` escrito a mano, igual a `AppColors.secondary`) y torta de ánimo con `Colors.primaries` (`Colors.pinkAccent` y `Colors.primaries` están fuera de la paleta `AppColors`). No muestra duración ni regularidad de ciclos, aunque `getDerivedCycles()` ya entrega esos datos.

### Riesgo detectado (hallazgo 5) — confirmado por ejecución

Si se marca solo el primer día de un período (hoy: marcar un solo día; en la v1.1: "Me llegó hoy" sin cerrarlo después), ese período entra al promedio con
`periodLengthDays = 1`, y el promedio de duración baja de forma silenciosa. Hoy `averagePeriodLengthDays` no se muestra en ninguna
pantalla: solo se usa para calcular `menstrualEndDay` (`cycle_predictor.dart`, líneas 375-377), por lo que puede acortar la fase
menstrual y adelantar el momento en que deja de aparecer la pregunta Sí/No. El error se vuelve visible para la usuaria cuando HU-05
muestre la duración promedio del período; por eso debe corregirse antes o junto con HU-05. Hoy el riesgo está acotado por la pregunta diaria
Sí/No; con un registro de 2 toques deja de estarlo. **La v1.1 debe resolverlo (ver HU-03 y decisión D-1).**

**Verificación** (revisión independiente con un script temporal sobre `main`, sin modificar el repositorio):

- Dos ciclos completos, uno con solo el primer día marcado (`periodLengthDays = 1`) y otro de 5 días: el promedio de duración del período es **3,67 en vez de 5**.
- Con el mismo caso pero con el fin confirmado (`periodConfirmedEnded = true`) el resultado es **idéntico**: `periodConfirmedEnded` no interviene en el promedio. Solo se usa en el cálculo de la fase menstrual del ciclo más reciente (`cycle_predictor.dart`, líneas 373-377).
- **Consecuencia:** el arreglo no se resuelve solo con marcar los períodos como cerrados; **el predictor debe filtrar** los períodos abiertos al calcular la duración promedio.
- **Caso aparte:** con menos ciclos completos que `minCompleteCyclesForMedium`, el predictor usa directamente la duración del período más reciente (`cycle_predictor.dart`, línea 330) sin promedio. Si ese período está abierto, la duración usada también es la de un solo día. Hay que cubrir este caso en los tests de HU-03.

## 3. Principios de diseño

1. **Un dato estimado nunca se guarda como dato real.** Los días estimados se muestran, pero no se escriben en `daily_logs`.
   Así el predictor no aprende de su propia suposición.
2. **Local primero.** Ninguna función de la v1.1 requiere el permiso `INTERNET`.
3. **La usuaria corrige sin fricción.** Toda acción de registro tiene "Deshacer".
4. **La app no hace afirmaciones médicas.** Mantener el aviso "Esta es una estimación, no un método anticonceptivo".

## 4. Alcance por versión

| Versión | Contenido |
|---|---|
| **1.1** | HU-01 a HU-06 + tarea T-01 (ícono) |
| **1.2** | HU-07 (historial de anticonceptivos) |
| Fuera de alcance | Recordatorio de toma de pastilla, cuenta o sincronización en la nube, publicidad, pagos, exportar a PDF clínico |

---

## 5. Historias de usuario

### HU-01 · Configurar mi duración habitual del período
**Como** usuaria **quiero** indicar cuántos días suele durar mi período **para** que la app estime los días y no tenga que marcarlos uno a uno.
**Mockup:** 5 (Ajustes) y 3.

**Criterios de aceptación**
1. **Dado** que abro Ajustes → "Tu ciclo", **cuando** elijo una duración **entonces** se guarda y se usa en las estimaciones siguientes.
2. El valor admitido está entre 1 y 15 días; por defecto 5.
3. Cambiarlo **no modifica** ningún registro ya guardado (solo afecta estimaciones futuras).
4. "Duración habitual del ciclo" es opcional y solo se usa en la primera predicción, antes de tener ciclos completos suficientes.
5. Tras "Borrar todos los datos" el valor vuelve al predeterminado.

**Datos:** nueva columna `typical_period_length` (int, default 5) en `app_settings`; **schema v4** con migración y test de migración v3→v4.

---

### HU-02 · Registrar el inicio de mi período con un toque
**Como** usuaria **quiero** tocar "Me llegó hoy" **para** registrar el inicio sin marcar cada día.
**Mockup:** 2 (botón) y 3 (hoja inferior).

**Criterios de aceptación**
1. **Dado** que toco "Me llegó hoy", **entonces** veo una hoja con fecha (Hoy / Ayer / Otro día) y la duración estimada.
2. **Cuando** confirmo "Marcar mi período", **entonces** se guarda **solo el primer día** como `is_period_day = true`.
3. Los días siguientes hasta la duración habitual se muestran como **estimados** (borde punteado) y **no se guardan**.
4. No puedo elegir una fecha futura.
5. Si la fecha elegida ya está marcada, la app lo informa y no duplica el registro.
6. Aparece "Deshacer" tras confirmar.
7. Cambiar la duración en la hoja afecta solo la vista previa de ese registro, no el ajuste global.

---

### HU-03 · Cerrar mi período cuando termina
**Como** usuaria **quiero** indicar cuándo terminó mi sangrado **para** que quede registrado con su duración real.
**Mockup:** 1 (botón "Terminó hoy") y 2 ("Confirmar días").

**Criterios de aceptación**
1. **Dado** que estoy en fase menstrual, **entonces** Inicio muestra "Sigue" y "Terminó hoy" con el día actual y la duración habitual.
2. **Cuando** toco "Terminó hoy", **entonces** se marcan como sangrado todos los días desde el inicio hasta hoy, y el período queda **cerrado**.
3. Puedo elegir otro día de término distinto de hoy (no futuro, no anterior al inicio).
4. "Sigue" mantiene el comportamiento actual (marca hoy y vuelve a preguntar mañana).
5. Un período **cerrado** entra al cálculo de duración promedio; un período **abierto** (solo el primer día, sin cerrar) **no** entra. Esto exige **modificar `predictCycle`**, que hoy no filtra, e incluye el caso de pocos ciclos completos (línea 330). Test de regresión obligatorio: dos ciclos, uno abierto de 1 día y otro de 5 días, debe dar duración promedio 5 y no 3,67.
6. Todo se puede deshacer.

**Datos:** hay que representar "período cerrado" de forma que también lo estén los rangos marcados en el calendario (ver D-1).

---

### HU-04 · Marcar el período desde el calendario sin buscar la función
**Como** usuaria **quiero** ver "Me llegó hoy" y "Elegir varios días" siempre visibles **para** no tener que descubrir la selección de rango.
**Mockup:** 2.

**Criterios de aceptación**
1. El calendario muestra los dos botones sin necesidad de abrir menús.
2. La leyenda distingue: período registrado, **estimado sin confirmar**, ventana fértil, ovulación.
3. Los días estimados no se pueden confundir con los registrados (borde punteado vs. relleno).
4. "Confirmar días" equivale a HU-03 usando como día de término el último día estimado: los estimados pasan a registrados y el período queda cerrado, tras una confirmación explícita.
5. La selección de rango existente conserva su confirmación para rangos largos (`longRangeConfirmationThreshold`).
6. Los controles táctiles miden al menos 44 dp.

---

### HU-05 · Entender mis ciclos en Estadísticas
**Como** usuaria **quiero** ver qué tan regulares son mis ciclos **para** saber si mi predicción es confiable.
**Mockup:** 4.

**Criterios de aceptación**
1. Resumen: ciclo promedio (con ± de dispersión), duración promedio del período y flujo promedio.
2. Gráfico de **duración de los últimos 6 ciclos completos** con línea de promedio, calculado con `getDerivedCycles()`.
3. Con menos de 3 ciclos completos se muestra un mensaje explicativo en vez de un promedio engañoso.
4. Síntomas y ánimo usan la paleta de `AppColors`, y **no dependen solo del color**: cada elemento lleva etiqueta y valor.
5. La duración promedio del período considera solo períodos cerrados (HU-03).
6. Con la base de datos vacía se mantiene el estado vacío actual.

**Reglas de negocio:** "ciclo válido" sigue siendo el de la v1.0 (15 a 60 días). La dispersión se calcula con la misma desviación estándar ponderada del predictor, para que Estadísticas y predicción no se contradigan.

---

### HU-06 · Respaldar y restaurar mis datos
**Como** usuaria **quiero** exportar e importar mis datos **para** no perder mi historial si cambio o pierdo el teléfono.
**Mockup:** 5 (Ajustes → "Copia de seguridad").

**Criterios de aceptación**
1. **Exportar:** genera un archivo versionado (formato propio, con `schemaVersion`, fecha y app) con todos los datos: registros diarios, síntomas y ajustes.
2. El archivo se comparte mediante la hoja de compartir del sistema; la app **no** requiere `INTERNET`.
3. **Importar:** valida el archivo **antes** de tocar los datos; si es inválido o de una versión no soportada, no modifica nada y explica por qué.
4. Importar **reemplaza** los datos actuales tras una confirmación que dice cuántos registros se sobrescriben.
5. La importación es atómica (todo o nada, en una transacción).
6. Un respaldo de una versión de schema anterior se puede importar; uno de una versión posterior se rechaza con un mensaje claro.
7. Se advierte que el archivo contiene datos de salud y se ofrece protegerlo con contraseña (ver D-3).
8. Tras importar, Inicio, Calendario y Estadísticas reflejan los datos sin reiniciar la app, y las notificaciones se reprograman.

---

### HU-07 · Llevar el historial de anticonceptivos (v1.2)
**Como** usuaria **quiero** registrar qué método uso y desde cuándo **para** mantener mi historial.
**Mockup:** 6.

**Criterios de aceptación**
1. Puedo agregar un método con **tipo**, **nombre libre** (opcional), **fecha de inicio**, **fecha de término** (opcional) y **nota**.
2. La pantalla aclara que es solo un historial: sin recordatorios de toma y sin medir eficacia.
3. Un método con inicio y sin término se muestra "En uso"; solo puede haber uno hormonal en uso a la vez.
4. Los ciclos cuyo inicio cae dentro de un período de método hormonal combinado se marcan como "con anticonceptivo hormonal" y **no entran** a la ventana del predictor (sangrado de privación no es ciclo natural).
5. Si el ciclo más reciente es hormonal, Inicio explica que la predicción natural no aplica, en vez de mostrar fechas.
6. Editar o eliminar un método recalcula las marcas de los ciclos afectados.

**Datos:** nueva tabla `contraceptive_periods`; **schema v5** con migración y test. Requiere actualizar la política de privacidad y la declaración de datos si se publica en Google Play.

---

### T-01 · Ícono con fondo claro (técnica)
Cambiar el fondo del ícono adaptativo a `#F8FAFB` (color de fondo de la app y del splash), mantener la flor de cuatro pétalos, regenerar con `flutter_launcher_icons`
y comprobar el resultado en un launcher claro y uno oscuro.

---

## 6. Requisitos no funcionales

| ID | Requisito |
|---|---|
| RNF-1 | **Privacidad:** el APK de release no declara el permiso `INTERNET` (verificar con `aapt dump permissions`). |
| RNF-2 | **Datos:** cada cambio de schema lleva migración y **test de migración**; ningún dato existente se pierde al actualizar. |
| RNF-3 | **Calidad:** `flutter analyze` sin advertencias y toda la batería de tests en verde antes de cada merge. |
| RNF-4 | **Pruebas:** cada HU agrega tests en la capa donde vive la regla (dominio puro primero, luego repositorio, luego widget). |
| RNF-5 | **Accesibilidad:** objetivos táctiles ≥ 44 dp; texto con contraste suficiente; la información no depende solo del color. |
| RNF-6 | **Release:** los cambios de recursos (íconos, `keep.xml`) se comprueban en un build de release instalado, no solo en debug. |

## 7. Decisiones abiertas

Marcadas para resolver en la **Etapa A** (propuesta de Claude Code) antes de implementar.

| ID | Pregunta | Recomendación |
|---|---|---|
| **D-1** | ¿Cómo se representa un período "cerrado"? Hoy `periodConfirmedEnded` exige un día explícito sin sangrado posterior, y el rango del calendario no lo genera. | Evaluar una marca de cierre dedicada (columna o fila de cierre) frente a reutilizar el día explícito. Debe cubrir **Terminó**, **rango del calendario** y **datos de la v1.0**. |
| **D-2** | ¿Qué pasa con los períodos de la v1.0 que no tienen cierre explícito? | No descartarlos en bloque: tratar como cerrados los que tienen más de un día marcado (señal de que se registró un rango o varios días reales), y como abiertos los de un solo día. Documentar la regla y probarla con datos reales de la v1.0. |
| **D-3** | ¿El respaldo va cifrado? Son datos de salud en un archivo que puede quedar en la nube. | Contraseña opcional pero recomendada, con el mismo enfoque que ya usa PetPal. Decidir si entra en la 1.1 o en la 1.2. |
| **D-4** | ¿Qué pasa si la usuaria nunca toca "Terminó"? | El período queda abierto y fuera del promedio de duración, y el ciclo sigue contando para la regularidad (se deriva de los inicios). Evaluar un aviso suave tras la duración habitual. |

## 8. Definición de hecho (por historia)

- Criterios de aceptación verificados con tests automáticos o, si son visuales, con una prueba manual descrita en el PR.
- Migración probada si hay cambio de schema.
- `flutter analyze` y `flutter test` en verde.
- Probado en un **build de release firmado** instalado en un teléfono.
- README, CHANGELOG y política de privacidad actualizados si cambia lo que la app guarda.
- Una rama por historia, merge a `main` solo con `--ff-only`, y tag de versión al terminar el conjunto.

## 9. Orden de implementación sugerido

1. **D-1 y D-2** (modelo de "período cerrado") — es la base de todo lo demás.
2. HU-01 → HU-02 → HU-03 → HU-04 (el flujo de registro, de adentro hacia afuera).
3. HU-05 (estadísticas, que consume el modelo ya corregido).
4. HU-06 (respaldo).
5. T-01 (ícono) en cualquier momento, en su propia rama.
6. Release v1.1.0.
7. HU-07 como v1.2.0.
