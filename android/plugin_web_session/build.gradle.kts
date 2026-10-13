import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

// Embedded only in LDC/CDK APKs, never in Android Core.
android {
    namespace = "com.github.lingyan000.fluxdo.plugin.web_session"
    compileSdk = 36
    defaultConfig { minSdk = 24 }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

kotlin {
    compilerOptions { jvmTarget = JvmTarget.JVM_17 }
}
