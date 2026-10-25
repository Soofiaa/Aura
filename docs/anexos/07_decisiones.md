# 07 · Registro de decisiones

> **App:** Aura 1.2.0 (build 7) · **Revisión:** 2026-10-24
> **Fuentes:** `ESPECIFICACION_v1.1.md` (decisiones D-1, D-2, P-1, E-1, R-1…R-8, M-1…M-4, U-1, T-01…T-03, HU6-1…HU6-6, HU6b-1, RR-6), `HU-09_respaldo_drive_v1.2.md`, `DRIVE_SETUP.md`.
> Este documento es un **resumen** para leer rápido: el razonamiento completo y las alternativas descartadas están en la especificación. Cada fila indica dónde profundizar.

## Cómo leerlo

Formato resumido de registro de decisiones de arquitectura (ADR): **decisión → motivo → consecuencia**. Los identificadores (D-1, E-1…) son los de la especificación.

## 1. Modelo de datos y reglas del ciclo

| Id | Decisión | Motivo | Consecuencia / compromiso |
|---|---|---|---|
| — | **Guardar solo los días de sangrado; derivar ciclos, duraciones, predicción y fases.** | Una sola fuente de verdad: corregir un día recalcula todo de forma consistente. | Cada lectura calcula (barato a esta escala); no hay historial de predicciones pasadas. |
| — | **Fechas como texto `yyyy-MM-dd` y aritmética en UTC.** | Un día de calendario no es un instante. En Chile el cambio de hora ocurre a medianoche y a veces la medianoche local no existe. | Las comparaciones y diferencias pasan por `DayKey`; no se usan instantes locales. |
| — | **Un período nuevo empieza cuando la brecha con el sangrado anterior supera 7 días; un ciclo es válido entre 15 y 60 días.** | Evita contar manchado o registros olvidados como ciclos y descarta ciclos implausibles. | Algunas usuarias con ciclos atípicos verán menos ciclos válidos. |
| **D-1** | **Cerrar el período con una marca `period_end` en el último día de sangrado.** | Todo el estado queda en las filas de `daily_logs`: «Deshacer» funciona con una foto de esas filas, el respaldo exporta una columna más y el derivador sigue puro. | Se descartaron una tabla de cierres (dos fuentes de verdad) y reutilizar `period_day_explicit` (obligaba a guardar días futuros falsos). |
| **D-2** | **Migración conservadora de períodos antiguos: solo se cierran por inferencia los que cumplen la regla.** | No afirmar un cierre que la usuaria nunca declaró. | `period_end = inferred` marca el origen. Los respaldos v3 y v4 usan la misma regla al importarse. |
| **P-1** | **Solo los períodos cerrados entran en el promedio de duración.** | Un período en curso, todavía corto, sesgaría el promedio a la baja. | Hasta cerrar un período se usa la duración habitual configurada. |
| **E-1** | **Los días estimados nunca se guardan.** | El predictor no debe aprender de su propia suposición. | La interfaz muestra estimados sin escribirlos en la base. |
| **R-4** | **Se puede reabrir un período cerrado dentro de 7 días.** | Corregir un cierre por error sin abrir la puerta a reescribir el historial. | Después de 7 días hay que corregir día por día. |
| — | **Predicción con los últimos 6 ciclos ponderados, rango `max(1,5σ; 2)` y niveles de confianza (umbrales 0,18 y 0,10); ovulación = próximo período − 14 días; ventana de −5 días hasta la ovulación; datos obsoletos a partir de 60 días.** | Dar un rango honesto en lugar de una fecha exacta, y callar cuando faltan datos. | Es una estimación estadística, no un método anticonceptivo; así se avisa en la app. |
| — | **Una sola regla (`visibleFertileMarks`) decide cuándo se muestran ovulación y ventana, con interruptor para ocultarlas.** | Evitar que Inicio y Calendario discrepen. | Un único punto de cambio y de prueba. |

## 2. Arquitectura

| Id | Decisión | Motivo | Consecuencia / compromiso |
|---|---|---|---|
| — | **Dominio puro separado de Flutter y de la base.** | Probar las reglas con fechas fijas y sin dobles pesados. | Más archivos y una capa de traducción en el repositorio. |
| — | **Base local con drift sobre SQLite y flujos reactivos.** | Consultas tipadas, migraciones verificables y pantallas que se actualizan solas. | Dependencia de código generado (`build_runner`). |
| — | **Reloj y base inyectables.** | Pruebas deterministas y de cambio de día. | Parámetros `now`/`today` en varias firmas. |
| — | **Servicios como instancias globales con *setters* para tests.** | Simplicidad. | Más acoplamiento que la inyección por constructor; se reconoce como deuda. |
| **M-4** | **Abrir la base primero, antes de programar avisos o limpiar temporales; si falla, mostrar pantalla de reintento.** | Antes, un fallo ocurría antes de `runApp` y dejaba la app congelada en la pantalla de inicio. | `AppStartup` y `UpdateErrorScreen`; ningún efecto lateral hasta que la base abra. |
| — | **Cálculo del plan de avisos como función pura (`planNotifications`) y un reconciliador que lo aplica.** | Probar qué avisos corresponden sin tocar el sistema. | Cola de corridas para no dejar planes a medias. |
| — | **Derivación de clave y cifrado en un `Isolate`.** | Argon2id es costoso y congelaría la interfaz. | Más código de orquestación. |

## 3. Respaldo y cifrado

| Id | Decisión | Motivo | Consecuencia / compromiso |
|---|---|---|---|
| — | **Respaldo como JSON propio y versionado, no copia de la base.** | Validar todo antes de tocar nada, independencia del formato interno de drift y conversión de esquemas antiguos. | Hay que mantener el codificador; el tope es de 5 MiB. |
| — | **Cifrado opcional con Argon2id + AES-256-GCM, de la biblioteca `cryptography` (Dart puro).** | Algoritmos estándar, sin inventar criptografía; sin dependencia nativa. | Más lento que una implementación nativa; se mitiga con el `Isolate`. |
| — | **Parámetros: 19 456 KiB de memoria, 2 iteraciones, paralelismo 1; sal de 16 bytes y nonce de 12 nuevos en cada respaldo.** | Costo razonable en teléfonos modestos con resistencia a ataques sin conexión. | Se validan límites de los parámetros antes de derivar, para que un archivo manipulado no consuma recursos. |
| — | **El encabezado entra como dato autenticado (AAD).** | Que alterar cualquier campo haga fallar el descifrado. | Cualquier cambio de formato exige nueva versión. |
| — | **El respaldo manual no guarda la contraseña.** | Minimizar lo que Aura conserva. | Contraseña olvidada = respaldo irrecuperable. Se advierte antes de proteger. |
| — | **Copia previa a importar sin cifrar en almacenamiento privado.** | Permitir «Deshacer» sin pedir la contraseña de nuevo. | Queda un archivo legible; está marcado como mejora pendiente. |
| **RR-6** | **Excluir todo de la transferencia entre teléfonos de Android, además de la copia en la nube.** | Los datos de salud solo salen por decisión explícita de la usuaria. | Cambiar de teléfono exige exportar e importar a mano. |

## 4. Respaldo automático en Google Drive (1.2)

| Id | Decisión | Motivo | Consecuencia / compromiso |
|---|---|---|---|
| **A.2** | **Un solo archivo (`aura_respaldo_automatico.json`) que se reemplaza cada día, como el respaldo de WhatsApp (decisión del 2026-10-24).** | Simplicidad para la usuaria: una copia, siempre la última. El diseño original preveía siete archivos y verificación. | No hay historial de copias; si un respaldo sale dañado, el anterior ya no existe. Sin verificación posterior, ni restauración desde Drive dentro de la app, ni cambio de contraseña. |
| — | **Alcance `drive.file` y carpeta visible «Aura».** | Menor privilegio: Aura solo ve los archivos que ella misma crea. El diseño original usaba `drive.appdata`. | La usuaria puede ver y borrar el archivo desde su Drive. |
| **A.4** | **La contraseña del respaldo automático se guarda sellada con el Keystore de Android.** | Respaldar cada día sin pedirla. | Diferencia real respecto del manual, que debe decirse con precisión en README y política de privacidad. Si se pierde la clave del Keystore, hay que activar de nuevo. |
| — | **Apagado por defecto; a lo sumo un intento al día; cliente REST propio con `http` en lugar del SDK de Google.** | Opt-in, menos dependencias y control del tráfico. | Hay que mantener el cliente de Drive. |
| — | **`INTERNET` es el único permiso de red y solo se usa para Drive.** | Mantener la promesa de «los datos se quedan en el teléfono» salvo que la usuaria decida. | Cualquier otro uso de red debe documentarse y revisarse. |

## 5. Interfaz y experiencia

| Id | Decisión | Motivo | Consecuencia / compromiso |
|---|---|---|---|
| — | **Cuatro destinos fijos con `IndexedStack`.** | Conservar el estado de cada pestaña. | Las cuatro pantallas se mantienen vivas. |
| — | **Avisos opt-in, con texto genérico en pantalla bloqueada salvo «Mostrar detalles».** | Privacidad frente a terceros que miran el teléfono. | La usuaria elige el nivel de detalle. |
| — | **«Ocultar Aura en Recientes» con `FLAG_SECURE`.** | Evitar vistas previas y capturas. | También impide capturas voluntarias mientras esté activo. |
| — | **Mensajes de error sin texto técnico.** | No filtrar datos de salud en mensajes. | Menos pistas para diagnosticar; se compensa con tests y registros no sensibles. |

## 6. Decisiones abiertas

| Tema | Estado | Dónde seguir |
|---|---|---|
| Seguridad de datos de Google Play y si el respaldo en Drive cuenta como «recopilación» | Interpretación sin confirmar | HU-09, decisión 9; [`05_permisos_y_privacidad.md`](05_permisos_y_privacidad.md) |
| Declaración de exportación de criptografía | Clasificación no determinada | Especificación, inventario criptográfico |
| Condiciones del servicio | Sin decidir si hacen falta | HU-09 |
| Cifrar la copia previa a importar | Pendiente de mejora | Sección 3 |
| Cifrar la base local | No planeado; la contraseña protege solo los respaldos | [`04_modelo_de_datos.md`](04_modelo_de_datos.md) |
| Verificación, historial y restauración desde Drive | Descartados en la 1.2; el diseño original sigue en la Parte B de HU-09 | `HU-09_respaldo_drive_v1.2.md` |
