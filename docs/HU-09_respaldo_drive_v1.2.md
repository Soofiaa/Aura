# Aura v1.2 — HU-09 · Respaldo automático en Google Drive

> **PROPUESTA para v1.2. No vigente en la v1.1. No reemplaza al RNF-1 de ESPECIFICACION_v1.1.md hasta la publicación de la 1.2.**
> Estado: propuesta para aprobación · Base: v1.1 en preparación (`main` a5c8f15, schema drift v5) · Fecha: 2026-10-14.
> Mientras la 1.2 no se publique, rigen `ESPECIFICACION_v1.1.md` y su RNF-1 (el APK de release no declara `INTERNET`).

## 1. Contexto y objetivo

Hasta la 1.1, Aura no tiene el permiso `INTERNET` y los datos solo salen del teléfono con un respaldo manual (HU-06, HU-06b) y
su recordatorio (HU-08). Sin un respaldo reciente, perder o cambiar el teléfono es perder los registros. La decisión D-7 de la
especificación de la 1.1 dejó abierto si Aura debía respaldar sola.

**Objetivo de la HU-09:** que los registros se respalden solos, cifrados, en la cuenta de Google Drive de la propia usuaria, sin
que tenga que acordarse ni elegir carpetas, y que pueda restaurarlos en un teléfono nuevo con su contraseña.

**Qué cambia en la promesa de privacidad.** La HU-09 agrega una conexión opcional y **desactivada por defecto**, únicamente con
Google Drive. Con ella activada, Aura sube a la cuenta de la usuaria un archivo que solo ella puede abrir; Google ve que el
archivo existe, su tamaño y sus fechas, pero no su contenido. El APK de la 1.2 declara `INTERNET` (ver RNF-1 v1.2). Los textos
que hoy dicen "sin internet" se actualizan al publicar la 1.2, no antes.

**Alternativa descartada.** Un respaldo automático a una carpeta elegida con el selector del sistema (sin `INTERNET`) se analizó
y quedó archivado: la raíz de Drive no se puede elegir como carpeta, la usuaria tendría que crear y mantener carpetas, y no se
puede prometer que otra app sincronice.

## 2. Historia de usuario

### HU-09 · Respaldo automático en Google Drive
**Como** usuaria de Aura **quiero** que mis datos se respalden solos y cifrados en mi propia cuenta de Google Drive **para** no
perder mis registros si pierdo o cambio el teléfono, sin tener que acordarme de crear un respaldo.

**Estado:** propuesta para la 1.2. Pendiente de las decisiones abiertas de la sección 7. La evidencia técnica que la respalda
está en la sección 8.

**Criterios de aceptación**
1. **Desactivado por defecto.** Con el respaldo en Drive desactivado, Aura no inicia ninguna conexión de red.
2. **Activación explícita.** En *Ajustes → Tus datos → Respaldo en Google Drive*, al activarlo Aura muestra primero una pantalla
   propia que explica qué se sube (un archivo cifrado con todos los registros y ajustes), que Google ve que el archivo existe,
   su tamaño y sus fechas pero no su contenido, y que sin la contraseña nadie puede abrirlo (tampoco Aura). Solo con una acción
   afirmativa ("Activar") se continúa. Salir o volver atrás no activa nada.
3. **Contraseña obligatoria.** Después de la pantalla, la usuaria crea una contraseña: **mínimo 12 caracteres; se recomienda una
   frase de varias palabras**. Se escribe dos veces, con el aviso de que Aura no puede recuperarla. **El automático nunca sube
   un archivo sin cifrar.** **Orden de activación (fijo):** 1) contraseña → 2) derivar `K` (Argon2id 64 MiB) → 3) guardar `K` en
   el Keystore → 4) autorizar con Google → 5) primer respaldo verificado → 6) marcar "activado". La contraseña es el paso 1 y la
   derivación de `K` el paso 2, **antes** de pedir nada a Google.
4. **Autorización de Google.** Aura pide a Google solo el acceso a su carpeta privada de la app (`drive.appdata`) y al correo de
   la cuenta (para mostrarla). La usuaria elige la cuenta en el diálogo de Google. Es el **paso 4** del orden de activación:
   solo se llega aquí con `K` ya derivada y guardada. Si la usuaria cancela el diálogo de Google, se borra `K` del Keystore y no
   queda nada activado.
5. **Primer respaldo.** Al terminar la activación se hace un primer respaldo y se informa el resultado.
6. **Cuándo respalda.** Al abrir Aura (o al volver a primer plano), si el último respaldo automático correcto es de **un día
   anterior** (frecuencia diaria) **y** los datos cambiaron desde entonces (huella HMAC distinta). Sin cambios, no sube nada.
   Además, **"Respaldar ahora"** hace uno en el momento aunque no haya cambios.
7. **Cifrado.** Formato v2 actual (`formatVersion` 2, AES-256-GCM, Argon2id), con una sal fija del automático y un nonce nuevo
   por archivo, y Argon2id reforzado: **m = 65 536 KiB, t = 3, p = 1** (entra en los límites que ya valida el formato v2:
   memoria de 8 192 a 65 536 KiB, iteraciones de 1 a 10, paralelismo 1). La clave derivada se guarda envuelta por el Keystore de
   Android; la contraseña no se guarda. El respaldo manual sigue con los parámetros de producción (m = 19 456 KiB, t = 2,
   p = 1).
8. **Verificación antes de rotar.** Cada respaldo se sube como un archivo **nuevo**, se vuelve a descargar y se descifra con la
   clave hasta obtener exactamente el documento exportado. Solo entonces se borran los más antiguos, conservando los **últimos
   7** verificados. Nunca se sobrescribe ni se borra un respaldo sin haber verificado el nuevo (ver R-2).
9. **Estado visible.** En *Tus datos* se ven la cuenta, la fecha del último respaldo correcto o el último error, la frecuencia,
   "Respaldar ahora", "Restaurar desde Google Drive", "Cambiar contraseña" y "Desconectar".
10. **Fallos.** Sin red: queda pendiente y se reintenta en la próxima apertura. Acceso vencido o revocado (401 o autorización
    que ya no vale): ver **criterio 20** (estado "pausado"). Drive lleno, o pendiente desde hace más de 2 días: tarjeta en
    Inicio, sin notificación, con la acción para resolverlo. Nunca se muestran datos de salud ni la contraseña en los mensajes.
11. **Recordatorio (HU-08).** Un respaldo automático correcto cuenta como respaldo para el recordatorio.
12. **Restaurar en otro teléfono.** *Restaurar desde Google Drive*: elegir cuenta, ver la lista de **todos** los respaldos
    automáticos de Aura en esa cuenta (fecha y hora; los de este teléfono marcados como "este teléfono" y los demás como "otro
    teléfono"), elegir uno, escribir la contraseña y seguir el flujo de importación actual (confirmación con recuentos, copia
    previa y "Deshacer").
13. **Cambiar contraseña.** Deriva una clave nueva. Los respaldos anteriores siguen abriéndose con la contraseña anterior, y la
    interfaz lo dice.
14. **Desconectar.** Revoca el acceso de Aura a Google, borra la clave y el estado del automático, y pregunta (casilla
    desmarcada) si borrar también los respaldos de Drive. Si `revokeAccess` falla (por ejemplo, porque el acceso ya fue revocado
    desde la cuenta de Google; ver **criterio 20** y la sección 8, hallazgo 6), se limpia el token viejo con `clearToken` y la
    desconexión local termina igual, sin bloquear. Si el automático está **"pausado"** (**criterio 20**), borrar también los
    respaldos de Drive exige volver a autorizar. Si la usuaria no lo hace, se desconecta solo lo local y se informa, igual que
    en el criterio 15.
15. **Borrar todos los datos.** Además de lo actual, borra la clave y el estado del automático, revoca el acceso y ofrece una
    casilla, **desmarcada**, para borrar también los respaldos en Drive. La casilla dice cuántos son y que incluye los de otros
    teléfonos con la misma cuenta. Si no hay red, informa cuántos quedaron y cómo borrarlos desde Drive (*Administrar apps*). Si
    el automático estaba "pausado" (**criterio 20**) o `revokeAccess` falla, se limpia el token viejo y el borrado local termina
    igual. Para borrar los respaldos de Drive en ese estado hace falta volver a autorizar; si la usuaria no lo hace, se informa
    como en el caso sin red.
16. **Sin Google Play services.** La opción aparece como "No disponible en este teléfono"; el respaldo manual sigue igual.
17. **Clave invalidada.** Si `K` no se puede leer del Keystore (clave borrada o invalidada por el sistema), el automático queda
    **desactivado** (sin reintentos ni subidas) y Aura muestra la tarjeta **"Vuelve a activar el respaldo automático"**, que
    lleva a la activación (nueva contraseña o la misma). Los respaldos ya subidos **siguen abriéndose con su contraseña**: el
    archivo trae la sal y los parámetros en el encabezado.
18. **Memoria insuficiente al activar.** Si derivar Argon2id con 64 MiB falla al activar (error de memoria del isolate), Aura
    muestra un mensaje claro ("Este teléfono no tiene memoria suficiente para activar el respaldo automático ahora. Cierra otras
    apps y vuelve a intentarlo.") y **no queda nada activado a medias**. La derivación es el **paso 2**, así que cuando falla
    todavía no se guardó `K`, no se creó el estado y **no se pidió autorización a Google: no hay nada que revocar**. El respaldo
    manual sigue igual (Argon2id de producción, 19 MiB). **Orden de activación (fijo):** 1) contraseña → 2) derivar `K`
    (Argon2id 64 MiB) → 3) guardar `K` en el Keystore → 4) autorizar con Google → 5) primer respaldo verificado → 6) marcar
    "activado". Si falla cualquier paso posterior, se deshacen solo los anteriores: tras el 3, se borra `K`; tras el 4, se borra
    `K` y se revoca; tras el 5, se borra `K`, se revoca y se borra el archivo subido si llegó a existir. Si el sistema cierra la
    app a mitad de camino (sin poder mostrar el mensaje), al abrirla de nuevo una marca "activación en curso" se detecta, se
    limpia lo parcial y se informa que la activación no terminó.
19. **Varios teléfonos con la misma cuenta.** Cada instalación con el automático activado tiene un **identificador aleatorio
    corto** (ver sección 3). Cada teléfono **solo rota sus propios archivos**. La lista de restauración muestra los de todos.
20. **Acceso de Google revocado o vencido (estado "pausado").**
    - **Disparador:** un **401** de Drive (`authError`) o de `userinfo` (`invalid_request`), o una autorización que ya no es
      válida (por ejemplo, `authorize()` devuelve un token que Google rechaza; sección 8, hallazgo 6).
    - **Primera respuesta, sin molestar:** Aura limpia el token viejo (`clearToken`) y vuelve a pedir la autorización. Si Google
      entrega un token válido sin mostrar nada, el respaldo sigue normalmente.
    - **Si Google necesita mostrar su diálogo y la app está en segundo plano:** no se muestra nada. El automático queda en
      estado **"pausado"** y, la próxima vez que se abra Aura, aparece en Inicio la tarjeta **"Vuelve a conectar tu cuenta de
      Google"** (sin notificación).
    - **Regla (opción A, decidida):** si el respaldo lo inició la **apertura automática** y no la usuaria, **nunca se abre el
      diálogo de Google por sorpresa**, aunque la app esté en primer plano: se muestra la tarjeta **"Vuelve a conectar tu cuenta
      de Google"**. **Solo "Respaldar ahora"** (acción de la usuaria) abre el diálogo directamente.
    - **La tarjeta lleva solo a la autorización de Google.** **No pide contraseña ni vuelve a derivar**: la clave `K` guardada
      en el Keystore sigue siendo válida.
    - **Mientras está pausado:** no se intenta subir y no se pierde ni se rota ningún respaldo anterior. *Tus datos* muestra
      "Pausado: vuelve a conectar tu cuenta de Google". **Al reconectar**, se hace un respaldo verificado como siempre (subir →
      descargar y descifrar con `K` → rotar), si hubo cambios o si lo pidió la usuaria.
    - **Distinción con el criterio 17:** en el 17 se **perdió `K`** (estado **"desactivado"**: hay que volver a activar y la
      contraseña se pide). En el 20, **`K` sigue intacta** (estado **"pausado"**: solo se reconecta Google y la contraseña
      **no** se pide).
    - **Test:** con una pasarela de Drive falsa que responde **401** (un caso con `authError` en una llamada a Drive y otro con
      `invalid_request` en `userinfo`) y un canal de autorización falso, se comprueba que:
      1. se llama a `clearToken` con el token rechazado, una sola vez;
      2. se vuelve a pedir la autorización;
      3. si el canal falso responde "requiere diálogo" con la app en segundo plano, el estado queda **"pausado"**, no se llama a
         `subir` ni a `borrar` y, al simular la siguiente apertura, Inicio muestra la tarjeta "Vuelve a conectar tu cuenta de
         Google";
      4. al tocar la tarjeta y autorizar, **no se muestra el diálogo de contraseña ni se llama a la derivación de Argon2id**, y
         el almacén de claves falso registra que `K` **no** se leyó para reescribir ni se borró (solo lecturas para cifrar);
      5. después de reconectar, se hace un respaldo verificado y los archivos anteriores siguen todos;
      6. si el canal falso entrega un token válido sin diálogo, no aparece ninguna tarjeta y el respaldo sigue;
      7. **regla de la opción A:** con un respaldo iniciado por la **apertura automática** (app en primer plano) y un canal
         falso que responde "requiere diálogo", **no se llama** a la apertura del diálogo de Google y se muestra la tarjeta. Con
         el mismo canal falso y **"Respaldar ahora"**, **sí se llama** a la apertura del diálogo.

**Datos:** sin migración ni cambio de schema (la base sigue en v5 y `currentBackupSchemaVersion` en 5); el formato del archivo
es el v2 actual. El estado del automático va en `respaldo_automatico.json`, junto a `recordatorio_respaldo.json` en el
almacenamiento privado (ver RNF-11 y R-3).

## 3. Diseño para varios teléfonos con la misma cuenta

Los clientes OAuth de un mismo proyecto de Google Cloud comparten la carpeta `appDataFolder` (sección 8, hallazgo 3): la debug y
la release de Aura, y dos teléfonos de la misma cuenta, ven los mismos archivos.

- **Diseño:** al activar el automático se genera un identificador de instalación de 8 caracteres en base32 (`Random.secure()`,
  40 bits) que se guarda en `respaldo_automatico.json` (nunca en el JSON exportable). Nombre de archivo:
  `aura_auto_<id>_AAAA-MM-DD_HHMMSS.json`. La rotación filtra por el prefijo `aura_auto_<id>_` y conserva los últimos 7 **de esa
  instalación**. La restauración lista todos los `aura_auto_*` y marca "este teléfono" los del propio identificador.
- **A favor:**
  - Un teléfono nunca borra los respaldos de otro. Sin esto, dos teléfonos rotando sobre los mismos 7 se borrarían mutuamente, y
    el respaldo más útil (el del teléfono con más datos) podría desaparecer.
  - La restauración es clara: se ve de qué teléfono es cada respaldo y se puede elegir el correcto (por ejemplo, el del teléfono
    perdido).
  - El identificador es aleatorio: no revela modelo, número ni nada del aparato.
- **En contra:**
  - Los archivos de una instalación **abandonada** (teléfono perdido, app reinstalada, "Borrar todos los datos" sin marcar la
    casilla) **no se rotan nunca**: quedan hasta 7 por cada instalación vieja. Pesan pocos KB, pero se acumulan en la lista de
    restauración. Mitigación: en la lista, una acción "Borrar respaldos de otros teléfonos" (con confirmación), o mostrar solo
    los 7 más recientes de cada instalación y agrupar por fecha.
  - Reinstalar Aura genera un identificador nuevo: los respaldos del mismo teléfono anteriores a la reinstalación aparecen como
    "otro teléfono".
  - Un poco más de lógica y de tests (filtrado por prefijo, agrupación en la lista).
- **Alternativa descartada:** declararlo como limitación ("pensado para un teléfono por cuenta"). Es más simple, pero el fallo
  es silencioso y puede costar datos, justo lo que el automático debe evitar.

## 4. Requisitos no funcionales (v1.2)

Los RNF-1 a RNF-6 de `ESPECIFICACION_v1.1.md` siguen vigentes. Con la 1.2, el RNF-1 se reemplaza por el **RNF-1 v1.2**; los
RNF-2 a RNF-6 no cambian. Se agregan RNF-7 a RNF-11.

| ID | Requisito |
|---|---|
| RNF-1 v1.2 | **Permisos (reemplaza al RNF-1 de la 1.1 al publicar la 1.2):** el manifest fusionado del release declara **exactamente** los permisos de la lista permitida: `POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED`, `VIBRATE`, `INTERNET` y `com.soofiaa.aura.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`. Cualquier otro hace fallar la verificación del release (script de lista permitida sobre el manifest fusionado + `aapt2` sobre el APK). `allowBackup="false"`. |
| RNF-7 | **Red mínima:** el único código con red es la pasarela de Drive: un solo módulo, con destino exclusivo `www.googleapis.com` por HTTPS. Sin SDK de terceros, sin analítica y sin telemetría. |
| RNF-8 | **Nunca en claro:** ningún dato de la usuaria sale del teléfono sin cifrar. La pasarela solo acepta bytes ya cifrados (formato v2) y se verifica con tests (R-1). |
| RNF-9 | **Credenciales:** no se guardan tokens de actualización en el teléfono; los tokens de acceso los gestiona Google Play services. La contraseña nunca se guarda. La clave derivada se guarda solo envuelta por el Keystore. El correo de la cuenta se guarda solo en el teléfono, fuera de la base y del respaldo exportable. |
| RNF-10 | **Alcance mínimo:** solo `drive.appdata`, `userinfo.email` y `openid`. Agregar otro alcance es una decisión nueva. |
| RNF-11 | **Estado fuera del respaldo:** el estado del automático (cuenta, fechas, resultado, huella HMAC) vive en `respaldo_automatico.json` del almacenamiento privado, no en `AppSettings` ni en el JSON exportable, y "Borrar todos los datos" lo elimina (R-3). |

## 5. Reglas duras

Cada una tiene un test que falla si se rompe.

- **R-1 · Nunca sin contraseña ni sin cifrar.** El automático no se puede activar sin contraseña, y la pasarela de Drive no
  tiene ningún método que acepte texto o un documento v1. Su `subir` solo recibe un tipo `RespaldoCifrado` que únicamente
  construye la función de cifrado con `K` (formato v2).
  - *Test de caminos:* con una pasarela falsa que registra los bytes, se recorren **todos** los caminos que suben (primer
    respaldo al activar, apertura de la app, volver a primer plano, "Respaldar ahora", reintento tras fallo). En cada subida se
    comprueba que `parseEncryptedBackup` acepta los bytes (`formatVersion` 2), que `decodeBackup` devuelve
    `BackupNeedsPassword`, y que **no** aparece en los bytes ningún valor reconocible del documento en claro (un marcador
    sembrado en notas, una fecha, `"dailyLogs"`, `"aura-backup"` con `formatVersion` 1). Falla si algún camino sube algo que no
    cumpla.
  - *Test sin clave:* sin `K` guardada (automático sin activar, tras "Desconectar" o tras "Borrar todos los datos"), ningún
    camino llama a `subir`.
  - *Test de un solo módulo de red (Dart):* un test recorre `lib/` y falla si algún archivo distinto de la pasarela de Drive usa
    `HttpClient`, `Socket`, `RawSocket`, `WebSocket`, `HttpServer` o importa `package:http`, `package:dio`,
    `package:web_socket_channel` o similares.
  - *Test del código Kotlin del canal de autorización:* el mismo test recorre `android/app/src/main/kotlin/` (hoy no existe
    código Kotlin propio: es la primera vez que lo habrá) y falla si aparece `java.net.`, `HttpURLConnection`, `URL(`, `Socket`,
    `okhttp3`, `retrofit`, `Volley` o `ktor`. El canal solo puede usar `com.google.android.gms.auth.api.identity` (autorizar,
    `clearToken`, `revokeAccess`), `com.google.android.gms.auth.GoogleAuthUtil` (`clearToken`, la salida probada en la sección
    8, hallazgo 6) y el Keystore; nunca abre conexiones propias. **Las cadenas prohibidas no deben coincidir con esos usos
    permitidos:** se buscan como importaciones o identificadores completos (por ejemplo `import java.net.` o `\bSocket\b`), no
    como subcadenas sueltas, y el test incluye un caso que comprueba que un archivo con
    `import com.google.android.gms.auth.GoogleAuthUtil` y `import com.google.android.gms.auth.api.identity.*` **pasa**.
  - *Test de dependencias (`pubspec.lock`):* el lock tiene hoy 122 paquetes, entre ellos `web_socket` y `web_socket_channel`
    como dependencias **transitivas** (no los usa la app, pero aparecen), así que una lista prohibida fallaría desde el primer
    día. Se propone una **lista permitida versionada** (`tool/paquetes_permitidos.txt`) con los nombres actuales: el test falla
    si `pubspec.lock` incorpora **cualquier** paquete nuevo que no esté en la lista, y la lista solo cambia con una decisión
    explícita. Complemento en el script de release: `flutter pub deps --no-dev --style=list` para revisar los paquetes que
    realmente entran en la app.
- **R-2 · Nombre nuevo, verificación y después rotación.** Cada respaldo se sube con un nombre que no existe en la lista
  (`aura_auto_<id>_AAAA-MM-DD_HHMMSS.json`; si choca, se agrega un sufijo). Después se descarga y se descifra con `K` hasta
  obtener exactamente el documento. **Solo después** se borran los que excedan los últimos 7 verificados. La pasarela **no
  tiene** método de sobrescritura (`PATCH`/`update` de contenido).
  - *Test de orden:* con la pasarela falsa se comprueba la secuencia `subir` → `descargar` → (verificación correcta) → `borrar`
    de los sobrantes. Si la verificación falla (bytes alterados por la pasarela falsa), no se llama a `borrar`, el estado queda
    en "verificación fallida" y los 7 anteriores siguen.
  - *Test de retención:* con 9 archivos verificados, quedan los 7 más recientes. Los archivos que no siguen el patrón de nombre
    de Aura nunca se borran.
  - *Test de nombre:* dos respaldos en el mismo segundo producen nombres distintos; nunca se reutiliza un nombre existente. El
    nombre lleva el identificador de instalación (criterio 19), y la rotación solo considera los archivos con ese prefijo: un
    test con archivos de otra instalación comprueba que no se tocan.
  - *Fallo al borrar un viejo:* si `borrar` falla para un archivo sobrante (red, 5xx, 404), el respaldo nuevo **igual cuenta
    como correcto** (estado "ok", fecha actualizada, cuenta para HU-08) y los sobrantes quedan anotados como "por borrar" en el
    estado. Se reintentan en el próximo respaldo correcto, o al abrir la app si hay red. Test: la pasarela falsa falla un
    `borrar`; el estado queda "ok" con un pendiente de borrado, y en la siguiente ejecución se vuelve a intentar y desaparece.
    Un 404 al reintentar cuenta como borrado.
- **R-3 · Estado fuera del JSON exportable.** El estado del automático (cuenta, fechas, resultado, huella HMAC, sal y
  parámetros) vive en `respaldo_automatico.json` del almacenamiento privado, junto a `recordatorio_respaldo.json`
  (`lib/data/backup/backup_reminder_store.dart`), nunca en `AppSettings` (`lib/data/database/app_database.dart`) ni en lo que
  escribe `encodeBackup` (`lib/domain/backup_codec.dart`).
  - *Test:* el JSON exportado **antes** y **después** de activar el automático, subir y registrar estado es idéntico salvo
    `exportedAt`. Además, el texto exportado no contiene el correo de la cuenta, la huella ni la palabra `automatico`.
  - *Test de borrado:* "Borrar todos los datos" elimina `respaldo_automatico.json` (y su `.tmp`) y la clave del Keystore (con un
    almacén falso).

## 6. Fuera de alcance (v1.2)

- Ejecución en segundo plano sin abrir la app (WorkManager).
- Respaldo automático a una carpeta local elegida con el selector del sistema.
- Otros proveedores de nube.
- Una versión sin `INTERNET` (flavors o app separada).

## 7. Decisiones abiertas

| # | Pregunta | Evidencia y opciones | Estado |
|---|---|---|---|
| **Decisión 6** | ¿En qué dominio van la página principal y la política de privacidad que muestra la pantalla de consentimiento de Google? | La consola aceptó `soofiaa.github.io` y `github.com` como dominios autorizados para guardar la información de marca, y exige que estén **todos** los dominios de los enlaces (sección 8, hallazgo 9). La raíz del sitio de GitHub Pages del proyecto da 404 (no hay `index.html` en `docs/`), por eso como página principal se usó la del repositorio en GitHub. En producción, con alcances solo no sensibles y sin dominio verificado ni logo, una cuenta ajena autorizó **sin** la advertencia de "app no verificada" (hallazgo 8). Opciones: dejar la página principal en GitHub; agregar un `index.html` en `docs/` (cambio del sitio que sirve la política); o un dominio propio. No se hizo la verificación en Search Console ni la verificación de marca. | Abierta |
| **Decisión 9** | ¿Qué se declara en el formulario de Seguridad de datos de Play? | **Interpretación sin confirmar, no un hecho:** como el archivo va siempre cifrado con la contraseña de la usuaria, a su propia cuenta, y la desarrolladora no puede leerlo, podría encajar en la exención de cifrado de extremo a extremo y en la pregunta frecuente de Play sobre subidas a la propia cuenta de Drive; la ayuda de Play (respuesta a esa pregunta frecuente) empieza con "It depends on the particular implementation." (Play Console Help, artículo 10787469). **Debe verificarse contra la documentación vigente de Google Play antes de completar el formulario de Seguridad de datos de la v1.2.** Opciones: mantener "no se recopilan datos" documentando el razonamiento, o declarar "Información de salud, opcional, cifrada en tránsito". | Abierta; se decide antes de publicar |
| **Recuadro azul del consentimiento** | ¿Qué provoca el recuadro informativo sobre vínculos a la Política de Privacidad o a las Condiciones del Servicio que aparece en el diálogo de Google, y desaparece al completar algo? | Observado en producción con una cuenta ajena (hallazgo 8). Causa no confirmada: falta de Condiciones del Servicio, marca sin verificar o enlaces en `github.com`. | Abierta |
| **Condiciones del Servicio** | ¿Hacen falta, dónde se publican y su ausencia causa el recuadro? | Aura no tiene Condiciones del Servicio. | Abierta |

## 8. Evidencia técnica

### Prueba de humo (2026-10-14)

App Android desechable, aparte de Aura (otro `applicationId`, otro proyecto de Google Cloud), con solo el permiso `INTERNET` y
una única dependencia (`play-services-auth` 22.0.0): autorización con `AuthorizationClient` y HTTP directo a la API REST de
Drive v3. Dos variantes firmadas con claves distintas (la de debug y una desechable). Probada en un POCO X6 Pro. Ni el
repositorio ni el proyecto real se tocaron, y el proyecto de prueba ya se cerró.

1. **Autorización sin cliente web.** Con clientes Android (paquete + SHA-1) basta: las dos variantes obtuvieron token sin
   cliente web. Alcances concedidos: `drive.appdata`, `userinfo.email`, `email` y `openid`.
2. **Drive API.** Sin habilitarla en el proyecto, la subida responde `HTTP 403 accessNotConfigured`.
3. **`appDataFolder` es del proyecto.** La variante con otra firma y otro cliente listó y descargó el archivo subido por la
   primera, con el mismo SHA-256. Debug, release y la firma de Play comparten respaldos si están en el mismo proyecto.
4. **Ciclo completo correcto.** Subir (multipart) → listar → descargar → comparar SHA-256 → borrar (HTTP 204, sin papelera). Dos
   archivos convivieron sin pisarse.
5. **Sin internet.** `UnknownHostException` capturada, sin cierre ni congelamiento.
6. **Revocación desde la cuenta de Google.** `authorize()` respondió "acceso ya concedido" con un token viejo que Google rechaza
   (401 `invalid_request` en `userinfo`, `authError` en Drive), y `revokeAccess` falló con `ApiException 8: [28404]`
   (significado no confirmado). **Salida probada:** `GoogleAuthUtil.clearToken` sobre el token viejo y volver a autorizar;
   entonces sí se abre el diálogo de Google. Base del criterio 20.
7. **El respaldo sobrevivió a la revocación**, desde la cuenta y con `revokeAccess`: al volver a autorizar, el archivo seguía.
   Es observación, no garantía documentada.
8. **Producción sin advertencia.** Con el proyecto publicado (solo alcances no sensibles, sin logo), una cuenta ajena a la lista
   de prueba autorizó sin la pantalla de "app no verificada". Apareció un recuadro informativo sobre vínculos a la Política de
   Privacidad o a las Condiciones del Servicio (causa no confirmada).
9. **Información de marca.** Hay que agregar a los dominios autorizados el dominio de cada enlace (`soofiaa.github.io` y
   `github.com`).
10. **Errores pasajeros y cancelación.** Un error 500 de Google al elegir la cuenta se resolvió al reintentar. La cancelación
    del diálogo llega como `resultCode=0`.

### Medición de Argon2id (2026-10-14)

POCO X6 Pro, Android 16, **modo profile**, en una app de medición aparte. Misma función (`deriveBackupKey`) y mismo aislamiento
(`Isolate.run`) que la app; solo la derivación; 1 calentamiento y 10 medidas por juego de parámetros, en dos corridas.
Desenchufado, en reposo, ahorro de batería desactivado y temperatura normal; batería al 18–19 % (no se cumplió la condición de
"sobre 20 %").

| Parámetros | Mediana | Rango (mín–máx) | Pico de memoria del proceso |
|---|---|---|---|
| Producción (19 456 KiB, t 2) | ~172–189 ms | 155–236 ms | +24 a 29 MiB |
| Automático (65 536 KiB, t 3) | **~0,97–1,0 s** | 0,95–1,06 s | **+70 a 100 MiB** |

- Arrancar el isolate agrega 1–3 ms. El automático cuesta ~5,2 a 5,8 veces la producción.
- ~1 s se paga solo al activar el automático y al restaurar con la contraseña, nunca en cada respaldo.
- **Gama baja: sin medir.** No hubo un teléfono de gama baja disponible. Es el caso que importa para el criterio 18 y para
  restaurar en un teléfono modesto.

## 9. Lista de verificación de Google Cloud

Configuración del proyecto real antes de implementar (CP0). Los puntos marcados **(prueba de humo)** se agregaron o cambiaron
por la evidencia de la sección 8.

1. Crear un único proyecto para Aura.
2. **Habilitar la Google Drive API (prueba de humo, hallazgo 2):** obligatorio; sin ella, `403 accessNotConfigured`.
3. Pantalla de consentimiento: público **External**; nombre de la app y correo de soporte; **sin logo** (mostrarlo exige
   verificación de marca); alcances solo `drive.appdata`, `userinfo.email` y `openid` (sin alcances sensibles ni restringidos).
4. **Dominios autorizados: el de cada enlace de la marca (prueba de humo, hallazgo 9).** Si la página principal queda en GitHub,
   también `github.com`. Se completa después de cerrar la decisión 6.
5. **Clientes Android, todos en el mismo proyecto (prueba de humo, hallazgo 3):** `com.soofiaa.aura.debug` con la SHA-1 de la
   clave de debug; `com.soofiaa.aura` con la SHA-1 de la clave de release local; y, cuando exista la primera subida a Play,
   `com.soofiaa.aura` con la SHA-1 de la clave de firma de Play App Signing si es distinta. **Sin cliente web** (hallazgo 1).
6. Mientras el estado sea **Testing**, la autorización caduca a los 7 días. Para uso real, **publicar en producción** (Audience
   → Publish app), con la decisión 6 resuelta.
