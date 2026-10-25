package com.github.lingyan000.fluxdo.plugin.sticker

import android.app.Activity
import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Separate Flutter-engine UI owned by the companion APK. Returns image bytes
 * to FluxDO via a scoped FileProvider URI rather than sharing app storage.
 */
class StickerActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.github.lingyan000.fluxdo.plugin.sticker/return",
        ).setMethodCallHandler { call, result ->
            if (call.method == "insertMode") {
                result.success(intent?.action == Intent.ACTION_GET_CONTENT)
                return@setMethodCallHandler
            }
            if (call.method != "complete") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val path = call.argument<String>("path")
            val mime = call.argument<String>("mimeType")
            val ext = call.argument<String>("extension")
            val types = mapOf(
                "png" to "image/png", "webp" to "image/webp",
                "avif" to "image/avif", "jpg" to "image/jpeg",
                "svg" to "image/svg+xml",
            )
            if (path == null || ext == null || types[ext] != mime) {
                result.error("INVALID", "Invalid export type", null)
                return@setMethodCallHandler
            }
            val file = File(path).canonicalFile
            val cache = cacheDir.canonicalFile
            if (!file.path.startsWith(cache.path + File.separator) ||
                !file.isFile || file.length() <= 0L ||
                file.length() > 16L * 1024 * 1024) {
                result.error("INVALID", "Export file outside companion cache", null)
                return@setMethodCallHandler
            }
            try {
                val uri: Uri = FileProvider.getUriForFile(
                    this, "${packageName}.files", file,
                )
                setResult(
                    Activity.RESULT_OK,
                    Intent().setDataAndType(uri, mime)
                        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        .apply {
                            clipData = android.content.ClipData.newUri(
                                contentResolver, "StevesSR", uri,
                            )
                        },
                )
                result.success(null)
                finish()
            } catch (e: Exception) {
                result.error("EXPORT", e.message, null)
            }
        }
    }
}
