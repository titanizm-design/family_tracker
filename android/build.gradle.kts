plugins {
    id("com.android.application")
    id("kotlin-android")
    // Плагин Flutter должен быть применён после Android и Kotlin плагинов
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.family_tracker"
    compileSdk = 34
    ndkVersion = "27.0.12077973"

    compileOptions {
        // ВАЖНО: Включаем дешугаринг для работы flutter_local_notifications
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.example.family_tracker"
        minSdk = 21
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
    }

    buildTypes {
        release {
            // Временно используем отладочную подпись для сборки release
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // ВАЖНО: Библиотека для дешугаринга
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}