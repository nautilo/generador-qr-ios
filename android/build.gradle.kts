// android/build.gradle.kts (top-level)

import org.gradle.api.file.Directory
import org.gradle.api.tasks.Delete
import org.gradle.kotlin.dsl.register

plugins {
    // 🔹 SIN versión aquí → Flutter gestiona la versión (actualmente 8.7.x)
    id("com.android.application") apply false
    id("com.android.library") apply false
    id("org.jetbrains.kotlin.android") apply false

    // 🔹 Este sí con versión
    id("com.google.gms.google-services") version "4.4.3" apply false
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// (Opcional) mantener tu reubicación de build
val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    layout.buildDirectory.value(newSubprojectBuildDir)
    evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

