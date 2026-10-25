# 01 · Requisitos

> **App:** Aura 1.2.0 (build 7) · **Revisión:** 2026-10-24
> **Fuentes:** `ESPECIFICACION_v1.1.md`, `HU-09_respaldo_drive_v1.2.md` (Parte A), `CHANGELOG.md` y el código en `lib/`.
> Este documento **consolida** los requisitos que hoy están repartidos en esas fuentes. No agrega funciones nuevas.

## 1. Propósito y alcance

Aura permite a una persona registrar su ciclo menstrual y obtener una **estimación honesta** de su próximo período, su fase actual y, cuando hay datos suficientes, su ovulación y ventana fértil. Todo ocurre en el teléfono.

**Dentro del alcance:** registro diario, predicción por el método del calendario, estadísticas, recordatorios locales, respaldo y restauración (manual y automático en Google Drive).

**Fuera del alcance (hoy):** iOS, modo oscuro, interfaz en inglés, cifrado de la base dentro del teléfono, historial de anticonceptivos (HU-07, planificado), recordatorio de toma de pastilla, cuenta o sincronización propia, publicidad, pagos y exportación a PDF clínico.

**Aviso:** Aura **no es un método anticonceptivo ni un dispositivo médico**. Ofrece estimaciones informativas.

## 2. Requisitos funcionales

| ID | Requisito | Reglas clave | Origen | Estado |
|---|---|---|---|---|
| RF-01 | **Registrar un día**: sangrado, intensidad del flujo, ánimo, síntomas y notas. | Flujo: ligero, moderado, abundante. Ánimo: 5 valores. Síntomas: 8. Notas: máx. 2000 caracteres. No se admiten fechas futuras. En un día sin registro todo parte «sin especificar». Guardar un día vacío no escribe nada. Salir con cambios pide confirmación. | v1.0, B-1 a B-3, T2-1 a T2-4 | Implementado |
| RF-02 | **Derivar ciclos** a partir de los días de sangrado. Los ciclos no se crean a mano. | Un día de sangrado a **más de 7 días** del anterior inicia un período nuevo. Un ciclo es válido si dura de **15 a 60 días**. | v1.0 | Implementado |
| RF-03 | **Predecir el próximo período** con un rango y un nivel de confianza (baja, media, alta). | Promedio ponderado de los últimos 6 ciclos válidos (los recientes pesan más). Rango = máx(1,5·σ, 2 días); 3 días con menos de 2 ciclos. Ciclo por defecto: 28 días. | v1.0, HU-05a | Implementado |
| RF-04 | **Mostrar la fase actual** (menstrual, folicular, ovulatoria, lútea). | No se muestra con el período atrasado ni con datos desactualizados (más de 60 días desde el último inicio). | v1.0, HU-05a | Implementado |
| RF-05 | **Mostrar ovulación y ventana fértil estimadas**, solo bajo condiciones. | Se muestran únicamente con confianza **media o alta**, sin período atrasado y con el interruptor encendido. Ovulación = próximo período − 14 días; ventana = ovulación − 5 hasta la ovulación. No se muestran si la ovulación caería dentro del período. | HU-05a, HU-05c, HU-05d | Implementado |
| RF-06 | **Configurar la duración habitual del período.** | De 1 a 15 días, por defecto 5. Cambiarla no modifica registros. Solo afecta las estimaciones mientras no haya períodos terminados. | HU-01 | Implementado |
| RF-07 | **Registrar el inicio del período con un toque** («Me llegó hoy»). | Guarda solo el primer día; los siguientes se muestran como estimados y **no se guardan**. Hoy, ayer u otro día; nunca futuro. «Deshacer» durante 7 segundos. | HU-02 | Implementado |
| RF-08 | **Indicar que el período terminó.** | «Sigue», «Terminó hoy» y «Ya terminó antes». Un período cerrado entra al promedio de duración; uno abierto no. Se completan los días sin registro y se respetan los «No» explícitos. | HU-03, D-1, P-1 | Implementado |
| RF-09 | **Calendario**: ver, marcar y quitar días; elegir varios días; ver estimados y confirmarlos. | Estimado = borde punteado; registrado = relleno. Con un rango completo, un toque nuevo lo alarga, mueve o acorta (no lo descarta). Más de 10 días pide confirmación. Todas las acciones tienen «Deshacer». | HU-04, U-1 | Implementado |
| RF-10 | **Estadísticas** («Tus ciclos»). | Duración típica del ciclo, más corto y más largo, regularidad (regular, algo variable, muy variable), duración típica del período, frecuencia de síntomas y de ánimo, flujo promedio. Con menos de 2 ciclos muestra un mensaje en vez de un promedio engañoso. | HU-05b | Implementado |
| RF-11 | **Recordatorios locales opcionales**: período, ventana fértil y «¿Te llegó el período?». | Apagados por defecto (el interruptor general también). Texto discreto salvo que se active «Mostrar detalles». Hora configurable (por defecto 9:00). Se reprograman tras reiniciar el teléfono. | v1.0, HU-05a | Implementado |
| RF-12 | **Respaldar y restaurar en un archivo JSON.** | Valida el archivo **antes** de tocar los datos. Importar reemplaza tras una confirmación con recuentos. Es atómico (todo o nada). Acepta respaldos de esquemas anteriores y rechaza los de versión posterior. «Deshacer» tras importar. | HU-06 | Implementado |
| RF-13 | **Proteger el respaldo con contraseña** (opcional). | Mínimo 10 caracteres. AES-256-GCM con clave derivada con Argon2id. Aura no guarda la contraseña de los respaldos manuales ni puede recuperarla. | HU-06b | Implementado |
| RF-14 | **Recordar crear un respaldo.** | Tarjeta en Inicio si pasaron 30 días sin respaldo (o 7 días de uso sin ninguno). «Ahora no» la oculta 7 días. Sin notificación del sistema. | HU-08 | Implementado |
| RF-15 | **Respaldo automático en Google Drive** (opcional). | Apagado por defecto. Una vez al día, cifrado, en un único archivo de la carpeta «Aura». Alcance `drive.file`. Ver [`HU-09`](HU-09_respaldo_drive_v1.2.md), Parte A. | HU-09 | Implementado (1.2.0) |
| RF-16 | **Borrar todos los datos.** | Elimina registros, ajustes y copias internas; compacta la base y sobrescribe lo borrado; olvida la cuenta de Drive. | v1.0, 1.1.1 | Implementado |
| RF-17 | **Ocultar Aura en Recientes.** | Activado por defecto. La vista previa sale en blanco y se bloquean capturas y grabaciones. | 1.1.1 | Implementado |
| RF-18 | **Presentación inicial** (onboarding) de 4 páginas, solo en instalaciones nuevas. | La 4.ª página explica que los datos viven en el teléfono y recomienda crear respaldos. | v1.0, HU-08 | Implementado |
| RF-19 | **Historial de anticonceptivos.** | Solo un método hormonal en uso a la vez. Los ciclos con anticonceptivo hormonal no entran a la predicción natural. | HU-07 | **Planificado, no implementado** |

## 3. Requisitos no funcionales

| ID | Categoría | Requisito | Cómo se verifica |
|---|---|---|---|
| RNF-01 | Privacidad | Con el respaldo en Drive apagado, la app no usa la red. El permiso `INTERNET` existe solo para ese respaldo. | `android_manifest_test.dart` (declara `INTERNET`); resto manual |
| RNF-02 | Privacidad | `allowBackup="false"` y reglas de extracción que excluyen todo: Android no copia los datos ni por la nube ni al cambiar de teléfono. | `android_manifest_test.dart` (RR-6) |
| RNF-03 | Privacidad | Ningún dato sale del teléfono sin que la usuaria lo decida. Lo que sube a Drive va siempre cifrado. | Revisión de código y tests del servicio de Drive |
| RNF-04 | Privacidad | La pantalla se oculta en Recientes y se bloquean capturas (`FLAG_SECURE`), salvo que la usuaria lo apague. | `android_manifest_test.dart` |
| RNF-05 | Integridad | Cada cambio de esquema lleva migración y **test de migración**. Ningún dato se pierde al actualizar. Antes de migrar se guarda una copia previa. | `app_database_*_migration_test.dart`, `pre_migration_copy_test.dart` |
| RNF-06 | Integridad | La importación es atómica: o se aplica completa o no se cambia nada. | `cycle_repository_backup_test.dart` |
| RNF-07 | Exactitud | Un dato estimado nunca se guarda como dato real. | Tests de calendario y de repositorio |
| RNF-08 | Exactitud | Los días son fechas de calendario, no instantes: texto `yyyy-MM-dd` y aritmética en UTC, sin errores por el cambio de hora de Chile. | `day_key_test.dart`, `cycle_predictor_test.dart` («cambios de hora de Chile») |
| RNF-09 | Calidad | `flutter analyze` sin advertencias y toda la batería de tests en verde antes de cada merge. | Manual (no hay integración continua todavía) |
| RNF-10 | Calidad | Cada historia agrega tests en la capa donde vive la regla: dominio puro primero, luego repositorio, luego widget. | Estructura de `test/` |
| RNF-11 | Accesibilidad | Objetivos táctiles de al menos 44 dp (los nuevos usan 48 dp). Contraste suficiente. La información no depende solo del color. Los textos soportan letra grande sin desbordar. | `colors_test.dart` y tests de pantalla; TalkBack no se probó de forma sistemática |
| RNF-12 | Rendimiento | Crear un respaldo protegido no congela la interfaz. Medido: 0,42 a 0,50 s en un POCO X6 Pro. | Medición manual (2026-10-08); teléfonos de gama baja **sin medir** |
| RNF-13 | Compatibilidad | Android 7 o superior (`minSdk` 24), orientación vertical en teléfonos. | Manifest; prueba manual |
| RNF-14 | Idioma | Interfaz en español; fechas en español. | — |
| RNF-15 | Release | Los cambios de recursos (íconos, `keep.xml`) se comprueban en un build de release instalado, no solo en debug. | Manual |

## 4. Reglas de negocio y umbrales

Son **decisiones de producto**, no criterios clínicos. Viven en `PredictionConfig` (`lib/domain/cycle_predictor.dart`).

| Concepto | Regla |
|---|---|
| Período nuevo | Un día de sangrado a más de **7 días** del anterior |
| Ciclo válido | De **15 a 60** días; los demás no cuentan |
| Ciclos que promedian | Los **6** más recientes, ponderados (1, 2, 3…; los recientes pesan más) |
| Rango del próximo período | máx(**1,5**·σ, **2** días); **3** días si hay menos de 2 ciclos |
| Confianza baja | Menos de 2 ciclos, o desviación/promedio > **0,18** |
| Confianza media | 2 o 3 ciclos con desviación/promedio ≤ 0,18 |
| Confianza alta | 4 ciclos o más con desviación/promedio ≤ 0,18 |
| Regularidad | «Regular» ≤ **0,10**; «Algo variable» hasta 0,18; «Muy variable» por encima |
| Ovulación | Próximo período esperado − **14** días |
| Ventana fértil | De ovulación − **5** días hasta la ovulación |
| Período atrasado | Hoy es posterior al extremo tardío del rango |
| Datos desactualizados | Más de **60** días desde el último inicio (y más de 7 días de atraso sobre el extremo tardío del rango) |
| Duración del período | Promedio ponderado de los períodos **cerrados**; si no hay ninguno, la duración habitual (1 a 15, por defecto 5) |
| Período cerrado | Su último día tiene `period_end`, o hay un «No» explícito entre 1 y 7 días después |
| Reabrir un período | Marcar un día a 7 días o menos de un período cerrado lo reabre (R-4) |
| Respaldo manual | Máx. 5 MiB sin cifrar; mínimo 10 caracteres de contraseña |
| Recordatorio de respaldo | 30 días sin respaldo; gracia de 7 días desde el primer uso; «Ahora no» = 7 días |

## 5. Glosario

| Término | Significado |
|---|---|
| **Día de sangrado** | Día marcado como período. Es lo único que se guarda del ciclo; todo lo demás se deriva. |
| **Período** | Racha de días de sangrado separados por 7 días o menos. |
| **Ciclo** | Desde el inicio de un período hasta el inicio del siguiente. El último ciclo queda abierto. |
| **Período abierto / cerrado** | Cerrado si la usuaria indicó que terminó (o se infirió al migrar). Solo los cerrados entran al promedio de duración. |
| **Día estimado** | Día que Aura supone que seguirá el período. Se muestra con borde punteado y no se guarda. |
| **Confianza** | Qué tan fiable es la predicción, según cuántos ciclos hay y qué tan regulares son. |
| **Respaldo** | Archivo con todos los datos. Puede ir cifrado. |
| **Copia previa** | Copia interna que Aura guarda antes de migrar o de importar, para poder deshacer. |

## 6. Pendientes conocidos

Ver las secciones «Limitaciones conocidas» y «Pendientes» de `ESPECIFICACION_v1.1.md` y la sección A.5 de `HU-09_respaldo_drive_v1.2.md`. Los principales:

- Historial de anticonceptivos (HU-07).
- Restaurar desde Drive dentro de la app, cambiar la contraseña del respaldo automático y verificar el archivo tras subirlo.
- Integración continua (GitHub Actions).
- Íconos temáticos de Android 13 (T-03).
- Mejoras de accesibilidad del modo de rango del calendario.
