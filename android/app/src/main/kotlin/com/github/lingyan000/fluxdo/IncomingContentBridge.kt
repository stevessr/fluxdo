package com.github.lingyan000.fluxdo

import android.app.Activity
import android.content.ClipData
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.ArrayDeque
import java.util.UUID

/**
 * Android shares and launcher shortcuts use the same channel.
 * Intents are buffered until Dart has mounted the authenticated application UI.
 * content:// grants are consumed while the receiving Activity still owns them.
 */
class IncomingContentBridge(private val activity: Activity) {
    companion object {
        const val CHANNEL = "com.github.lingyan000.fluxdo/incoming_content"
        const val NEW_TOPIC = "com.github.lingyan000.fluxdo.NEW_TOPIC"
        const val NEW_MESSAGE = "com.github.lingyan000.fluxdo.NEW_MESSAGE"
        const val SEARCH = "com.github.lingyan000.fluxdo.SEARCH"
        private const val MAX_FILES = 10
        private const val MAX_BYTES = 100L * 1024L * 1024L
    }

    private val pending = ArrayDeque<Intent>()
    private val main = Handler(Looper.getMainLooper())
    private var channel: MethodChannel? = null

    fun capture(intent: Intent?) {
        val incoming = intent ?: return
        val action = incoming.action
        if (action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE &&
            action != NEW_TOPIC && action != NEW_MESSAGE && action != SEARCH) return
        synchronized(pending) { pending.addLast(Intent(incoming)) }
        main.post { channel?.invokeMethod("newIntent", null) }
    }

    fun attach(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, CHANNEL).also { bridge ->
            bridge.setMethodCallHandler { call, result ->
                if (call.method != "consume") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val incoming = synchronized(pending) {
                    if (pending.isEmpty()) null else pending.removeFirst()
                }
                if (incoming == null) {
                    result.success(null)
                    return@setMethodCallHandler
                }
                // Reading content providers (especially cloud photos) may block.
                Thread({
                    try {
                        val payload = parse(incoming)
                        main.post { result.success(payload) }
                    } catch (e: Exception) {
                        Log.w("IncomingContent", "Cannot read Android share", e)
                        main.post { result.error("SHARE_READ_FAILED", e.message, null) }
                    }
                }, "fluxdo-share-import").start()
            }
        }
    }

    fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    private fun parse(intent: Intent): Map<String, Any?> {
        when (intent.action) {
            NEW_TOPIC -> return mapOf("action" to "topic")
            NEW_MESSAGE -> return mapOf("action" to "message")
            SEARCH -> return mapOf("action" to "search")
        }

        val uris = mutableListOf<Uri>()
        if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)?.let(uris::add)
            intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)?.let(uris::addAll)
        } else {
            @Suppress("DEPRECATION")
            (intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM))?.let(uris::add)
            @Suppress("DEPRECATION")
            intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)?.let(uris::addAll)
        }
        val clip: ClipData? = intent.clipData
        if (clip != null) for (index in 0 until clip.itemCount) {
            clip.getItemAt(index).uri?.let(uris::add)
        }
        val imported = mutableListOf<Map<String, Any>>()
        for (uri in uris.distinct().take(MAX_FILES)) {
            // Never accept file:// paths from another app.
            if (uri.scheme != "content") continue
            val name = displayName(uri)
            val ext = name.substringAfterLast('.', "").lowercase()
            val safeExt = if (ext.matches(Regex("[a-z0-9]{1,8}"))) ".$ext" else ""
            val destDir = File(activity.cacheDir, "incoming-shares").apply { mkdirs() }
            val dest = File(destDir, UUID.randomUUID().toString() + safeExt)
            try {
                activity.contentResolver.openInputStream(uri)?.use { source ->
                    FileOutputStream(dest).use { out ->
                        val buffer = ByteArray(64 * 1024)
                        var total = 0L
                        while (true) {
                            val count = source.read(buffer)
                            if (count < 0) break
                            total += count
                            if (total > MAX_BYTES) throw IllegalArgumentException("Share exceeds 100 MB")
                            out.write(buffer, 0, count)
                        }
                    }
                } ?: continue
                val mime = activity.contentResolver.getType(uri) ?: intent.type.orEmpty()
                imported.add(mapOf(
                    "path" to dest.absolutePath,
                    "name" to name,
                    "image" to mime.startsWith("image/"),
                ))
            } catch (e: Exception) {
                dest.delete()
                Log.w("IncomingContent", "Skipping unreadable URI", e)
            }
        }
        return mapOf(
            "action" to "share",
            "title" to (intent.getStringExtra(Intent.EXTRA_SUBJECT) ?: ""),
            "text" to (intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString() ?: ""),
            "files" to imported,
        )
    }

    private fun displayName(uri: Uri): String {
        var name: String? = null
        var cursor: Cursor? = null
        try {
            cursor = activity.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            if (cursor?.moveToFirst() == true) name = cursor.getString(0)
        } catch (_: Exception) {
            // Providers can refuse metadata while permitting stream access.
        } finally {
            cursor?.close()
        }
        return name?.substringAfterLast('/')?.take(120)
            ?.takeIf { it.isNotBlank() } ?: "shared-file"
    }
}
