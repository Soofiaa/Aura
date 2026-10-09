import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Firma de release: lee primero el archivo que indica la variable de
// entorno AURA_KEY_PROPERTIES (si esta definida y el archivo existe; asi
// key.properties puede vivir fuera del repo) y, si no, android/key.properties.
// Ninguno se commitea (ver android/.gitignore). Si no existe ninguno -- por
// ejemplo, recien clonado el repo -- el build NO debe fallar: cae a la firma
// de debug para que se pueda compilar y probar igual, con un aviso explicito.
val envKeystorePropertiesPath = System.getenv("AURA_KEY_PROPERTIES")
val envKeystorePropertiesFile = envKeystorePropertiesPath
    ?.takeIf { it.isNotBlank() }
    ?.let { File(it) }
if (envKeystorePropertiesFile != null && !envKeystorePropertiesFile.isFile) {
    logger.warn(
        "AVISO: AURA_KEY_PROPERTIES apunta a un archivo que no existe. " +
            "Se usa android/key.properties si existe."
    )
}
val keystorePropertiesFile = envKeystorePropertiesFile
    ?.takeIf { it.isFile }
    ?: rootProject.file("key.properties")
val hasKeystoreProperties = keystorePropertiesFile.exists()
val keystoreProperties = Properties()
if (hasKeystoreProperties) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
} else {
    logger.warn(
        "AVISO: no hay key.properties (ni AURA_KEY_PROPERTIES ni " +
            "android/key.properties). El build de release se firmara con " +
            "la key de DEBUG (no instalable en Play). Ver android/RELEASE.md " +
            "para crear el keystore de verdad."
    )
}

android {
    namespace = "com.soofiaa.aura"
    compileSdk = flutter.compileSdkVersion
    defaultConfig {
        applicationId = "com.soofiaa.aura"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["appLabel"] = "Aura"
    }
    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    signingConfigs {
        if (hasKeystoreProperties) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }
    buildTypes {
        getByName("debug") {
            isMinifyEnabled = false
            isShrinkResources = false
            // Permite tener debug y release instaladas a la vez, cada
            // una con su propio applicationId (y por lo tanto su propia
            // base de datos local): no son la misma app para Android.
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
            manifestPlaceholders["appLabel"] = "Aura (debug)"
        }
        getByName("release") {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            signingConfig = if (hasKeystoreProperties) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
    ndkVersion = "27.0.12077973"
}



flutter {
    source = "../.."
}

dependencies {
    // Requerido por flutter_local_notifications (ver
    // https://developer.android.com/studio/write/java8-support.html).
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
