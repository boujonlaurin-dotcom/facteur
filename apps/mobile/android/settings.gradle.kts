pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            val propertiesFile = file("local.properties")
            var path: String? = null
            if (propertiesFile.exists()) {
                propertiesFile.inputStream().use { properties.load(it) }
                path = properties.getProperty("flutter.sdk")
            }
            if (path == null) {
                path = System.getenv("FLUTTER_ROOT")
            }
            require(path != null) { "flutter.sdk not set in local.properties and FLUTTER_ROOT not found in environment" }
            path
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.7.2" apply false
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false
}

include(":app")
