allprojects {
    ext.set("kotlin_version", "1.9.24")
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

subprojects {
    configurations.all {
        resolutionStrategy.eachDependency {
            if (requested.group == "org.jetbrains.kotlin") {
                useVersion("1.9.24")
            }
        }
    }

    // Force language version for ALL Kotlin compilation tasks (aggressive)
    afterEvaluate {
        tasks.matching { it.name.contains("Compile") && it.name.contains("Kotlin") }.configureEach {
            try {
                // Use reflection-like access or dynamic property to avoid compile-time issues
                // but since it's a .kts file, we can try the standard way with a safety check
                (this as? org.jetbrains.kotlin.gradle.tasks.KotlinCompile)?.kotlinOptions {
                    jvmTarget = "17"
                    apiVersion = "1.9"
                    languageVersion = "1.9"
                    allWarningsAsErrors = false
                }
            } catch (e: Exception) {
                // Ignore tasks that don't support these options
            }
        }
    }

    afterEvaluate {
        if (project.hasProperty("android")) {
            val android = project.property("android") as com.android.build.gradle.BaseExtension
            android.compileOptions {
                sourceCompatibility = JavaVersion.VERSION_17
                targetCompatibility = JavaVersion.VERSION_17
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
