import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: provide android/key.properties (storeFile, storePassword, keyAlias, keyPassword).
// Without it, release builds fall back to the debug key so local test APKs can still be produced.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

android {
    namespace = "com.efetufe.efetufe"
    compileSdk = maxOf(flutter.compileSdkVersion, 36) // flutter_secure_storage 10 compiles against 36
    // No native code of our own: no ndkVersion pin, so a full NDK download is not required to build.

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.efetufe.efetufe"
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // debug/profile builds may talk to a local HTTP dev server; release overrides this below
        manifestPlaceholders["usesCleartextTraffic"] = "true"
    }

    signingConfigs {
        if (keystoreProperties.containsKey("storeFile")) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // HTTPS only. Set ALLOW_CLEARTEXT=true when building a test APK for a plain-HTTP LAN server.
            manifestPlaceholders["usesCleartextTraffic"] =
                (System.getenv("ALLOW_CLEARTEXT") == "true").toString()
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
            // Keeps the audio player stack out of R8 optimisation (see proguard-rules.pro).
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

flutter {
    source = "../.."
}
