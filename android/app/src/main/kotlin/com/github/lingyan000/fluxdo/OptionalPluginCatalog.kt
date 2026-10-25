// Generated from android_modular/plugins.json. Do not edit by hand.
package com.github.lingyan000.fluxdo

import android.content.ComponentName

internal data class OptionalPluginSpec(
    val id: String,
    val name: String,
    val packageName: String,
    val serviceClass: String,
    val operations: Set<String>,
    val activityClass: String? = null,
) {
    val component get() = ComponentName(packageName, serviceClass)
}

internal object OptionalPluginCatalog {
    val specs: List<OptionalPluginSpec> = listOf(
        OptionalPluginSpec(
            "deviceinfo",
            "设备诊断",
            "com.github.lingyan000.fluxdo.plugin.deviceinfo",
            "com.github.lingyan000.fluxdo.plugin.deviceinfo.DeviceInfoService",
            setOf("device.snapshot"),
        ),
        OptionalPluginSpec(
            "network",
            "网络诊断",
            "com.github.lingyan000.fluxdo.plugin.network",
            "com.github.lingyan000.fluxdo.plugin.network.NetworkService",
            setOf("network.state", "network.lookup"),
        ),
        OptionalPluginSpec(
            "cdk",
            "CDK 元宇宙",
            "com.github.lingyan000.fluxdo.plugin.cdk",
            "com.github.lingyan000.fluxdo.plugin.cdk.CdkPluginService",
            setOf("metaverse.capabilities"),
            "com.github.lingyan000.fluxdo.plugin.cdk.CdkActivity",
        ),
        OptionalPluginSpec(
            "ldc",
            "LDC 元宇宙",
            "com.github.lingyan000.fluxdo.plugin.ldc",
            "com.github.lingyan000.fluxdo.plugin.ldc.LdcPluginService",
            setOf("metaverse.capabilities"),
            "com.github.lingyan000.fluxdo.plugin.ldc.LdcActivity",
        ),
        OptionalPluginSpec(
            "ldc_reward",
            "LDC 打赏",
            "com.github.lingyan000.fluxdo.plugin.ldc_reward",
            "com.github.lingyan000.fluxdo.plugin.ldc_reward.LdcRewardPluginService",
            setOf("reward.capabilities"),
            "com.github.lingyan000.fluxdo.plugin.ldc_reward.LdcRewardActivity",
        ),
    )
    const val STICKER_PACKAGE = "com.github.lingyan000.fluxdo.plugin.sticker"
    const val STICKER_ACTIVITY = "com.github.lingyan000.fluxdo.plugin.sticker.StickerActivity"
}
