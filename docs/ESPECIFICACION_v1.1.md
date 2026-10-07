# Aura v1.1 — Especificación funcional

> Documento de requisitos para la versión 1.1 (y el alcance previsto de la 1.2).
> Autora: Sofia Menzel · Estado: borrador para aprobación · Base: Aura v1.0 (`main`, schema drift v3)
> Avance: implementado hasta schema v4.
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
4. `CycleSummary.periodConfirmedEnded` es `true` solo si existe un día **explícitamente sin sangrado** (`period_day_explicit = true`, `is_period_day = false`) dentro de los 7 días posteriores al último día de sangrado. Marcar un rango en el calendario **no** activa este indicador. **En la v4** un período también queda cerrado si su último día tiene `period_end` (ver D-1 en la sección 10).
5. `predictCycle` calcula `averagePeriodLengthDays` con el promedio ponderado de `periodLengthDays` de los ciclos completos **válidos (15–60 días)** de la ventana (máx. 6). **No filtra por `periodConfirmedEnded`.** **Resuelto en la v4:** ver P-1 en la sección 10.
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
- **Resuelto en la v4** (P-1): el predictor solo promedia períodos cerrados y el caso especial de la línea 330 ya no existe. El test de
  regresión (5 y no 3,67) está en `test/domain/cycle_predictor_test.dart`.

### Hallazgo B-1 — el formulario "Registrar síntomas" marca sangrado por defecto

En un día sin registro, el formulario abre con el interruptor "Día de sangrado" **encendido** (`add_cycle_screen.dart`, línea 22,
y línea 50 al cambiar a una fecha sin registro) y con flujo "Ligero" (línea 23). Al guardar, `upsertDay` recibe
`isPeriodDaySwitch: true` y `flow` (líneas 65-68) y escribe `is_period_day = 1` (`cycle_repository.dart`, líneas 67-70).

**Verificación** (test de widget temporal sobre `main`, sin modificar el repositorio): con un período real de 5 días hace 20 días,
registrar solo "Dolor de cabeza" hoy (abrir "Registrar día" → tocar el síntoma → "Guardar registro", **3 toques**) deja el día con
`is_period_day = 1` y `flow = ligero`, y `deriveCycles` crea un **período nuevo de 1 día** que cierra un ciclo falso de 20 días.
Para registrar un síntoma sin sangrado hacen falta **4 toques**, y uno de ellos (apagar el interruptor) depende de que la usuaria
note que viene encendido.

**Consecuencia:** un registro de síntomas fuera del período puede alterar la duración de los ciclos, la predicción, las
notificaciones y el flujo promedio. Se corrige antes que todo lo demás (ver sección 9, paso 0).

### Hallazgo B-2 — el formulario guarda flujo "Ligero" sin que se elija

El flujo del formulario arranca en "Ligero" en un día sin registro (`add_cycle_screen.dart`, líneas 23 y 51, antes del parche
v1.0.1), y un día de sangrado sin flujo guardado se abre con "Ligero" (línea 45, `existing.flow ?? FlowIntensity.ligero`). Con el
interruptor encendido, ese valor se guarda aunque la usuaria nunca lo elija. A diferencia de B-1, afecta también a días de
sangrado reales.

**Verificación** (test de widget temporal sobre `main`): agregar un síntoma desde el formulario a un día marcado en el calendario
(sin flujo) le guarda `flow = ligero`; con un historial de 3 días "Abundante", registrar solo un síntoma hoy baja
`getAverageFlow` de 3,00 a 2,50.

**Consecuencia:** el "Promedio de flujo" de Estadísticas promedia valores que nadie eligió.

### Hallazgo B-3 — el formulario guarda ánimo "Normal" sin que se elija

El estado de ánimo arranca en "Normal" (`add_cycle_screen.dart`, líneas 24, 46 y 52, antes del parche v1.0.1) y se guarda en todo
registro del formulario, incluso con el interruptor de sangrado apagado. La columna `mood` ya admite `null`, así que corregirlo no
requiere migración.

**Consecuencia:** el gráfico de estado de ánimo de Estadísticas suma un "Normal" por cada registro en que no se eligió ánimo.

### Hallazgo U-1 — la selección de rango del calendario descarta un rango sin que se note

Es un problema de usabilidad, no un defecto de código. En "Seleccionar varios días", el panel ya muestra el rango y el conteo desde
el primer toque (`calendar_screen.dart`, línea 330), pero el único texto de ayuda es "Toca el primer y el último día del rango."
(línea 320). Quien toca día por día no nota que, con el rango ya completo, el tercer toque empieza un rango nuevo y descarta el
anterior: es la regla de `table_calendar` 3.1.3 (`table_calendar.dart`, líneas 364-374), que olvida el inicio al cerrar un rango.

**Evidencia** (grabación de pantalla de Sofia, caso real del 10, 11 y 12 de julio de 2026):

1. Toca el 10: el panel dice "10 julio 2026 - 10 julio 2026 (1 días)".
2. Toca el 11: "10 julio 2026 - 11 julio 2026 (2 días)", con la franja azul del rango.
3. Toca el 12: el rango se descarta y el panel dice "12 julio 2026 - 12 julio 2026 (1 días)".
4. "Marcar período" deja marcado **solo el 12**.

Además, dos textos usan "días" sin plural: el panel (línea 330, "1 días") y el aviso tras marcar el rango (línea 150, "1 días
registrados como menstruación"). El diálogo de rango largo (línea 110) nunca puede salir con 1 día, porque solo aparece con más
de 10.

**Decisión:** se corrige dentro de HU-04 en la v1.1, con las opciones A y B (ver HU-04). No entra en la v1.0.1.

### Hallazgo S-1 — los avisos con "Deshacer" no se cerraban solos

**Síntoma:** en la rama de HU-06, los SnackBar con acción "Deshacer" ("Registrado: hoy no hubo sangrado." en Inicio y "Marca
quitada" en el Calendario) quedaban en pantalla hasta que la usuaria los cerraba.

**Causa:** desde Flutter 3.29, `SnackBar.persist` es `null` por defecto y, si hay `action`, se toma como `true`
(`snack_bar.dart`: `persist = persist ?? action != null`). Al vencer la duración, `ScaffoldMessenger` no oculta un SnackBar
persistente (`scaffold.dart`: `if (snackBar.persist) return;`). Comprobado en el SDK de Flutter 3.44.8.

**Corrección** (commit `00cd5dc`): los avisos con "Deshacer" transitorio llevan `persist: false` explícito y `duration` de 8
segundos (`undoSnackBarDuration` en `lib/utils/app_snackbar.dart`). El único persistente a propósito es el éxito de la
importación. Tests de widget comprueban que siguen visibles a los 7 s y desaparecen a los 10 s; verificado también en el
teléfono.

**Relacionado** (commit `9960dff`): `ScaffoldMessenger` encola los SnackBar, así que el éxito persistente de la importación
bloqueaba todos los mensajes siguientes. Toda la app muestra los SnackBar con `showAppSnackBar`, que descarta los anteriores
antes de mostrar uno nuevo. No se limpian al cambiar de pestaña, para no borrar el "Deshacer" de la importación cuando la
usuaria va al Calendario a revisar los días importados.

## 3. Principios de diseño

1. **Un dato estimado nunca se guarda como dato real.** Los días estimados se muestran, pero no se escriben en `daily_logs`.
   Así el predictor no aprende de su propia suposición.
2. **Local primero.** Ninguna función de la v1.1 requiere el permiso `INTERNET`.
3. **La usuaria corrige sin fricción.** Toda acción de registro tiene "Deshacer".
4. **La app no hace afirmaciones médicas.** Mantener el aviso "Esta es una estimación, no un método anticonceptivo".

## 4. Alcance por versión

| Versión | Contenido |
|---|---|
| **1.0.1** | Parche del formulario "Registrar síntomas": hallazgos B-1, B-2 y B-3 (sección 2) |
| **1.1** | HU-01 a HU-06 (HU-04 incluye la mejora U-1) + tareas T-01, T-02 y T-03 (íconos) |
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
4. Tras "Borrar todos los datos" el valor vuelve al predeterminado.

**Datos:** nueva columna `typical_period_length` (int, default 5) en `app_settings`; **schema v4** con migración y test de migración v3→v4.

**Estado:** implementado. En la base y en el respaldo (v4): columna `typical_period_length` con valor 5 por defecto y `CHECK` de 1
a 15, migración v3→v4 con tests, y "Borrar todos los datos" la vuelve a 5. En la interfaz: sección **"Tu ciclo"** en Ajustes, arriba
de Notificaciones, con "Duración habitual del período" y botones − / + de 48 dp (deshabilitados en 1 y 15) que guardan al instante.
La app usa **una sola duración estimada** (`estimatePeriodLength`, P-1): el promedio ponderado de los períodos terminados y, si no
hay ninguno, este ajuste. Esa misma duración usan la fase menstrual, la hoja "Me llegó hoy", la tarjeta de Inicio y los días
estimados del Calendario, así que el ajuste solo cambia las estimaciones mientras no hay períodos terminados (lo dice el texto de
ayuda de Ajustes). `privacy.html` (es/en) ya menciona la duración habitual entre los datos que maneja la app.

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
7. La hoja muestra la duración estimada solo como texto, sin botones − / + (decisión 13 de la Etapa A): "Duración estimada: N días", con "(puedes cambiarla en Ajustes)" si sale del ajuste o "(según tus últimos períodos)" si sale del promedio de tus períodos terminados. La hoja no cambia el ajuste.

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

**Estado:** implementado. La representación del período cerrado (D-1) y el criterio 5 en el predictor (P-1) llegaron en la v4.
La interfaz está en Inicio: la tarjeta "¿Sigue tu período hoy?" con "Sigue", "Terminó hoy" y el enlace "Ya terminó antes" (selector
entre el inicio del período y hoy). Aparece con un período abierto, hoy sin respuesta y la fase menstrual o el último día marcado
ayer. Al cerrar se completan los días sin registro y se respetan los "No" explícitos; si hay días marcados después del elegido, se
bloquea con un mensaje. Un período de 1 día pide confirmación. Todas las acciones tienen "Deshacer".

---

### HU-04 · Marcar el período desde el calendario sin buscar la función
**Como** usuaria **quiero** ver "Me llegó hoy" y "Elegir varios días" siempre visibles **para** no tener que descubrir la selección de rango.
**Mockup:** 2.

**Criterios de aceptación**
1. El calendario muestra los dos botones sin necesidad de abrir menús.
2. La leyenda distingue **período registrado** (relleno) y **estimado sin confirmar** (borde punteado). El calendario no muestra
   ventana fértil ni ovulación, así que la leyenda no las incluye (decisión 9B de la Etapa A); siguen en la tarjeta de Inicio.
3. Los días estimados no se pueden confundir con los registrados (borde punteado vs. relleno).
4. "Confirmar días" equivale a HU-03 usando como día de término el último día estimado: los estimados pasan a registrados y el período queda cerrado, tras una confirmación explícita.
5. La selección de rango existente conserva su confirmación para rangos largos (`longRangeConfirmationThreshold`).
6. Los controles táctiles miden al menos 48 dp.
7. Marcar un día, quitar una marca, marcar un rango, "Confirmar días" y "Terminó este día" muestran "Deshacer" (8 segundos), que
   restaura exactamente el estado previo de todos los días afectados, incluido el fin del período, en una sola transacción.

**Mejora U-1: selección de rango (decidida, opciones A + B).** Hace más visible el resumen que ya existe y evita que un rango ya
fijado se descarte sin que la usuaria lo note (ver hallazgo U-1).

- **B (tolerante):** con el rango ya completo, tocar un día **posterior** al final lo alarga; un día **anterior** al inicio mueve
  el inicio; un día **dentro** del rango acorta el final. "Cancelar selección" vuelve a cero. Se permite extender el rango entre
  meses. Se implementa en el estado propio de la pantalla (`RangeSelection`, en `lib/domain/range_selection.dart`), con el modo de
  rango de `table_calendar` desactivado y todos los toques por `onDaySelected`, **sin modificar `table_calendar`**. La
  confirmación de rango largo (más de `longRangeConfirmationThreshold` = 10 días) sigue protegiendo contra extensiones
  accidentales.
- **A (guía):** el panel indica el paso en cada estado: sin selección, "Toca el primer día"; con inicio, "Ahora toca el último
  día"; con el rango listo, el resumen en formato corto ("10 jul → 12 jul · 3 días") y la indicación de que tocar otro día cambia
  el final. Si el rango supera los 10 días, el resumen lo advierte de inmediato, no solo al pulsar "Marcar período". Corrige el
  plural: "1 día" en el panel y "1 día registrado como menstruación" en el aviso.

**Criterios de aceptación de U-1** (tests de widget):

8. Tocar 10, 11 y 12 → rango 10–12, "3 días".
9. Tocar 10 y 12 → rango 10–12, "3 días".
10. Con 10–12 listo, tocar el 8 → rango 8–12.
11. Con 10–12 listo, tocar el 11 → el final pasa a 11.
12. Un rango de un solo día muestra "1 día" en el panel y, al marcarlo, el aviso dice "1 día registrado como menstruación".
13. Marcar el rango deja exactamente esos días en la base de datos.
14. "Cancelar selección" vuelve a cero.
15. Un rango de más de 10 días, alcanzado por extensión, sigue pidiendo confirmación al marcarlo.
16. Con un rango ya completo, un tercer toque alarga, mueve o acorta el rango, y nunca lo reinicia. Como el modo de rango de
    `table_calendar` está desactivado, cada toque llega como un día por `onDaySelected` y `RangeSelection.tap` decide el rango
    nuevo; la librería nunca recibe un rango, así que no puede reiniciarlo.
17. Con 10–12 listo, tocar el 10 (el inicio) deja un rango de 1 día (10–10); tocar el 12 (el final) no cambia nada.
18. Un rango puede cruzar de mes; si supera los 10 días, el resumen del panel lo advierte en ese momento.

**Etapa A de HU-04:** ya no decide qué hacer, solo cómo: los textos exactos del panel; el SnackBar "Marca quitada · Deshacer", que
hoy no se cierra solo (revisar si es porque tiene acción y Flutter lo mantiene fijo, y qué conviene); y los casos límite
(rango que cruza de mes, tocar el mismo día dos veces, fechas futuras).

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
**Mockup:** 5 (Ajustes → "Copia de seguridad"; en la app la sección se llama **"Tus datos"**).

**Estado:**
- **HU-06a (respaldo sin cifrado): implementada, probada en la app debug (automatizada por adb) y release verificado; verificada con datos reales el 2026-10-04: se exportó desde la app real, se importó en la app debug y los recuentos del diálogo (días con registro y de período) coincidieron; después se ejecutó "Borrar todos los datos" en la app debug.** Rama `feature/hu-06-respaldo`, commits `9f8666e`,
  `9960dff`, `00cd5dc` y `0bc413c`. Cubre los criterios 1 a 6 y 8, y la advertencia de datos de salud del criterio 7.
  - Prueba manual en el teléfono (2026-10-04, build debug con datos inventados): 9 de 10 pasos OK. Falló uno: al cerrar la hoja
    de compartir sin elegir destino aparecía "Respaldo listo". Se corrigió en `0bc413c` y quedó cubierto por un test.
  - En la misma prueba se comprobó con `run-as` que `cache/file_picker` queda vacía después de importar, que los temporales se
    borran al volver a abrir la app y que "Borrar todos los datos" elimina `files/respaldos`.
  - Release firmado (SHA-256 del certificado igual al de la app instalada): `aapt dump permissions` sin `INTERNET`. Se instaló
    con `adb install -r` sobre la app real, conservando sus datos (`firstInstallTime` sin cambios).
- **Respaldo v4 (con la migración v4):** el archivo pasa a `schemaVersion` 4, con `periodEnd` en cada día y `typicalPeriodLength`
  en los ajustes. `formatVersion` sigue en 1 (el envoltorio no cambia). Un respaldo v3 se sigue aceptando y, al importarlo, se le
  aplica la regla D-2; uno v4 se importa tal cual. La app anterior (schema v3) rechaza un respaldo v4 como de una versión más nueva,
  sin tocar nada (ver HU6-7 en la sección 10).
- **HU-06b (contraseña / cifrado del respaldo): pendiente.** Completa el criterio 7 (ver decisiones HU6-2 y HU6-3 en la sección
  10). Bloquea la publicación de la v1.1.

**Criterios de aceptación**
1. **Exportar:** genera un archivo versionado (formato propio, con `schemaVersion`, fecha y app) con todos los datos: registros diarios, síntomas y ajustes.
2. El archivo se comparte mediante la hoja de compartir del sistema; la app **no** requiere `INTERNET`.
3. **Importar:** valida el archivo **antes** de tocar los datos; si es inválido o de una versión no soportada, no modifica nada y explica por qué.
4. Importar **reemplaza** los datos actuales tras una confirmación que dice cuántos registros se sobrescriben. Se cuentan
   **días con registro** y, entre paréntesis, cuántos son de período: "tiene N días con registro (M de período)" (ver
   HU6-R4 en la sección 10).
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

### T-01 · Ícono con fondo blanco (técnica)
Fondo del círculo del ícono adaptativo en blanco `#FFFFFF`, con la misma flor de cuatro pétalos.

- Se reemplazan `assets/icon/aura_icon_1024.png` y `assets/icon/aura_background_1024.png`. El foreground y el splash no cambian, y
  el splash conserva su color `#F8FAFB`.
- Se agrega `adaptive_icon_foreground_inset: 8` a la configuración de `flutter_launcher_icons` y se regenera con
  `dart run flutter_launcher_icons`.
- **Fundamento medido:** con el 16 % por defecto de `flutter_launcher_icons` 0.14.4, la flor mide 37,6 dp de ancho en un círculo
  visible de 72 dp (queda encogida). Con 0 %, las puntas de los pétalos salen de la zona segura de 66 dp (2,35 % de los píxeles).
  Con 8 % la flor mide unos 46,4 dp de ancho y cabe en un círculo de 58,3 dp, dentro de la zona segura de 66 dp.
- **Por qué 8 y no 4:** con 4 % (50,8 dp) también cabía en la zona segura, pero viéndolo instalado en el teléfono, Sofia prefirió
  la flor un poco más chica.
- Entra en la v1.1, sin subir la versión antes. Se comprueba en un build de release instalado (RNF-6).

---

### T-02 · Ícono pequeño de notificación (técnica)
Hoy `notifications.dart` (línea 62) usa `@mipmap/ic_launcher` como ícono pequeño. Su fondo es opaco y Android dibuja ese ícono
usando solo la transparencia, así que la notificación no muestra la flor.

**Confirmado** en el teléfono de Sofia (HyperOS) con el botón "Enviar notificación de prueba" de Ajustes: el ícono pequeño se ve
como un disco oscuro liso dentro del círculo del sistema, sin forma de flor. Es la misma causa: un ícono opaco usado como ícono
pequeño.

- **Solución:** un ícono `ic_stat_*` blanco sobre transparente, referenciado por nombre, con su `res/raw/keep.xml` para que
  R8 / `shrinkResources` no lo elimine en el release.
- **Criterio de aceptación:** una notificación real en el teléfono muestra la silueta de la flor y no una forma lisa (un cuadrado o
  un disco).
- **Mejora menor:** el texto de la notificación de prueba dice "Notificación de prueba (debug), programada hace 10s"
  (`notifications.dart`, línea 173) y se ve en la versión de release, porque el botón de Ajustes no está limitado a debug
  (`settings_screen.dart`, líneas 270-274). Conviene un texto pensado para quien usa la app, o esconder el botón en release.
- Debe estar antes de publicar la v1.1.

---

### T-03 · Ícono monocromo (técnica)
Íconos temáticos de Android 13 o superior. Hoy no existe `<monochrome>` en `ic_launcher.xml` ni `adaptive_icon_monochrome` en la
configuración: con los íconos temáticos activos, Aura se ve a color entre íconos teñidos.

- Requiere una silueta de la flor como asset.
- **Criterio de aceptación:** con los íconos temáticos activos, el ícono de Aura se tiñe como los demás.

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

| ID | Pregunta | Recomendación | Estado |
|---|---|---|---|
| **D-1** | ¿Cómo se representa un período "cerrado"? Hoy `periodConfirmedEnded` exige un día explícito sin sangrado posterior, y el rango del calendario no lo genera. | Evaluar una marca de cierre dedicada (columna o fila de cierre) frente a reutilizar el día explícito. Debe cubrir **Terminó**, **rango del calendario** y **datos de la v1.0**. | Resuelta: ver sección 10 |
| **D-2** | ¿Qué pasa con los períodos de la v1.0 que no tienen cierre explícito? | No descartarlos en bloque: cerrar solo los que tienen al menos 2 días marcados, un hueco interno de 1 día como máximo y que ya no pueden seguir creciendo (si son el período más reciente, que su último día sea de hace más de 7 días). Los demás, incluidos los de un solo día, quedan abiertos. Documentar la regla y probarla con datos que reproduzcan los de la v1.0. | Resuelta: ver sección 10 |
| **D-3** | ¿El respaldo va cifrado? Son datos de salud en un archivo que puede quedar en la nube. | Contraseña opcional pero recomendada, con el mismo enfoque que ya usa PetPal. Decidir si entra en la 1.1 o en la 1.2. | Resuelta: ver sección 10 (HU6-2, HU6-3) |
| **D-4** | ¿Qué pasa si la usuaria nunca toca "Terminó"? | El período queda abierto y fuera del promedio de duración, y el ciclo sigue contando para la regularidad (se deriva de los inicios). Evaluar un aviso suave tras la duración habitual. | Resuelta: ver sección 10 |
| **U-1** | ¿Cómo se evita que la selección de rango del calendario descarte un rango sin que se note? | Hacer más visible el resumen que ya existe; evaluar un aviso al empezar un rango nuevo y que un toque posterior alargue el rango. | Resuelta: ver sección 10 |
| **T-02 / T-03** | ¿El ícono de notificación y el ícono monocromo se corrigen dentro de T-01? | Separarlos en tareas propias. | Resuelta: ver sección 10 |

## 8. Definición de hecho (por historia)

- Criterios de aceptación verificados con tests automáticos o, si son visuales, con una prueba manual descrita en el PR.
- Migración probada si hay cambio de schema.
- `flutter analyze` y `flutter test` en verde.
- Probado en un **build de release firmado** instalado en un teléfono.
- README, CHANGELOG y política de privacidad actualizados si cambia lo que la app guarda.
- Una rama por historia, merge a `main` solo con `--ff-only`, y tag de versión al terminar el conjunto.

## 9. Orden de implementación sugerido

0. **Formulario (B-1, B-2, B-3), parche v1.0.1:** en un día sin registro, el interruptor de sangrado arranca apagado; el flujo
   queda "Sin especificar" y el ánimo "Sin registrar" salvo que la usuaria los elija. El selector de fecha del formulario deja de
   permitir días futuros. No cambia el esquema ni modifica los datos ya guardados. Apagar el interruptor en un día marcado sigue
   guardando un "no" explícito, sin confirmación ni "Deshacer" en este parche.
1. **T-01 (ícono con fondo blanco), adelantada:** se hace justo después de la rama de documentación de los hallazgos, porque es
   independiente del resto. Sin subir la versión (ver sección 10).
2. **HU-06 (respaldo)**, con su propia Etapa A. Va antes de la migración v4 para poder respaldar los datos reales antes de actualizar.
3. **Modelo de período cerrado** (D-1, D-2, P-1): columna `period_end`, migración v4 (incluye `typical_period_length`), cambio en el predictor y ajuste de duración habitual en el repositorio, **sin interfaz**.
   **Hecho**, junto con la copia previa a la migración y la pantalla de error al actualizar (M-1 a M-4 en la sección 10).
4. Interfaz de HU-01 a HU-04 (HU-04 incluye la mejora U-1).
5. HU-05 (estadísticas, que consume el modelo ya corregido) y los íconos T-02 (ícono de notificación, obligatorio antes de publicar la v1.1) y T-03 (ícono monocromo).
6. Release v1.1.0 y, después, HU-07 como v1.2.0.

## 10. Registro de decisiones

Decisiones tomadas tras la Etapa A del modelo de período cerrado (D-1 a R-8), tras el parche v1.0.1 (U-1 y T-01 a T-03),
tras la Etapa A de HU-06 (HU6-1 a HU6-6 y ajustes A a H) y durante la implementación de la migración v4 (M-1 a M-4 y HU6-7).
Reemplazan las recomendaciones de la sección 7 donde difieran.

| ID | Decisión | Motivo |
|---|---|---|
| **D-1** | Nueva columna `period_end` en `daily_logs`, de tipo `PeriodEndSource` (`declared` \| `inferred`), con `CHECK` en la columna: `period_end IS NULL OR is_period_day = 1`. Un período está **cerrado** si su último día de sangrado tiene `period_end`, o si se cumple la regla actual del "No" explícito (un día con `is_period_day = 0` y `period_day_explicit = 1` entre 1 y 7 días después del último día de sangrado). | Todo el estado queda en las filas de `daily_logs`: "Deshacer" y "Quitar marca" siguen funcionando con una foto de las filas afectadas, el respaldo exporta una columna más y `deriveCycles` sigue siendo pura. El origen (`declared` / `inferred`) separa las declaraciones reales de la inferencia de la migración y permite revertir esta última. Se descartaron: una tabla de cierres (dos fuentes de verdad), reutilizar `period_day_explicit` (obliga a guardar días futuros falsos) e inferir sin guardar nada (no distingue un período abierto de uno corto). El `CHECK` va en la columna, no en la tabla, para que una instalación nueva y una migrada tengan el mismo schema. **Implementada en la v4.** |
| **D-2** | Al migrar a v4, los períodos de la v1.0 se cierran con `period_end = inferred` en su último día **solo** si: no están ya cerrados por un "No", su último día no tiene ya `period_end`, tienen al menos 2 días marcados, su hueco interno más grande (días sin marcar entre dos días marcados seguidos) es de 1 día como máximo, y no son el período más reciente con su último día 7 días o menos antes de "hoy" (incluye un último día en el futuro). En cualquier otro caso quedan abiertos y no se escribe nada (ver tabla de casos más abajo). "Hoy" es la fecha del teléfono al migrar o, al importar un respaldo v3, el día de la importación. **Implementada en la v4** como `inferLegacyPeriodEnds` (`lib/domain/legacy_period_ends.dart`), que comparten la migración y la conversión de respaldos v3. | Regla conservadora: un período abierto solo queda fuera del promedio, mientras que un cierre equivocado lo distorsiona. La migración solo escribe `period_end`; no cambia ningún día de sangrado, flujo, ánimo, nota, síntoma ni negación explícita. Una sola función para los dos caminos hace que migrar la base y restaurar el mismo respaldo v3 den los mismos cierres (probado con tests). |
| **P-1** | El predictor filtra **solo la duración del período**; la duración del ciclo, el rango y la confianza no cambian. La duración promedio del período es un **promedio ponderado por posición**: se toman los períodos cerrados de la ventana (los últimos 6 ciclos completos con duración válida, de 15 a 60 días), ordenados del más antiguo al más reciente, y, si el período actual está cerrado, se agrega al final (R-3). Pesan 1, 2, 3…, igual que en la duración del ciclo, de modo que los más recientes cuentan más. Si no hay ningún período cerrado, aunque haya días registrados, se usa la duración habitual guardada (`typical_period_length`: 5 por defecto, de 1 a 15), que llega a `predictCycle` como `typicalPeriodLengthDays` en `PredictionConfig`. Sin la interfaz de HU-01, ese valor solo cambia al importar un respaldo v4 que traiga otro. Desaparece el caso especial de la línea 330. **Implementada en la v4.** | Corrige el riesgo del hallazgo 5 (3,67 en vez de 5). Pasar la duración habitual en `PredictionConfig` mantiene `predictCycle` como función pura. |
| **E-1** | Los días estimados se calculan con una función pura (período actual, duración habitual, hoy) y **no se guardan**. | Principio 1: un dato estimado nunca se guarda como dato real. |
| **R-1** | Un rango marcado en el calendario cierra el período (`declared` en su último día) solo si termina hace 2 días o más. Si termina hoy o ayer, se pregunta "¿Ya terminó tu período?". | Un rango que termina hoy o ayer puede corresponder a un período que sigue. |
| **R-2** | Se acepta que los períodos de 1 día de la v1.0 queden abiertos, y el límite de hueco interno de 1 día de D-2. | En los datos de la v1.0 no se puede distinguir un período real de 1 día de uno en que solo se marcó el inicio. |
| **R-3** | El período actual cerrado entra al promedio de duración aunque su ciclo no esté completo. **Implementada en la v4.** | Su duración ya es un dato real. |
| **R-4** | Marcar un día a continuación de un fin declarado **reabre** el período, sin borrar la marca anterior (queda en un día interior y deja de contar). | Es la opción conservadora, y si después se quita ese día el fin declarado vuelve a valer. **Nota (por diseño):** un `period_end` que quedó en un día interior es un dato obsoleto que se conserva a propósito: `deriveCycles` solo lee el `period_end` del último día de cada período, así que el interior se ignora; no se borra al marcar (Inicio, Calendario, rangos o formulario), el respaldo lo exporta tal cual y "Deshacer" lo restaura. Si el período vuelve a cerrarse en otro día, ese nuevo fin es el que cuenta. |
| **R-5** | El respaldo (HU-06) se implementa **antes** de la migración v4. | `allowBackup="false"` y la build de release impiden copiar la base del teléfono; sin exportación no hay forma de respaldar los datos reales antes de migrar. |
| **R-6** | No se agrega `typical_cycle_length`. | Decisión de producto; se quita el criterio correspondiente de HU-01 y la v4 solo agrega `typical_period_length`. |
| **R-7** | Estadísticas muestra "Según tu ajuste" cuando no hay períodos cerrados, y no muestra el origen `inferred`. | Ser transparente sobre de dónde sale el número sin exponer un detalle técnico. |
| **R-8** | El aviso suave de D-4 (cuando nunca se toca "Terminó") queda fuera de la v1.1. | Reducir el alcance; el período abierto ya queda fuera del promedio sin afectar la regularidad. |
| **M-1** | La migración 3→4 corre dentro de una transacción explícita y, antes de confirmar, comprueba que no cambió la cantidad de días ni de síntomas, que `foreign_key_check` no informa nada y que ningún `period_end` quedó en un día sin sangrado. Tolera columnas ya existentes. `drift_dev make-migrations` guarda los volcados de los schemas v3 y v4 en `drift_schemas/aura/` y, a partir de ellos, genera el andamiaje del paso a paso (`app_database.steps.dart`: `Schema4` y `migrationSteps`) y los schemas de prueba (`test/drift/aura/generated/`; el test `test/drift/aura/migration_test.dart` parte de su plantilla y está adaptado a mano); el contenido del paso 3→4 (`_from3To4`) está escrito a mano. Las migraciones v1→v3 siguen escritas a mano, antes del paso a paso. | drift no envuelve `onUpgrade` en una transacción: sin ella, un fallo a mitad de camino dejaría columnas nuevas con el `user_version` viejo y la app no volvería a abrir. Con la transacción, SQLite revierte todo, incluido `user_version`. La tolerancia cubre una base v4 abierta por una app v3, que queda con `user_version` 3 y las columnas ya puestas. |
| **M-2** | Antes de que drift abra una base con `user_version` entre 1 y 3, se guarda una copia del archivo en `respaldos/antes_de_migrar_v4.sqlite`, dentro del almacenamiento privado de la app, con `VACUUM INTO` a un archivo temporal que después se renombra. No se crea en una instalación nueva ni en una base ya v4, y no se sobrescribe si ya existe. Si no se puede escribir, la base no se abre ni se migra. Se borra: tras un "Guardar en el teléfono" exitoso (no al compartir; si el borrado falla, se ignora y queda para los otros dos casos); al abrir la app, si tiene más de 30 días según su fecha de modificación (ver M-3); y siempre con "Borrar todos los datos", que borra la carpeta `respaldos/` completa. | R-5: red de seguridad para los datos reales durante la migración. Tras guardar en el teléfono la usuaria ya tiene una copia completa y más reciente fuera de la app. Compartir no basta, porque `share_plus` puede devolver `unavailable` sin que se haya enviado nada (HU6-R5). |
| **M-3** | La revisión de los 30 días de M-2 solo ocurre si la base abrió bien. | Si una migración quedó trabada, la copia previa es la única red de seguridad: no se borra mientras la app no logre abrir los datos. |
| **M-4** | La app abre la base (y con eso hace la copia previa y la migración) antes de programar notificaciones o limpiar temporales. Si falla, muestra la pantalla "No se pudo actualizar Aura" con un botón "Reintentar", que cierra la base y crea una nueva. El texto es: "Aura no pudo abrir tus datos, pero no borró nada. Cierra la app y vuelve a abrirla. Si el problema sigue, no desinstales la app, porque se perderían tus datos, y escribe a soofiaa.menzel@gmail.com". Si la causa es falta de espacio (`SQLITE_FULL` o un error de disco lleno del sistema de archivos), en su lugar dice "Libera espacio en el teléfono e inténtalo de nuevo" y, debajo, "Tus datos están a salvo: no se borró ni se cambió nada." | Antes, un fallo al abrir la base ocurría antes de `runApp` y dejaba la app congelada en la pantalla de inicio. Desinstalar borraría los datos, por eso el texto lo desaconseja. |
| **U-1** | La selección de rango del calendario aplica las opciones **A + B** (ver HU-04): el panel guía cada paso y muestra el resumen corto, y con un rango ya completo otro toque alarga, mueve o acorta el rango en vez de descartarlo. Se implementa en el estado de la pantalla, sin modificar `table_calendar`. Entra en HU-04, en la v1.1. | Ataca la causa del caso real del 10 al 12 de julio (el tercer toque descartaba el rango sin que se notara) sin agregar pasos. Se descartaron: C, marcar día por día, porque revive la queja de fricción que HU-04 busca resolver; y D, apoyarse en "Me llegó hoy", porque no sirve para registrar un período pasado. La confirmación de rango largo sigue protegiendo contra extensiones accidentales. |
| **T-01** | Fondo del ícono adaptativo en blanco `#FFFFFF` y `adaptive_icon_foreground_inset: 8`. El foreground y el splash no cambian; el splash conserva `#F8FAFB`. | Medido sobre el foreground: con el 16 % por defecto de `flutter_launcher_icons` 0.14.4 la flor queda encogida en 37,6 dp de un círculo visible de 72 dp; con 0 % las puntas de los pétalos salen de la zona segura de 66 dp (2,35 % de los píxeles); con 8 % mide unos 46,4 dp y cabe en un círculo de 58,3 dp, dentro de la zona segura. Se eligió 8 y no 4 (50,8 dp, que también cabía) porque, viéndolo instalado en el teléfono, Sofia prefirió la flor un poco más chica. `#F8FAFB` y `#FFFFFF` casi no se distinguen, por eso el splash no cambia. |
| **T-01 (versión)** | T-01 entra en la v1.1 sin subir la versión antes. Para probarla en el teléfono se instala con `adb install -r` con el mismo `versionCode`, como instalación de prueba. | Un cambio solo de ícono no justifica una versión publicada aparte, y la misma firma con `-r` conserva los datos. |
| **T-02 / T-03** | El ícono pequeño de notificación (T-02) y el ícono monocromo (T-03) son tareas separadas de T-01. T-02 debe estar antes de publicar la v1.1. | Son problemas distintos del fondo del ícono: cada uno necesita su propio asset y su propia prueba en el teléfono, y mezclarlos agrandaría T-01. T-02 va antes de la v1.1 porque las notificaciones ya están en uso y su ícono pequeño no muestra la flor: confirmado en el teléfono de Sofia (HyperOS), donde se ve como un disco oscuro liso. T-03 solo afecta a quien usa íconos temáticos: forma parte de la v1.1 pero no bloquea su publicación; si no queda lista, pasa a la v1.2. |
| **HU6-1** | El respaldo es un **JSON propio** (`"format": "aura-backup"`, con `formatVersion`, `schemaVersion`, `appVersion` y `exportedAt`), no una copia del archivo `.sqlite`. | Se puede validar completo antes de tocar la base, no depende del formato interno de drift y un schema anterior se puede importar convirtiéndolo. |
| **HU6-2** | El cifrado entra en la v1.1 como **HU-06b**, en una rama aparte. Bloquea la publicación de la v1.1, pero no la migración v4. | Son datos de salud en un archivo que puede terminar en la nube o en un chat, pero el respaldo sin cifrar ya permite proteger los datos reales antes de migrar (R-5). |
| **HU6-3** | HU-06b usará un **envoltorio propio PBKDF2-SHA256 + AES-GCM**, no el ZIP AE-2 de PetPal. | El enfoque de PetPal usa 1000 iteraciones con SHA-1, un costo de derivación demasiado bajo para datos de salud. |
| **HU6-4** | "Crear respaldo" ofrece la **hoja de compartir** del sistema y un botón **"Guardar en el teléfono"** (el "Guardar como" del sistema). | Guardar en el propio teléfono no debería obligar a pasar por otra app. Además, `share_plus` puede devolver `unavailable` en vez de `dismissed` según el dispositivo o la versión de Android, así que no se puede garantizar que siempre se detecte el cierre de la hoja de compartir. En el teléfono de prueba (Xiaomi, HyperOS) el cierre sí se detectó (verificado en el release real, 2026-10-04). "Guardar en el teléfono" informa si se guardó o se canceló. |
| **HU6-5** | **"Deshacer"** está en el mensaje de éxito de la importación, sin un botón permanente en Ajustes. | Deshacer sirve justo después de importar; un botón permanente invitaría a restaurar una copia vieja por error. |
| **HU6-6** | Se importan los **ajustes de recordatorios**, salvo el **interruptor general** de notificaciones. | Ese interruptor depende del permiso de notificaciones del teléfono donde se importa, así que conserva su valor actual. |
| **HU6-7** | Con la migración v4, el respaldo pasa a `schemaVersion` 4: cada día lleva `periodEnd` (`null`, `"declared"` o `"inferred"`) y los ajustes llevan `typicalPeriodLength` (de 1 a 15). `formatVersion` sigue en 1. Un respaldo v3 se acepta y se convierte con la regla D-2 ("hoy" = el día de la importación); si trae una clave `periodEnd`, se ignora. La duración habitual de un respaldo v3 queda en 5. Un respaldo v4 se importa tal cual, incluida su duración habitual. La importación solo acepta datos ya convertidos al schema actual. La app v3 rechaza un respaldo v4 como de una versión más nueva, sin tocar nada. | `formatVersion` versiona el envoltorio (cambiará con el cifrado de HU-06b) y `schemaVersion` los datos. Convertir siempre antes de importar impide que algún camino importe datos v3 sin aplicar D-2. |

**Ajustes obligatorios de HU-06** (aprobados con la Etapa A):

| ID | Ajuste |
|---|---|
| **A** | Los archivos temporales de exportación se borran al abrir la app y antes de la siguiente exportación, **no** al volver de la hoja de compartir: la app de destino puede seguir leyéndolos. |
| **B** | "Borrar todos los datos" borra también la carpeta `respaldos/` completa (`antes_de_importar.json` y, desde la v4, `antes_de_migrar_v4.sqlite`) y los temporales; intenta los tres pasos aunque uno falle. |
| **C** | Si el respaldo trae **menos** días que los actuales, la confirmación lo avisa de forma destacada ("El respaldo tiene N días menos que los que tienes ahora; se perderán."). Se calcula con el total de días con registro. |
| **D** | La versión sale de una **constante única** (`lib/utils/app_version.dart`), usada en Ajustes y en el respaldo, con un test que falla si no coincide con `pubspec.yaml`. |
| **E** | La exportación es **determinista**: días ordenados por fecha, síntomas por nombre y claves siempre en el mismo orden; los mismos datos producen el mismo archivo, salvo `exportedAt`. |
| **F** | "Deshacer" no se cierra solo y no reescribe la copia previa. El texto inicial ("…quedan guardados hasta la próxima importación") se cambió en la revisión del CP2 por **"Si te equivocaste, toca Deshacer."** |
| **G** | Rango de fechas válido al importar y exportar: de `1970-01-01` a la mayor entre `2030-12-31` y la fecha de exportación + 2 días. |
| **H** | Durante la importación la interfaz queda **bloqueada** con un diálogo de progreso que no se puede cerrar (ni con "atrás"). |

**Riesgos, hallazgos y tareas de HU-06:**

| ID | Tipo | Detalle |
|---|---|---|
| **HU6-R1** | Riesgo residual | Si un día guardado queda con una fecha fuera del rango de G, el respaldo no se puede crear y la importación tampoco, porque su copia previa falla. Pasa, por ejemplo, con un día posterior a 2030 guardado con el reloj adelantado. El mensaje nombra la fecha, pero la app no permite editar ese día, así que la única salida es "Borrar todos los datos". |
| **HU6-R2** | Tarea aparte | Actualizar **AGP 8.7.3, Gradle 8.12 y Kotlin 2.1.0** antes de publicar la v1.1: Flutter 3.44.8 avisa que pronto dejará de soportarlos. |
| **HU6-R3** | Dependencias fijadas | `share_plus` queda en **12.0.2** y `file_picker` en **11.0.3**, versiones exactas. `file_picker` 12/13 (federado, `android_file_picker` 2.0.0) no compila con AGP 8.7.3: `androidx.core` 1.18 exige AGP 8.9.1 o superior y falla el lint. `share_plus` 13 exige `win32` ^6, que choca con `file_picker` 11 (`win32` ^5). Se revisan junto con HU6-R2. |
| **HU6-R4** | Aclaración | La confirmación de importar cuenta **días con registro**, no solo días de período: un día con la marca quitada o con "no hubo sangrado" sigue siendo una fila y se reemplaza igual. Por eso dice "N días con registro (M de período)". M sale de `isPeriodDay` en el respaldo y de `getPeriodDayDates()` en el teléfono. Antes decía "N días registrados" y confundía, porque el calendario solo muestra los de período. |
| **HU6-R5** | Hallazgo | `share_plus` 12.0.2 en Android devuelve `dismissed` si la hoja de compartir se cierra sin elegir destino, `success` si se elige una app y `unavailable` si la plataforma no puede saberlo. `BackupFileGateway.shareFile` devuelve `false` solo con `dismissed`, y entonces la pantalla no muestra "Respaldo listo". |

**Casos de la regla D-2** (datos de la v1.0 al migrar a v4):

| Caso | Resultado | Duración que entra al promedio |
|---|---|---|
| 1 día marcado (ciclo completo) | Abierto | No entra |
| 2 o más días seguidos (por ejemplo, 01-01 a 01-05) | Cerrado (`inferred`) | 5 |
| Rango con 1 día sin marcar (por ejemplo, días 1, 2, 4 y 5) | Cerrado (`inferred`) | 5 (el hueco cuenta, igual que hoy) |
| Rango con hueco de más de 1 día (por ejemplo, días 1 y 7) | Abierto | No entra |
| Período que ya tiene un "No" explícito | Ya cerrado; no se escribe nada | Su duración real |
| Período más reciente que terminó hace 7 días o menos | Abierto (puede seguir) | No entra |
| Período más reciente que terminó hace más de 7 días, con 2 o más días | Cerrado (`inferred`) | Su duración |
| Período más reciente de 1 solo día, de hace más de 7 días | Abierto | No entra |
| Período cuyo último día ya tiene `period_end` (por ejemplo, una base v4 abierta por la app v3) | No se reescribe | Su duración |
| Período más reciente con días de fecha futura (el formulario de la v1.0 los permitía) | Abierto (cuenta como "7 días o menos") | No entra |

**Verificación de la migración v4:** además de los tests, se comprobó en un dispositivo con datos reales, en la app de prueba
(debug), que la migración no altera días ni síntomas y que la copia previa a la migración queda intacta.
