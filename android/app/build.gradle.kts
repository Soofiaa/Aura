plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.soofiaa.aura"
    compileSdk = flutter.compileSdkVersion
    defaultConfig {
        applicationId = "com.soofiaa.aura"
        minSdk = flutter.minSdkVersion
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
    }
    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    buildTypes {
        getByName("debug") {
            isMinifyEnabled = false
            isShrinkResources = false
        }
        getByName("release") {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
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
