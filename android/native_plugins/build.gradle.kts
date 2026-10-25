// This build contains only the native companion libraries and applications.
// It deliberately has no Flutter loader, :app, Rust or host asset preparation.
allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val outputRoot = layout.projectDirectory.dir("../../build/native_plugins")
layout.buildDirectory.set(outputRoot)
subprojects {
    layout.buildDirectory.set(outputRoot.dir(name))
}

tasks.register<Delete>("clean") {
    delete(outputRoot)
}
