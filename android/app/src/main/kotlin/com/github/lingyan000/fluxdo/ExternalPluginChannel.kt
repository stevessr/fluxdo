package com.github.lingyan000.fluxdo

import android.app.Activity
import android.net.Uri
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.Executors
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
        private const val INSERT_IMAGE_REQUEST = 0xF1D0
        private const val MAX_GENERATED_IMAGE_BYTES = 12 * 1024 * 1024
        private const val PACK_PACKAGE = "com.github.stevessr.fluxdo.resources"
        private val FONT_PATH = Regex("^(fonts/[0-9a-f]{64}|emoji_fonts/[0-9a-f]{40})\\.ttf$")
        private val EMOJI_PATH = Regex("^emoji/(noto|twemoji|fluentui|openmoji|unicode|noto_3d|noto_animated)/[a-z0-9_+\\-]+(/[1-6])?\\.(png|webp)$")
    }

    private val packExecutor = Executors.newFixedThreadPool(2)

    private val channel = MethodChannel(messenger, CHANNEL).also { channel ->
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "copyPackFont", "readPackEmoji" -> {
                    val path = call.argument<String>("path").orEmpty()
                    val font = call.method == "copyPackFont"
                    if (!(if (font) FONT_PATH else EMOJI_PATH).matches(path)) {
                        result.error("INVALID_ASSET", "Invalid resource pack path", null)
                    } else {
                        packExecutor.execute {
                            val value = readPackAsset(path, font)
                            activity.runOnUiThread { result.success(value) }
                        }
                    }
                }
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
        packExecutor.shutdown()
    }

    // Read only the designated package's assets. Never load its code or
    // accept a filesystem path from a third-party application.
    private fun readPackAsset(path: String, font: Boolean): Map<String, Any?> {
        val pack = try {
            activity.createPackageContext(PACK_PACKAGE, 0)
        } catch (_: PackageManager.NameNotFoundException) {
            return mapOf("installed" to false)
        } catch (_: Exception) {
            return mapOf("installed" to false)
        }
        var temporary: File? = null
        return try {
            pack.assets.open(path).use { input ->
                val limit = if (font) 80 * 1024 * 1024 else 2 * 1024 * 1024
                if (font) {
                    val target = File.createTempFile("pack-font-", ".ttf", activity.cacheDir)
                    temporary = target
                    target.outputStream().use { output ->
                        val buffer = ByteArray(32768)
                        var total = 0
                        while (true) {
                            val count = input.read(buffer)
                            if (count < 0) break
                            total += count
                            require(total <= limit)
                            output.write(buffer, 0, count)
                        }
                        require(total > 0)
                    }
                    mapOf("installed" to true, "path" to target.absolutePath)
                } else {
                    val buffer = ByteArray(8192)
                    val output = ByteArrayOutputStream()
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        require(output.size() + count <= limit)
                        output.write(buffer, 0, count)
                    }
                    mapOf("installed" to true, "bytes" to output.toByteArray())
                }
            }
        } catch (_: Exception) {
            temporary?.delete()
            mapOf("installed" to true)
        }
    }

    /**
     * Accept image results only from activities launched via the verified
     * catalog. Reject arbitrary file paths and unbounded URI content.
     */
    fun handleActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != INSERT_IMAGE_REQUEST) return false
        if (resultCode != Activity.RESULT_OK) {
            channel.invokeMethod("generatedImageCancelled", null)
            return true
        }

        val uri: Uri = data?.data ?: return true
        if (uri.scheme != "content") return true
        val mimeType = data.type ?: activity.contentResolver.getType(uri) ?: return true
        val extension = when (mimeType) {
            "image/png" -> "png"
            "image/jpeg" -> "jpg"
            "image/webp" -> "webp"
            "image/avif" -> "avif"
            else -> return true
        }
        Thread {
            try {
                val bytes = activity.contentResolver.openInputStream(uri)?.use { input ->
                    val buffer = ByteArray(8192)
                    val output = ByteArrayOutputStream()
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        if (output.size() + count > MAX_GENERATED_IMAGE_BYTES) {
                            throw IllegalArgumentException("Generated image is too large")
                        }
                        output.write(buffer, 0, count)
                    }
                    output.toByteArray()
                } ?: return@Thread
                if (bytes.isEmpty()) return@Thread
                activity.runOnUiThread {
                    channel.invokeMethod(
                        "generatedImage",
                        mapOf(
                            "bytes" to bytes,
                            "fileName" to "stevessr_generated.$extension",
                        ),
                    )
                }
            } catch (_: Exception) {
                // Invalid or withdrawn URI grants must not crash the host.
            }
        }.start()
        return true
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
            @Suppress("DEPRECATION")
            activity.startActivityForResult(
                Intent(ACTION)
                    .addCategory(Intent.CATEGORY_DEFAULT)
                    .setComponent(component),
                INSERT_IMAGE_REQUEST,
            )
            true
        } catch (_: ActivityNotFoundException) {
            false
        } catch (_: SecurityException) {
            false
        }
    }
}
