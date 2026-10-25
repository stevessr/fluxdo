import java.io.File
import java.util.Properties
import org.jetbrains.kotlin.gradle.dsl.JvmTarget


plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

// The module directory stays under android/ in both Gradle roots.
// Resolve host signing material identically even in the independent build.
val androidRoot = projectDir.parentFile
val versions = Properties().apply {
    androidRoot.resolve("plugin-versions.properties").inputStream().use { load(it) }
}
val keyFile = androidRoot.resolve("key.properties")
val keys = Properties().apply {
    if (keyFile.exists()) keyFile.inputStream().use { load(it) }
}
val keyStore = keys.getProperty("storeFile")?.trim()?.takeIf { it.isNotEmpty() }?.let { path ->
    val raw = File(path)
    if (raw.isAbsolute) raw else listOf(
        androidRoot.resolve("app/$path"),
        androidRoot.resolve(path),
    ).firstOrNull { it.isFile } ?: androidRoot.resolve("app/$path")
}
val signed = listOf("keyAlias", "keyPassword", "storePassword")
    .all { !keys.getProperty(it).isNullOrBlank() } && keyStore?.isFile == true


android {
    namespace = "com.github.lingyan000.fluxdo.plugin.ldc_reward"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.github.lingyan000.fluxdo.plugin.ldc_reward"
        minSdk = 24
        targetSdk = 35
        versionCode = (providers.gradleProperty("pluginVersionCode.ldc_reward")
            .orElse(providers.gradleProperty("pluginVersionCode")).orNull
            ?: versions.getProperty("ldc_reward.versionCode")).toInt().also {
            require(it in 1 until 2100000000) { "Invalid ldc_reward versionCode" }
        }
        versionName = providers.gradleProperty("pluginVersionName.ldc_reward")
            .orElse(providers.gradleProperty("pluginVersionName")).orNull
            ?: versions.getProperty("ldc_reward.versionName")
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
            // Never silently fall back to the debug identity for release.
            signingConfig = if (signed) signingConfigs.getByName("pluginRelease") else null
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

// Check the actual variant task, including unqualified assembleRelease/bundleRelease.
// Matching only command-line task strings could bypass the signing requirement.
tasks.matching { it.name == "preReleaseBuild" }.configureEach {
    doFirst {
        check(signed) { "plugin_ldc_reward Release must use FluxDO host key.properties" }
    }
}
