import java.io.File
import java.util.Properties
import org.jetbrains.kotlin.gradle.dsl.JvmTarget


plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

val keyFile = rootProject.file("key.properties")
val keys = Properties().apply {
    if (keyFile.exists()) keyFile.inputStream().use { load(it) }
}
val keyStore = keys.getProperty("storeFile")?.trim()?.takeIf { it.isNotEmpty() }?.let { path ->
    val raw = File(path)
    if (raw.isAbsolute) raw else listOf(file(path), rootProject.file(path))
        .firstOrNull { it.exists() } ?: rootProject.file(path)
}
val signed = listOf("keyAlias", "keyPassword", "storePassword")
    .all { !keys.getProperty(it).isNullOrBlank() } && keyStore?.isFile == true


android {
    namespace = "com.github.lingyan000.fluxdo.plugin.deviceinfo"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.github.lingyan000.fluxdo.plugin.deviceinfo"
        minSdk = 24
        targetSdk = 35
        versionCode = providers.gradleProperty("pluginVersionCode").orNull?.toIntOrNull() ?: 1
        versionName = providers.gradleProperty("pluginVersionName").orNull ?: "0.1.0"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    signingConfigs {
        if (signed) create("pluginRelease") {
            storeFile = keyStore
            storePassword = keys.getProperty("storePassword")
            keyAlias = keys.getProperty("keyAlias")
            keyPassword = keys.getProperty("keyPassword")
            enableV1Signing = true
            enableV2Signing = true
            enableV3Signing = true
        }
    }

    buildTypes {
        getByName("debug") {
            if (signed) signingConfig = signingConfigs.getByName("pluginRelease")
        }
        getByName("release") {
            signingConfig = signingConfigs.getByName(if (signed) "pluginRelease" else "debug")
            isMinifyEnabled = false
        }
    }
}

kotlin {
    compilerOptions { jvmTarget = JvmTarget.JVM_17 }
}

dependencies {
    implementation(project(":plugin_api"))
}
