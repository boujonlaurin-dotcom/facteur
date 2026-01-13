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
allprojects {
    repositories {
        google()
        mavenCentral()
    }
    
    // Force Kotlin version and language compatibility for ALL modules (root + plugins)
    configurations.all {
        resolutionStrategy.eachDependency {
            if (requested.group == "org.jetbrains.kotlin") {
                useVersion("1.9.24")
            }
        }
        // Force specific standard libraries which are often pinned by plugins
        resolutionStrategy.force("org.jetbrains.kotlin:kotlin-stdlib:1.9.24")
        resolutionStrategy.force("org.jetbrains.kotlin:kotlin-stdlib-jdk8:1.9.24")
        resolutionStrategy.force("org.jetbrains.kotlin:kotlin-stdlib-common:1.9.24")
        resolutionStrategy.force("org.jetbrains.kotlin:kotlin-reflect:1.9.24")
    }

    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        kotlinOptions {
            jvmTarget = "17"
            apiVersion = "1.9"
            languageVersion = "1.9"
            allWarningsAsErrors = false
            freeCompilerArgs = freeCompilerArgs + listOf("-Xjdk-release=17", "-language-version", "1.9", "-api-version", "1.9")
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
    
    afterEvaluate {
        if (project.hasProperty("android")) {
            val android = project.property("android") as com.android.build.gradle.BaseExtension
            android.compileOptions {
                sourceCompatibility = JavaVersion.VERSION_17
                targetCompatibility = JavaVersion.VERSION_17
            }
        }
        
        // Aggressively force Kotlin options for all tasks, including those from plugins
        project.tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            kotlinOptions {
                jvmTarget = "17"
                apiVersion = "1.9"
                languageVersion = "1.9"
                freeCompilerArgs = freeCompilerArgs + listOf("-Xjdk-release=17")
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
