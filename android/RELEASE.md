# Compilar Aura para release

## JDK: 17 o 21, nunca 25

Gradle 8.12 (el que usa este proyecto) no soporta JDK 25: falla con un
error críptico (`class file major version 68 not supported` / un
"What went wrong: 25.0.2" sin más detalle). Si tu Android Studio trae un
JBR 25 embebido (el error típico en instalaciones nuevas), necesitás
apuntar Gradle a un JDK 17-21 instalado aparte.

Formas de hacerlo:

- **Por build** (no persiste), desde `android/`:
  ```
  ./gradlew assembleRelease -Dorg.gradle.java.home="C:\Program Files\Java\jdk-17"
  ```
- **Persistente**, para que `flutter build`/`flutter run` también lo usen:
  ```
  flutter config --jdk-dir="C:\Program Files\Java\jdk-17"
  ```

## Comandos de build

| Quiero... | Comando | Resultado |
|---|---|---|
| Instalar en mi teléfono por USB | `./gradlew assembleRelease -Dorg.gradle.java.home="<ruta-jdk-17>"` (desde `android/`) o `flutter build apk --release` | `build/app/outputs/flutter-apk/app-release.apk` |
| Subir a Google Play | `flutter build appbundle --release` | `build/app/outputs/bundle/release/app-release.aab` |

**Play exige `.aab`, no `.apk`** (deja que Play arme el APK final por
dispositivo, con split de ABI — el `.apk` que generamos nosotros es un
único archivo "gordo" con todas las arquitecturas adentro, útil para
probar a mano pero no para subir a la tienda).

## Firma de release

`android/app/build.gradle.kts` busca `android/key.properties` (nunca se
commitea; ya está en `android/.gitignore`). Si no existe, el build **no
falla**: cae a la firma de debug con un aviso en el log, para que
cualquiera que clone el repo pueda compilar y probar. Para firmar de
verdad:

1. Generar el keystore (fuera del repo):
   ```
   keytool -genkey -v -keystore <ruta-fuera-del-repo>/aura-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias aura
   ```
2. Crear `android/key.properties` (NO se commitea):
   ```
   storePassword=<...>
   keyPassword=<...>
   keyAlias=aura
   storeFile=<ruta absoluta al .jks, o relativa a android/app/>
   ```
3. Guardar el `.jks` y las contraseñas en un gestor de contraseñas. Si se
   pierden, no hay forma de publicar actualizaciones bajo el mismo
   `applicationId` (`com.soofiaa.aura`) — Play exige la misma firma en
   cada actualización.

## Qué probar a mano en un release de verdad (no alcanza con debug)

`debug` compila con `isMinifyEnabled = false`; `release` corre R8 con
las reglas de `proguard-rules.pro`. Algunas cosas solo se rompen en
release:

- **Notificaciones tras reiniciar el teléfono**: programar un
  recordatorio real (o adelantar la fecha del sistema para que caiga
  pronto), reiniciar, confirmar que sigue llegando sin abrir la app
  primero.
- **Ícono y splash**: confirmar que se ven igual que en debug (R8/
  shrinkResources a veces elimina recursos que cree "no usados").
- **Tiempo de arranque en frío**: R8 + drift pueden cambiar cuánto tarda
  en abrir la primera vez.
