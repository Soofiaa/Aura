# 06 · Calidad y pruebas (QA)

> **App:** Aura 1.2.0 (build 7) · **Revisión:** 2026-10-24
> **Fuentes:** carpeta `test/` (74 archivos de prueba), `ESPECIFICACION_v1.1.md`, `CHANGELOG.md`, `README.md`.
> **Alcance de este documento:** describe la estrategia y el inventario de pruebas. Los **resultados de ejecución** están en la sección 8 (1296 casos aprobados, sin fallos).

## 1. Estrategia

La calidad de Aura se apoya en una decisión de arquitectura: **las reglas del ciclo viven en funciones puras** (`lib/domain/`), sin Flutter, sin base de datos y sin reloj real. Eso permite probarlas con fechas fijas y muchos casos límite, de forma rápida y determinista. Sobre esa base se agregan capas de prueba más pesadas solo donde hace falta.

| Nivel | Qué verifica | Herramienta | Dónde |
|---|---|---|---|
| **Unitario (dominio)** | Reglas de negocio: derivación de ciclos, predicción, ventana fértil, avisos, cifrado, formato de respaldo | `flutter_test` | `test/domain/` |
| **Datos / integración** | Repositorio contra una base real en memoria, migraciones, servicio de respaldo, Drive con dobles, reconciliador de avisos | `flutter_test` + `AppDatabase.forTesting` | `test/data/`, `test/drift/` |
| **Widget** | Pantallas y diálogos: lo que la usuaria ve y toca, incluidos mensajes de error y estados vacíos | `flutter_test` (`testWidgets`) | `test/screens/`, `test/widgets/` |
| **Plataforma / configuración** | Manifest (orientación, sin respaldo en la nube, `FLAG_SECURE`, `INTERNET`), arranque, accesibilidad de colores | `flutter_test` | `test/android_manifest_test.dart`, `test/app_startup_test.dart`, `test/utils/colors_test.dart` |
| **Manual en dispositivo** | Notificaciones reales, reinicio del teléfono, Drive real, rendimiento | Teléfono Android y prueba cerrada de Play | Sección 6 |

**Técnicas de diseño de casos que se aplican:**

- **Valores límite:** ciclo de 15 y 60 días, brecha de 7 y 8 días entre sangrados, período de 1 y 15 días, nota de 2000 caracteres, respaldo en el tope de 5 MiB.
- **Particiones de equivalencia:** ciclos regulares, irregulares, con un solo ciclo, sin ciclos; período abierto, cerrado, cerrado por inferencia.
- **Tablas de decisión:** cuándo se muestran ovulación y ventana (`visibleFertileMarks`), qué avisos corresponden (`planNotifications`).
- **Transiciones de estado:** ciclo de vida del período (abierto → cerrado → reabierto, regla R-4) y selección de rango en el calendario.
- **Pruebas de regresión dirigidas:** cada defecto corregido conserva su test (sección 5).
- **Pruebas con vectores conocidos** para Argon2id y AES-GCM, de modo que el cifrado se compare contra resultados publicados y no solo contra sí mismo.
- **Tiempo controlado:** `now` y `today` se inyectan; hay tests específicos de cambio de día con la app abierta y de la hora de Chile (cambio de horario a medianoche).

## 2. Inventario de pruebas

74 archivos de prueba. Declaraciones `test(` y `testWidgets(` literales: **1014**. Al ejecutar, los bucles y ayudantes generan casos adicionales y la suite corre **1296** (sección 8).

| Capa | Archivos | Qué cubre |
|---|---|---|
| Dominio | 12 | Derivador de ciclos, predictor (el más extenso), período en curso, marcas fértiles, planificador de avisos, formato y cifrado de respaldo, recordatorio, fortaleza de contraseña, selección de rango, ranking de síntomas, migración de períodos antiguos |
| Datos | 19 | Repositorio (acciones de período, respaldo, lecturas), migraciones v3→v4 y v4→v5, copia previa a la migración, servicio de respaldo (plano y cifrado), cliente de Drive, respaldo automático, almacenes de estado, reconciliador de avisos |
| Esquemas drift | 1 (+ 4 esquemas generados) | Migraciones verificadas contra volcados de cada versión del esquema |
| Pantallas | 25 | Inicio, calendario (rango, estimados, ventana fértil, cierre de período, cambio de día), registrar día, estadísticas, ajustes, respaldo (crear, proteger, desbloquear, recordatorio), Drive, presentación inicial, navegación |
| Widgets | 5 | Hoja de inicio de período, selector de síntomas, diálogos de proteger y desbloquear respaldo |
| Utilidades | 9 | Fechas (`DayKey`), zona horaria, colores y contraste, localización, snackbar, versión, Keystore con doble, textos |
| Raíz | 3 | Manifest, arranque (`AppStartup`), prueba de humo del widget raíz |
| **Total** | **74** | |

**Datos de prueba (`test/fixtures/`):** respaldos reales de esquema v3, v4, v5 y v5 cifrado, para comprobar que lo exportado antes se sigue importando. **Dobles (`test/support/`):** planificador de avisos, respaldo, Drive, ajustes del teléfono, lanzador de URL; con tests de paridad para que el doble no se aleje del comportamiento real (`fake_reminder_parity_test.dart`).

## 3. Trazabilidad requisito → pruebas

Los identificadores de requisito están en [`01_requisitos.md`](01_requisitos.md). Esta matriz enlaza cada área funcional con los archivos que la ejercitan.

| Área funcional | Reglas y decisiones | Pruebas principales |
|---|---|---|
| Registrar días y períodos | Solo se guardan días de sangrado; `CHECK` de flujo y de `period_end` | `data/repositories/cycle_repository_test.dart`, `…_period_actions_test.dart`, `screens/add_cycle_screen_test.dart`, `widgets/symptom_selector_test.dart` |
| Derivación de ciclos | Brecha > 7 días = período nuevo; ciclo válido 15–60 | `domain/cycle_deriver_test.dart` |
| Cierre de período | D-1, D-2, P-1, R-4 | `domain/current_period_test.dart`, `domain/legacy_period_ends_test.dart`, `screens/calendar_screen_end_day_test.dart`, `screens/home_screen_period_check_test.dart` |
| Predicción y confianza | Últimos 6 ciclos ponderados; rango; umbrales; datos obsoletos | `domain/cycle_predictor_test.dart`, `screens/home_screen_prediction_card_test.dart`, `screens/home_screen_coherencia_test.dart` |
| Ovulación y ventana fértil | Regla única de visibilidad; ajuste para ocultarla | `domain/fertile_marks_test.dart`, `screens/calendar_screen_fertile_test.dart` |
| Estimados | Nunca se guardan (E-1) | `screens/calendar_screen_estimates_test.dart`, `domain/current_period_test.dart` |
| Calendario | Selección de rango; cambio de día con la app abierta | `domain/range_selection_test.dart`, `screens/calendar_screen_range_test.dart`, `…_day_change_test.dart`, `screens/home_screen_day_change_test.dart` |
| Estadísticas | Duraciones, regularidad, síntomas frecuentes | `screens/stats_screen_test.dart`, `domain/symptom_ranking_test.dart` |
| Avisos | Plan puro; reconciliación; permiso; aviso de atraso | `domain/notification_planner_test.dart`, `data/notifications/notification_reconciler_test.dart`, `screens/calendar_screen_avisos_test.dart`, `screens/settings_screen_test.dart` |
| Respaldo manual | Formato versionado, límite de tamaño, validación previa, copia previa a importar | `domain/backup_codec_test.dart`, `data/backup/backup_service_test.dart`, `data/repositories/cycle_repository_backup_test.dart`, `screens/backup_create_flow_test.dart`, `screens/backup_section_test.dart` |
| Respaldo cifrado | Argon2id + AES-256-GCM; encabezado autenticado; límites de parámetros | `domain/backup_crypto_test.dart`, `data/backup/backup_service_encrypted_test.dart`, `domain/password_strength_test.dart`, `widgets/protect_backup_dialog_test.dart`, `widgets/unlock_backup_dialog_test.dart`, `screens/backup_section_protected_test.dart`, `…_unlock_test.dart` |
| Compatibilidad de respaldos | v3 y v4 se importan igual que una migración | `data/backup/v3_migration_vs_import_test.dart`, `test/fixtures/` |
| Recordatorio de respaldo | Reglas y persistencia | `domain/backup_reminder_test.dart`, `data/backup/backup_reminder_store_test.dart`, `screens/home_backup_reminder_test.dart`, `screens/settings_backup_reminder_test.dart` |
| Respaldo automático en Drive | Un archivo, alcance `drive.file`, a lo sumo uno al día, contraseña sellada | `data/backup/auto_drive_backup_service_test.dart`, `data/backup/drive_api_client_test.dart`, `data/backup/drive_backup_settings_store_test.dart`, `screens/drive_backup_section_test.dart`, `utils/keystore_vault_test.dart` |
| Migraciones de base | v3→v4→v5 transaccionales, con verificaciones y copia previa | `data/database/app_database_*_migration_test.dart`, `data/backup/pre_migration_copy_test.dart`, `drift/aura/migration_test.dart` |
| Arranque robusto | La base se abre primero; fallo → pantalla de reintento (M-4) | `app_startup_test.dart` |
| Privacidad de plataforma | Orientación, `allowBackup`, transferencia, `FLAG_SECURE`, `INTERNET` | `android_manifest_test.dart`, `data/device_settings_store_test.dart` |
| Accesibilidad visual | Contraste de colores | `utils/colors_test.dart`, `test/support/contrast.dart` |
| Fechas y zona horaria | Texto `yyyy-MM-dd`, aritmética UTC, Chile | `utils/day_key_test.dart`, `utils/time_zone_test.dart` |
| Presentación y navegación | Onboarding, cuatro destinos | `screens/onboarding_screen_test.dart`, `screens/main_navigation_screen_test.dart` |

*Pendiente (mejora de la matriz):* citar el identificador exacto de cada RF en el nombre o la descripción del grupo de pruebas, para que la trazabilidad se pueda buscar con `grep` en lugar de depender de esta tabla.

## 4. Criterios de calidad que el proyecto ya aplica

| Criterio | Cómo se cumple |
|---|---|
| **No perder datos** | Copia previa antes de migrar e importar; migración en transacción con verificaciones; importación que valida todo antes de tocar la base; «Deshacer» de la importación. |
| **Fallar con claridad** | Mensajes de error sin texto técnico ni datos de salud; pantalla de reintento si no abre la base. |
| **Privacidad comprobable** | Reglas de manifest cubiertas por test; sin `print` ni registros con datos (verificado en 1.1.0). |
| **Determinismo** | Reloj y base inyectables; fechas fijas en los tests. |
| **Doble de prueba fiel** | Tests de paridad entre el doble y la implementación real del almacén de recordatorios. |
| **Compatibilidad** | Fixtures de respaldos antiguos importados en cada versión. |

## 5. Defectos conocidos y regresiones

El historial de defectos corregidos está en `CHANGELOG.md` y en las decisiones de `ESPECIFICACION_v1.1.md` (por ejemplo, el congelamiento al fallar la apertura de la base, M-4, y la unificación de la regla de ventana fértil). Cada corrección significativa conserva su test de regresión en la matriz de la sección 3.

*Pendiente:* consolidar una tabla de defectos con identificador, severidad, versión de origen, corrección y test asociado. No se incluye aquí porque requiere revisar el historial completo de commits y no se inventa.

## 6. Pruebas manuales en dispositivo

Lo que los tests automáticos no pueden asegurar y se verifica en un teléfono real:

| Prueba | Qué se comprueba | Estado |
|---|---|---|
| Notificaciones programadas | Llegan a la hora elegida, con texto genérico en pantalla bloqueada | Prueba cerrada |
| Reinicio del teléfono | Los avisos se reprograman (`RECEIVE_BOOT_COMPLETED`) | Prueba cerrada |
| Permiso de notificaciones (Android 13+) | Solicitud, rechazo, «Abrir ajustes» tras dos negativas | Prueba cerrada |
| Respaldo en Drive real | Inicio de sesión, creación de la carpeta «Aura», reemplazo diario del archivo | Prueba cerrada |
| Ocultar en Recientes | Vista previa en blanco y sin capturas | Prueba cerrada |
| Importar en otro teléfono | Un respaldo (plano y cifrado) se restaura completo | Prueba cerrada |
| Rendimiento del cifrado | Derivar la clave (Argon2id) no congela la interfaz en un teléfono modesto | Prueba cerrada |

El guion para las testers está en la capa de usuaria (documento aparte). **Esta tabla no registra resultados**: se completan con lo que informen las testers.

## 7. Brechas y riesgos de calidad

| Brecha | Impacto | Propuesta |
|---|---|---|
| No hay pruebas de integración de extremo a extremo en dispositivo (`integration_test`) | Los flujos completos dependen de la prueba manual | Agregar un recorrido mínimo: registrar día → ver predicción → exportar → importar |
| El código Kotlin (`MainActivity`: pantalla segura, Keystore, ajustes) no tiene tests propios | Un cambio nativo solo se detecta a mano | Cubrirlo con la prueba manual y, si crece, con pruebas instrumentadas |
| Verificación de permisos hecha con `aapt` sobre la 1.1.0 | La 1.2.0 agrega `INTERNET` | Repetirla sobre la 1.2.0 y automatizar una lista permitida |
| Porcentaje de cobertura sin calcular | El reporte `lcov.info` existe pero no se resumió | Resumirlo con `lcov --summary` y registrarlo en la sección 8 |
| El análisis estático se ejecuta a mano | `flutter analyze` pasó limpio el 2026-10-24, pero nada lo fuerza en cada cambio | Integrarlo a CI |
| Sin integración continua | Los tests dependen de que se ejecuten a mano | Una acción de GitHub que corra `flutter analyze` y `flutter test` |
| Pruebas con usuarias reales aún en curso | La usabilidad no está validada con muestra suficiente | Cerrar la prueba cerrada y recoger hallazgos |

## 8. Resultados de ejecución

Ejecución local de Sofia el 2026-10-24 sobre la versión 1.2.0+7 (Windows, Flutter estable), con `flutter analyze` y `flutter test --coverage`:

| Medida | Resultado |
|---|---|
| Análisis estático (`flutter analyze`) | **Sin problemas** (36,2 s) |
| Casos ejecutados | **1296** |
| Aprobados / fallidos | **1296 / 0** («All tests passed») |
| Duración de la suite | Aprox. 1 min 5 s |
| Cobertura de líneas | Reporte generado (`coverage/lcov.info`); el porcentaje **no se imprime** en consola y queda por calcular |

La cifra del README («más de 1290 pruebas») queda **confirmada**: 1296 casos en ejecución frente a 1014 declaraciones literales, porque los bucles y ayudantes generan casos adicionales.

**Observaciones de la ejecución:**

- Durante la suite aparece la advertencia de drift «*creaste la clase AppDatabase varias veces*». Proviene de los tests, que crean una base en memoria por caso con `AppDatabase.forTesting` sin cerrar la anterior. Solo se emite en compilaciones de depuración y no afecta al resultado. Mejora posible: cerrar la base en `tearDown` o fijar `driftRuntimeOptions.dontWarnAboutMultipleDatabases = true` en los tests, para dejar la salida limpia.
- Hay 59 paquetes con versiones nuevas incompatibles con las restricciones actuales (entre ellos `drift`, `fl_chart`, `flutter_local_notifications`, `flutter_timezone`, `file_picker` y `sqlite3_flutter_libs`, este último marcado como fin de vida). No es un fallo, pero conviene planear una actualización controlada.

Para calcular el porcentaje de cobertura (opcional):

```bash
# Linux/macOS/WSL con lcov instalado
lcov --summary coverage/lcov.info
```
