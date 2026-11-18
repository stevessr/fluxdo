package com.github.lingyan000.fluxdo

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ResolveInfo
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Android 已安装插件的发现和启动契约。
 *
 * 插件在可导出的 Activity 上声明 PLUGIN 动作、DEFAULT 类别和 API_VERSION=1；
 * 宿主按每次实际安装状态重新发现，禁止使用调用方直接传入的任意组件启动应用。
 */
internal class ExternalPluginChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
) {
    companion object {
        private const val CHANNEL = "com.github.lingyan000.fluxdo/external_plugins"
        private const val ACTION = "com.github.lingyan000.fluxdo.action.PLUGIN"
        private const val API_VERSION = "com.github.lingyan000.fluxdo.plugin.API_VERSION"
    }

    private val channel = MethodChannel(messenger, CHANNEL).also { channel ->
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "listPlugins" -> {
                    try {
                        result.success(discover().map { (info, component) ->
                            mapOf(
                                "id" to component.flattenToString(),
                                "packageName" to component.packageName,
                                "label" to info.loadLabel(activity.packageManager).toString(),
                            )
                        })
                    } catch (error: Exception) {
                        result.error("PLUGIN_DISCOVERY_FAILED", error.message, null)
                    }
                }
                "launchPlugin" -> {
                    val id = call.argument<String>("id")
                    if (id.isNullOrBlank()) {
                        result.error("INVALID_PLUGIN", "插件标识不能为空", null)
                    } else {
                        result.success(launch(id))
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }

    private fun discover(): List<Pair<ResolveInfo, ComponentName>> {
        val manager = activity.packageManager
        val intent = Intent(ACTION).addCategory(Intent.CATEGORY_DEFAULT)
        val flags = PackageManager.MATCH_DEFAULT_ONLY or PackageManager.GET_META_DATA
        val matches = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            manager.queryIntentActivities(intent, PackageManager.ResolveInfoFlags.of(flags.toLong()))
        } else {
            @Suppress("DEPRECATION")
            manager.queryIntentActivities(intent, flags)
        }
        return matches.mapNotNull { match ->
            val info = match.activityInfo ?: return@mapNotNull null
            if (!info.exported || !info.enabled || !info.applicationInfo.enabled ||
                info.metaData?.getInt(API_VERSION, 0) != 1
            ) {
                return@mapNotNull null
            }
            match to ComponentName(info.packageName, info.name)
        }.distinctBy { it.second.flattenToString() }
            .sortedBy { it.first.loadLabel(manager).toString().lowercase() }
    }

    private fun launch(id: String): Boolean {
        val component = ComponentName.unflattenFromString(id) ?: return false
        // 每次启动均重新解析：安装、升级、卸载时不会留下过期入口。
        if (discover().none { it.second == component }) return false
        return try {
            activity.startActivity(
                Intent(ACTION)
                    .addCategory(Intent.CATEGORY_DEFAULT)
                    .setComponent(component)
            )
            true
        } catch (_: ActivityNotFoundException) {
            false
        } catch (_: SecurityException) {
            false
        }
    }
}
