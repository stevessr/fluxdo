package com.github.lingyan000.fluxdo

import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

/**
 * Activity-based companion (not the Messenger diagnostic plugin API): runs its
 * own Flutter engine in a separately installed, independently updatable APK.
 */
class StickerCompanionChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
) {
    companion object {
        private const val CHANNEL = "com.github.lingyan000.fluxdo/sticker_companion"
        private const val PACKAGE = "com.github.lingyan000.fluxdo.plugin.sticker"
        private const val ACTIVITY = "$PACKAGE.StickerActivity"
        private const val REQUEST_CODE = 0x571C
        private const val MAX_BYTES = 16 * 1024 * 1024
        private val TYPES = mapOf(
            "image/png" to "png",
            "image/webp" to "webp",
            "image/avif" to "avif",
            "image/jpeg" to "jpg",
            "image/svg+xml" to "svg",
        )
    }

    private val channel = MethodChannel(messenger, CHANNEL)
    private var pending: MethodChannel.Result? = null

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "available" -> result.success(isAvailable())
                "generate" -> {
                    if (pending != null) {
                        result.error("BUSY", "A sticker session is already open", null)
                    } else if (!isAvailable()) {
                        result.error("NOT_INSTALLED", "Signed sticker companion unavailable", null)
                    } else {
                        pending = result
                        try {
                            activity.startActivityForResult(
                                Intent(Intent.ACTION_GET_CONTENT).apply {
                                    component = ComponentName(PACKAGE, ACTIVITY)
                                    type = "image/*"
                                    addCategory(Intent.CATEGORY_OPENABLE)
                                },
                                REQUEST_CODE,
                            )
                        } catch (error: Exception) {
                            pending = null
                            result.error("LAUNCH_FAILED", error.message, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun isAvailable(): Boolean {
        val pm = activity.packageManager
        if (pm.checkSignatures(activity.packageName, PACKAGE) !=
            PackageManager.SIGNATURE_MATCH) return false
        return try {
            val info = pm.getActivityInfo(ComponentName(PACKAGE, ACTIVITY), 0)
            info.exported && info.enabled
        } catch (_: PackageManager.NameNotFoundException) {
            false
        }
    }

    /**
     * true = request consumed; false = not our activity result.
     * A cancelled dialog returns null rather than uploading a bogus image.
     */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val response = pending ?: return true
        pending = null
        if (resultCode != Activity.RESULT_OK) {
            response.success(null)
            return true
        }
        val uri: Uri? = data?.data
        val mime = data?.type
        if (uri == null || mime !in TYPES || uri.scheme != "content" ||
            uri.authority != "$PACKAGE.files" || !isAvailable()) {
            response.error("UNTRUSTED_RESULT", "Invalid or unsigned companion result", null)
            return true
        }
        try {
            val bytes = ByteArrayOutputStream()
            activity.contentResolver.openInputStream(uri).use { stream ->
                requireNotNull(stream) { "Companion URI cannot be read" }
                val buffer = ByteArray(32768)
                while (true) {
                    val count = stream.read(buffer)
                    if (count < 0) break
                    if (count == 0) continue
                    check(bytes.size() + count <= MAX_BYTES) { "Sticker export too large" }
                    bytes.write(buffer, 0, count)
                }
            }
            check(bytes.size() > 0) { "Empty sticker export" }
            response.success(
                mapOf(
                    "bytes" to bytes.toByteArray(),
                    "mimeType" to mime,
                    "extension" to TYPES[mime],
                ),
            )
        } catch (error: Exception) {
            response.error("READ_FAILED", error.message, null)
        }
        return true
    }

    fun dispose() {
        pending?.error("DISPOSED", "The host activity was destroyed", null)
        pending = null
        channel.setMethodCallHandler(null)
    }
}
