// android/app/build.gradle.kts
import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // El plugin de Flutter debe ir después de Android/Kotlin
    id("dev.flutter.flutter-gradle-plugin")
    // Google Services (Firebase)
    id("com.google.gms.google-services")
}



// ======== 🔐 CONFIGURACIÓN DE FIRMA ========
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.gladiator.generador_qr_flutter"

    // Usa las versiones provistas por el plugin de Flutter
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973" // Puedes usar flutter.ndkVersion si prefieres

    defaultConfig {
        applicationId = "com.gladiator.generador_qr_flutter"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = keystoreProperties["storeFile"]?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    buildTypes {
        getByName("release") {
            // ✅ Usa tu firma real para subir a Play Store
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        getByName("debug") {
            // Mantén tus ajustes de depuración
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    // Si en algún momento necesitas packagingOptions:
    // packaging {
    //     resources {
    //         excludes += "/META-INF/{AL2.0,LGPL2.1}"
    //     }
    // }
}

flutter {
    source = "../.."
}

// Nota: No declares dependencias Firebase aquí; los plugins Flutter (p.ej. firebase_messaging)
// ya agregan las nativas necesarias. Si más adelante requieres libs Android/Jetpack nativas,
// puedes agregarlas en un bloque dependencies normal:
//
// dependencies {
//     implementation("androidx.core:core-ktx:1.13.1")
// }
