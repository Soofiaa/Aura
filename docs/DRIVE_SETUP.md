# Configurar el respaldo en Google Drive (HU-09)

El respaldo automático en Google Drive necesita un **client ID de OAuth** por
aplicación. Aura no usa servidores propios: el teléfono habla directamente con
Google con el alcance `drive.file`, que solo le permite ver y escribir los
archivos que ella misma crea (una carpeta `Aura` en tu Google Drive).

Estos pasos se hacen **una sola vez**, en la consola de Google, con tu propia
cuenta de Google. Aura no incluye ni necesita ninguna clave en el código.

## 1. Crear el proyecto y habilitar la API de Drive

1. Abre <https://console.cloud.google.com/>.
2. Arriba, crea un proyecto nuevo (por ejemplo, "Aura") o elige uno existente.
3. En **API y servicios → Biblioteca**, busca **Google Drive API** y actívala.

## 2. Pantalla de consentimiento

1. En **API y servicios → Pantalla de consentimiento de OAuth**, elige tipo
   **Externo** y completa nombre, correo de soporte y política de privacidad
   (la de Aura: `https://soofiaa.github.io/Aura/privacy.html` o la que uses).
2. En **Alcances**, añade `.../auth/drive.file`
   (`https://www.googleapis.com/auth/drive.file`).
3. En **Usuarios de prueba**, añade el correo de la cuenta del teléfono donde
   vas a probar (mientras la app está en "pruebas", solo esas cuentas pueden
   iniciar sesión).

## 3. Crear los client IDs (Android)

En **Credenciales → Crear credenciales → ID de cliente de OAuth**, tipo
**Android**, necesitas **dos**:

| Para qué | Paquete | SHA-1 |
|---|---|---|
| Depurar en tu teléfono | `com.soofiaa.aura.debug` | el del keystore de depuración (abajo) |
| La app de Play | `com.soofiaa.aura` | el de tu keystore de publicación |

**SHA-1 de depuración** (tu máquina; sale solo):

```
keytool -list -v -keystore %USERPROFILE%\.android\debug.keystore -alias androiddebugkey -storepass android
```

(en macOS/Linux: `~/.android/debug.keystore`)

**SHA-1 de publicación** (tu keystore de Play; está fuera del repositorio,
como `key.properties`):

```
keytool -list -v -keystore RUTA_DE_TU_KEYSTORE -alias AURA
```

La contraseña de esa keystore no escribe en el repo: usa tu gestor de
contraseñas o `!` en OpenCode para correr el comando con ella.

Los client IDs Android **no se copian en ningún lado**: basta con que existan
en el proyecto para que Google reconozca la app.

## 3b. Crear el client ID web (el que usa la app)

En Android, `google_sign_in` 7 no usa los client IDs Android directamente:
exige el client ID de tipo **Aplicación web** del mismo proyecto (su
`serverClientId`). Sin él, conectar falla con "no se puede conectar con
Google".

En **Credenciales → Crear credenciales → ID de cliente de OAuth**, tipo
**Aplicación web**, nombre `Aura web`; no hace falta llenar orígenes ni URIs
de redirección. Es uno solo, para depurar y publicar.

## 4. Pasar el client ID web en la compilación

El client ID **nunca va en el repo**. Se pasa como definición al compilar,
con un archivo local `secrets.json` (está en `.gitignore`) en la raíz del
proyecto:

```json
{
  "DRIVE_WEB_CLIENT_ID": "PEGA_AQUI_EL_CLIENT_ID_WEB.apps.googleusercontent.com"
}
```

Y se compila con:

```
flutter run --debug --dart-define-from-file=secrets.json
```

(`flutter install` no acepta `--dart-define-from-file`: instala el último APK
compilado. Para instalar sin `flutter run`, compila antes con
`flutter build apk --debug --dart-define-from-file=secrets.json`.)

(Si lo prefieres, puedes pasarlo con
`--dart-define=DRIVE_WEB_CLIENT_ID=...`.) Si defines `secrets.json` en tu
IDE como opción de compilación, no hace falta repetir la bandera.

Si no se define ninguno, la sección de Drive en Ajustes muestra
"Configuración pendiente" y no intenta conectar: la app sigue funcionando
con normalidad.

## 5. Probar

1. `flutter run --debug --dart-define-from-file=secrets.json` en el teléfono.
2. Ajustes → Tus datos → **Respaldar automáticamente en Google Drive**.
3. Elige la cuenta (la de prueba añadida en el paso 2), pon la contraseña que
   protegerá los archivos y espera el primer respaldo: aparece la carpeta
   **Aura** en tu Google Drive con `aura_respaldo_automatico.json` (cifrado).

## Notas

- El archivo que llega a Drive está **cifrado** (AES-256-GCM) con una clave
  derivada de tu contraseña (Argon2id). Sin la contraseña no se puede abrir,
  ni siquiera desde Drive web.
- Para restaurar en otro teléfono: instalar Aura, **Importar respaldo**, elegir
  el archivo desde Drive (lo descargas con la app de Drive) y escribir la
  contraseña.
- Si usas la app en "pruebas" de Google, cada pocos días Google puede pedir
  reconfirmar; al publicarla en Play y verificarla, deja de pedirlo.
