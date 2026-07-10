import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Firebase config commitée par flavor : app/src/beta (com.example.facteur.staging)
// et app/src/playstore (facteur.app). Un google-services.json Android n'est PAS un
// secret (identifiants publics + clé API restreinte) → commit assumé. Sans lui,
// Firebase natif n'embarque aucune ressource `google_app_id`, donc
// `Firebase.initializeApp()` lève une PlatformException sur CHAQUE appareil → tout
// l'enregistrement push meurt et 100 % des users retombent sur la notif locale
// (root cause « notif du jour morte depuis le 1er jour », cf.
// docs/bugs/bug-notifications-stalled.md).
val hasGoogleServices =
    file("src/beta/google-services.json").exists() ||
    file("src/playstore/google-services.json").exists() ||
    file("google-services.json").exists()

if (hasGoogleServices) {
    apply(plugin = "com.google.gms.google-services")
} else {
    // Filet anti-régression : un build release/bundle (AAB Play Store, APK stable)
    // sans google-services.json produirait une app « push mort-né ». On échoue fort
    // et tôt plutôt que de re-livrer en silence. Les builds debug/dev restent
    // tolérants (dev local sans credentials Firebase).
    val isReleaseBuild = gradle.startParameter.taskNames.any {
        it.contains("Release") || it.contains("Bundle")
    }
    if (isReleaseBuild) {
        throw GradleException(
            "google-services.json manquant — le push serait mort-né. Ajoute " +
                "apps/mobile/android/app/src/<flavor>/google-services.json " +
                "(src/beta pour com.example.facteur.staging, src/playstore pour facteur.app)."
        )
    }
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.example.facteur"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Required for flutter_local_notifications v20 (java.time API)
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.facteur"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Canal `beta` = APK side-loaded via GitHub Releases (auto-update intégré,
    // garde REQUEST_INSTALL_PACKAGES). Canal `playstore` = AAB Play Store
    // (sans cette permission, pas d'auto-update).
    flavorDimensions += "channel"

    productFlavors {
        create("beta") {
            dimension = "channel"
            // Conserve le package historique des ~60 testeurs side-load
            // (com.example.facteur.staging) -> auto-update préservé, aucune réinstall.
            applicationIdSuffix = ".staging"
            versionNameSuffix = "-beta"
        }
        create("playstore") {
            dimension = "channel"
            // Package définitif Play Store, figé au 1er upload AAB. NE PAS modifier.
            applicationId = "facteur.app"
        }
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
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
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

dependencies {
    // Required for flutter_local_notifications v20 desugaring
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
