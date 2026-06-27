import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing (pattern copied from tapper). Two sources, both gitignored:
//   - CI: KEYSTORE_PATH / KEYSTORE_PASSWORD / KEY_ALIAS / KEY_PASSWORD env vars.
//   - Local: android/key.properties (storeFile/storePassword/keyAlias/keyPassword).
// With neither, release falls back to the debug key so `flutter build apk
// --release` still works for local sideloading.
val keystorePropertiesFile = rootProject.file("key.properties")
val hasKeystore = keystorePropertiesFile.exists()
val keystoreProperties = Properties().apply {
    if (hasKeystore) {
        keystorePropertiesFile.inputStream().use { load(it) }
    }
}
val hasEnvSigning = System.getenv("KEYSTORE_PATH") != null

android {
    namespace = "ai.stridelabs.shed"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // The permanent Google Play package id (Stride Labs namespace). Lowercase,
        // mirroring tapper's ai.stridelabs.tapper. Distinct from the Dart package
        // name (shed_mobile) and the macOS bundle id.
        applicationId = "ai.stridelabs.shed"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasEnvSigning) {
            create("release") {
                keyAlias = System.getenv("KEY_ALIAS")
                keyPassword = System.getenv("KEY_PASSWORD")
                storeFile = file(System.getenv("KEYSTORE_PATH")!!)
                storePassword = System.getenv("KEYSTORE_PASSWORD")
            }
        } else if (hasKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Sign with the release key (env or key.properties) when available;
            // otherwise fall back to debug so local release builds still work.
            signingConfig = if (hasEnvSigning || hasKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
