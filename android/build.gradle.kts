import com.android.build.api.variant.LibraryAndroidComponentsExtension

plugins {
    id("com.android.library") apply false
}

allprojects {
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

    // clipboard 3.0.14 still sets API 33, below its resolved AndroidX dependencies.
    if (name == "clipboard") {
        plugins.withId("com.android.library") {
            extensions.configure<LibraryAndroidComponentsExtension> {
                finalizeDsl { it.compileSdk = 36 }
            }
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
