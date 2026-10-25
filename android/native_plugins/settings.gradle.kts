// Generated from android_modular/plugins.json. Do not edit by hand.
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
plugins {
    id("com.android.application") version "8.11.1" apply false
    id("com.android.library") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}
rootProject.name = "fluxdo-native-companions"
include(":plugin_api")
project(":plugin_api").projectDir = file("../plugin_api")
include(":plugin_web_session")
project(":plugin_web_session").projectDir = file("../plugin_web_session")
include(":plugin_deviceinfo")
project(":plugin_deviceinfo").projectDir = file("../plugin_deviceinfo")
include(":plugin_network")
project(":plugin_network").projectDir = file("../plugin_network")
include(":plugin_cdk")
project(":plugin_cdk").projectDir = file("../plugin_cdk")
include(":plugin_ldc")
project(":plugin_ldc").projectDir = file("../plugin_ldc")
include(":plugin_ldc_reward")
project(":plugin_ldc_reward").projectDir = file("../plugin_ldc_reward")
