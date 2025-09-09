import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // Flutter plugin must come after Android/Kotlin
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.carlostechops.mindbreath"

    // *** Explicitly set compileSdk instead of relying on flutter.*
    compileSdk = 35
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.carlostechops.mindbreath"

        // *** Explicitly set min/targetSdk
        minSdk = 21
        targetSdk = 35

        // *** Tie versioning to pubspec.yaml (e.g. version: 1.0.1+2)
        // Flutter automatically maps "1.0.1+2" → versionName=1.0.1, versionCode=2
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // --- Read keystore from android/app/key.properties
    val keystoreProperties = Properties()
    val keystorePropertiesFile = file("key.properties") // <-- android/app/key.properties
    if (keystorePropertiesFile.exists()) {
        keystoreProperties.load(FileInputStream(keystorePropertiesFile))
    }

    signingConfigs {
        // *** Only create release config if the keystore file exists
        if (keystorePropertiesFile.exists()) {
            create("release") {
                val storePath = keystoreProperties.getProperty("storeFile")
                if (storePath != null) {
                    storeFile = file(storePath)
                    storePassword = keystoreProperties.getProperty("storePassword")
                    keyAlias = keystoreProperties.getProperty("keyAlias")
                    keyPassword = keystoreProperties.getProperty("keyPassword")
                }
            }
        }
    }

    buildTypes {
        release {
            // *** Only apply signing if release config exists
            if (keystorePropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            }

            // Keep these off for now; you can enable later if you want smaller bundles.
            isMinifyEnabled = false
            isShrinkResources = false

            // *** If you enable minify later, add ProGuard:
            // proguardFiles(
            //     getDefaultProguardFile("proguard-android-optimize.txt"),
            //     "proguard-rules.pro"
            // )
        }
        debug {
            // no release signing here
        }
    }
}

flutter {
    source = "../.."
}
