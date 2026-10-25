# 05 · Permisos y privacidad

> **App:** Aura 1.2.0 (build 7) · **Revisión:** 2026-10-24
> **Fuentes:** `android/app/src/main/AndroidManifest.xml`, `data_extraction_rules.xml`, `test/android_manifest_test.dart`, el inventario criptográfico de `ESPECIFICACION_v1.1.md`, `HU-09_respaldo_drive_v1.2.md` (Parte A) y el código de `lib/data/backup/`.
> **Importante:** esto es documentación técnica del proyecto, **no una opinión legal**. Los puntos de cumplimiento (sección 7) requieren verificación con las fuentes oficiales o asesoría profesional.

## 1. Resumen en una página

Aura guarda datos de salud sensibles, así que su diseño parte de una regla: **los datos se quedan en el teléfono**, salvo que la usuaria decida otra cosa.

- No tiene cuenta, servidor propio, analítica, publicidad ni telemetría.
- Hay **una sola** salida de datos opcional por la red: el respaldo automático en el Google Drive de la propia usuaria. Está **apagado por defecto** y siempre sube el archivo **cifrado**.
- Android no copia los datos de Aura ni a la nube ni al cambiar de teléfono.
- La base de datos dentro del teléfono **no está cifrada**; lo que se protege con contraseña es el archivo de respaldo.

## 2. Permisos

| Permiso | Para qué | Cuándo se usa | Dónde se declara |
|---|---|---|---|
| `POST_NOTIFICATIONS` | Mostrar los recordatorios | Solo si la usuaria activa los avisos. Android 13 o superior lo pide en ejecución. Si Android deja de preguntar tras dos negativas, Aura ofrece «Abrir ajustes». | Manifest de la app |
| `RECEIVE_BOOT_COMPLETED` | Reprogramar los avisos tras reiniciar el teléfono o actualizar la app | En segundo plano, solo si hay avisos programados | Manifest de la app |
| `INTERNET` | **Únicamente** el respaldo automático en Google Drive | Solo con ese respaldo activado | Manifest de la app (desde la 1.2.0) |
| `VIBRATE` | Vibración de las notificaciones | Con los avisos | Según lo verificado en la 1.1.0, aparece en el manifest fusionado del release (lo incorpora una dependencia, no el manifest propio) |
| `com.soofiaa.aura.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` | Permiso propio que agrega AndroidX para receptores internos | Interno | Manifest fusionado |

**Qué no pide:** ubicación, contactos, cámara, micrófono, almacenamiento amplio, teléfono ni acceso a otras apps. Los archivos de respaldo se guardan y se leen con el selector del sistema, que no requiere permisos de almacenamiento.

**Verificación:** la lista de permisos del release se comprobó con `aapt dump permissions` sobre la versión 1.1.0 (sin `INTERNET`). La 1.2.0 agrega `INTERNET` y el test `android_manifest_test.dart` comprueba que esté declarado. *Pendiente: repetir la verificación con `aapt` sobre el APK de la 1.2.0 y automatizar una lista permitida que falle ante cualquier permiso nuevo.*

## 3. Configuración de seguridad del manifest

| Elemento | Valor | Efecto |
|---|---|---|
| `allowBackup` | `false` | Android no sube los datos a su respaldo en la nube |
| `dataExtractionRules` | Excluye todo, en `cloud-backup` y en `device-transfer` | Tampoco se copian al cambiar de teléfono por cable o Wi-Fi (decisión RR-6) |
| `MainActivity` | Exportada, solo como lanzador; orientación vertical | Sin enlaces profundos |
| Receptores de avisos | `exported="false"` | Solo el sistema los dispara |
| `FLAG_SECURE` | Activo al arrancar; configurable | «Ocultar Aura en Recientes»: vista previa en blanco y sin capturas ni grabaciones |
| `<queries>` | `PROCESS_TEXT` y selector de archivos | Mínimo necesario |

Estos puntos tienen test en `android_manifest_test.dart`: orientación, ausencia de respaldo en la nube y de transferencia (RR-6), `FLAG_SECURE` e `INTERNET` declarado.

## 4. Qué datos guarda y dónde

| Dato | Dónde vive | Cifrado | Sale del teléfono |
|---|---|---|---|
| Días de sangrado, flujo, ánimo, síntomas, notas | Base SQLite en el almacenamiento privado de la app | **No** | Solo en un respaldo |
| Ajustes del ciclo y de avisos | Misma base | No | Solo en un respaldo |
| Ajustes de este teléfono | `ajustes_telefono.json` | No | Nunca |
| Estado del recordatorio de respaldo | `recordatorio_respaldo.json` | No | Nunca |
| Cuenta de Google y contraseña del respaldo automático | `respaldo_drive.json` | La contraseña va **sellada con el Keystore de Android**; la cuenta (correo) no | Nunca. (El inicio de sesión lo gestiona Google.) |
| Copia previa a una importación | `respaldos/antes_de_importar.json` | **No**, aunque el respaldo importado estuviera protegido | Nunca |
| Copia previa a una migración (bases antiguas) | `respaldos/antes_de_migrar_v4.sqlite` | No | Nunca |
| Archivos de respaldo | Donde la usuaria los guarde o comparta; o su Drive | Opcional (manual); **siempre** (automático) | Por decisión de ella |

«Almacenamiento privado» significa que otras apps no pueden leerlo en un teléfono sin acceso privilegiado.

## 5. Flujos de salida de datos

| Flujo | Qué sale | Quién lo decide | Cifrado |
|---|---|---|---|
| **Respaldo manual** | Un archivo JSON con todos los datos | La usuaria, cada vez | Opcional, con contraseña |
| **Compartir un respaldo** | El mismo archivo, hacia la app que ella elija | La usuaria | Opcional |
| **Respaldo automático en Drive** | Un único archivo `aura_respaldo_automatico.json` en la carpeta «Aura» de su Drive, una vez al día | La usuaria, al activarlo | **Siempre** (AES-256-GCM, Argon2id) |
| **Política de privacidad** | Nada: Aura pide al sistema abrir un enlace en el navegador | La usuaria, al tocarlo | — |

Con el respaldo automático, **Google ve** que el archivo existe, su tamaño y sus fechas, pero no su contenido. Aura pide solo el alcance `drive.file`: ve únicamente los archivos que ella misma crea.

No hay otro tráfico de red propio: el único código con red es el cliente de Drive (`https://www.googleapis.com`). Las dependencias de red que aparecen en `pubspec.lock` son transitivas de herramientas de desarrollo y no entran en la app.

## 6. Modelo de amenazas

### Qué protege

| Amenaza | Defensa |
|---|---|
| Alguien obtiene el archivo de respaldo protegido (por Drive, un chat, un correo, un pendrive) | Cifrado AES-256-GCM con clave derivada con Argon2id; sin la contraseña no se puede leer. El cifrado ocurre en el teléfono. |
| Alguien altera el archivo o cambia sus parámetros | El encabezado entra como dato autenticado: un archivo alterado, cortado o con el encabezado cambiado no se descifra y no se importa. |
| Un archivo manipulado intenta agotar la memoria | Los algoritmos y parámetros se validan contra límites **antes** de derivar la clave. |
| Otra persona mira la pantalla de Recientes o graba la pantalla | `FLAG_SECURE` (configurable). |
| Alguien mira las notificaciones en la pantalla de bloqueo | Texto genérico y visibilidad privada, salvo que se active «Mostrar detalles». |
| Quedan restos de notas ya borradas en el archivo de la base | `secure_delete` sobrescribe lo borrado y «Borrar todos los datos» compacta con `VACUUM`. |
| Android copia los datos a la nube o a otro teléfono | `allowBackup="false"` y reglas de extracción que excluyen todo. |
| Se pierde el teléfono | Respaldos propios y recordatorio para crearlos; respaldo automático opcional. |

### Qué no protege

| Riesgo | Detalle |
|---|---|
| **La base dentro del teléfono** | Es SQLite estándar, sin cifrar. La contraseña protege solo el archivo de respaldo. |
| **Un teléfono desbloqueado en manos de otra persona**, o malware en el teléfono | Fuera del alcance de Aura. |
| **Un respaldo sin contraseña** | Es JSON legible por cualquiera que lo abra. Aura lo advierte antes. |
| **La copia previa a importar** | Queda sin cifrar en el almacenamiento privado, aunque el respaldo importado tuviera contraseña (pendiente de mejorar). |
| **Una contraseña débil** | El archivo se puede atacar sin conexión probando contraseñas. El mínimo de 10 caracteres y Argon2id lo encarecen; el indicador de fortaleza es solo orientativo. |
| **Lo que ve Google** | La existencia, el tamaño y las fechas del archivo de Drive. |
| **El tamaño del archivo** | Da una idea aproximada de cuántos datos tiene. |

### Dónde queda la contraseña

- **Respaldo manual:** Aura **no guarda** la contraseña ni puede recuperarla. Si se olvida, ese respaldo no se puede abrir.
- **Respaldo automático:** para poder respaldar cada día sin pedirla, Aura **guarda la contraseña sellada (cifrada) con el Keystore de Android**, nunca en claro ni en archivos. Si el Keystore pierde la clave (por ejemplo, al borrar la app), Aura avisa y pide activar de nuevo. Los archivos ya subidos siguen abriéndose con la contraseña que eligió.

## 7. Cumplimiento y publicación (pendientes y puntos abiertos)

| Tema | Estado | Qué falta |
|---|---|---|
| **Política de privacidad** | Publicada en `https://soofiaa.github.io/Aura/privacy.html` (`docs/privacy.html`) | Revisar que describa con precisión lo del respaldo automático y la contraseña sellada (sección 6) |
| **Seguridad de datos de Google Play** | **Abierta** (Decisión 9 de HU-09) | Verificarla contra la documentación vigente de Play antes de publicar la 1.2. La interpretación de que podría no ser «recopilación» está **sin confirmar**. |
| **Declaración de exportación (EE. UU.)** | Clasificación **no determinada** en la especificación | Consulta pendiente a la autoridad correspondiente o asesoría legal; existe un inventario criptográfico que la respalda |
| **Prueba cerrada de Play** | En curso | Una cuenta personal nueva necesita prueba cerrada con testers antes de publicar |
| **Condiciones del servicio** | No existen | Decidir si hacen falta (HU-09, decisiones abiertas) |
| **Normativa de protección de datos personales** | No evaluada en este documento | Consultar la normativa aplicable en Chile con asesoría profesional, sobre todo por tratarse de datos de salud |
| **Aviso de salud** | Presente en la app y el README | Mantenerlo: «Estimación; no es un método anticonceptivo» |

## 8. Inventario de criptografía

Detalle completo en `ESPECIFICACION_v1.1.md` (sección «Inventario criptográfico y exportación»). Resumen:

- **Algoritmos:** Argon2id (RFC 9106) y AES-256-GCM, ambos estándar, de la biblioteca `cryptography` 2.9.0 en Dart puro. Sin algoritmos propios.
- **Parámetros del respaldo:** memoria 19 456 KiB, 2 iteraciones, paralelismo 1, clave de 32 bytes; sal de 16 bytes y nonce de 12 bytes, nuevos en cada respaldo y generados con `Random.secure()`.
- **Pruebas con vectores conocidos** para Argon2id y AES-GCM en `test/domain/backup_crypto_test.dart`.
- **Higiene de memoria:** la contraseña en bytes y la clave derivada se borran de memoria al usarlas (mejor esfuerzo). No hay `print`, `debugPrint` ni registros con datos (verificado en la 1.1.0).
- **La base de datos no usa cifrado** (SQLite estándar, sin SQLCipher).
