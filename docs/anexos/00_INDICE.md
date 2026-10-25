# Documentación de Aura

> **Versión de la app documentada:** 1.2.0 (build 7) · **Revisión:** 2026-10-24 · **Autora:** Sofia Menzel
>
> Aura es una app Android, hecha con Flutter, que registra el ciclo menstrual y estima sus fases. Es **local primero**: sin cuenta, sin servidor propio y sin analítica. Los datos viven en el teléfono y solo salen en un respaldo que decide la usuaria.

Esta carpeta reúne la documentación técnica del proyecto. Se escribió **después** de construir la app, a partir del código, de la especificación que fue creciendo con cada versión y de las pruebas hechas en el teléfono. Donde algo no se pudo comprobar, el documento lo dice.

## Por dónde empezar

| Si eres… | Lee primero | Después |
|---|---|---|
| **Reclutadora o reclutador** | [Informe del proyecto](informe/) · [Calidad y pruebas](06_calidad_y_pruebas.md) | [Decisiones de diseño](07_decisiones.md) |
| **Analista o QA** | [Requisitos](01_requisitos.md) · [Casos de uso](02_casos_de_uso.md) | [Calidad y pruebas](06_calidad_y_pruebas.md) |
| **Desarrolladora o desarrollador** | [Arquitectura](03_arquitectura.md) · [Modelo de datos](04_modelo_de_datos.md) | [Decisiones de diseño](07_decisiones.md) |
| **Usuaria o tester** | [README](../README.md) · [Política de privacidad](privacy.html) | [Permisos y privacidad](05_permisos_y_privacidad.md) |

## Documentos

| N.º | Documento | Qué responde |
|---|---|---|
| 01 | [Requisitos](01_requisitos.md) | ¿Qué debe hacer Aura y bajo qué reglas? |
| 02 | [Casos de uso](02_casos_de_uso.md) | ¿Cómo interactúa la usuaria con la app, paso a paso? |
| 03 | [Arquitectura](03_arquitectura.md) | ¿Cómo está construida y por qué así? |
| 04 | [Modelo de datos](04_modelo_de_datos.md) | ¿Qué se guarda, dónde y con qué reglas? |
| 05 | [Permisos y privacidad](05_permisos_y_privacidad.md) | ¿Qué permisos pide, qué datos salen y qué protege? |
| 06 | [Calidad y pruebas](06_calidad_y_pruebas.md) | ¿Cómo se verificó y qué defectos se encontraron? |
| 07 | [Decisiones de diseño](07_decisiones.md) | ¿Por qué se eligió cada camino? |

## Documentos de origen (más detallados)

Estos son los documentos con los que se fue construyendo la app. Los de arriba los resumen y ordenan; estos conservan el detalle.

- [`ESPECIFICACION_v1.1.md`](ESPECIFICACION_v1.1.md): historias de usuario, criterios de aceptación, hallazgos, registro de decisiones (unas 50).
- [`HU-09_respaldo_drive_v1.2.md`](HU-09_respaldo_drive_v1.2.md): el respaldo automático en Google Drive. La Parte A es lo construido; la Parte B es un diseño ampliado, no implementado.
- [`DRIVE_SETUP.md`](DRIVE_SETUP.md): cómo configurar el acceso a Google Drive.
- [`../CHANGELOG.md`](../CHANGELOG.md): cambios por versión.

## Convenciones

- **ID de historia (HU-xx):** historia de usuario de la especificación. **RF-xx / RNF-xx:** requisito funcional / no funcional de este paquete, con su origen indicado.
- **Verificado en el código** significa que se leyó el archivo citado. **Sin probar** o **pendiente de verificar** significa que no se comprobó.
- Las fechas van como `AAAA-MM-DD`. Los textos de la interfaz van entre «comillas».
