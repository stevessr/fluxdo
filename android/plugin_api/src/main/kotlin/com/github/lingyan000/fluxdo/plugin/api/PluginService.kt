package com.github.lingyan000.fluxdo.plugin.api

import android.app.Service
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.Message
import android.os.Messenger
import android.os.RemoteException
import org.json.JSONObject

/**
 * The exported Service MUST be guarded by BIND_PERMISSION (signature) in
 * the plugin manifest. Each request is handled off the UI thread.
 *
 * Messenger carries only short JSON messages; do not send files, cookies,
 * tokens, or other credentials here.
 */
abstract class PluginService : Service() {
    private lateinit var worker: HandlerThread
    private lateinit var endpoint: Messenger

    override fun onCreate() {
        super.onCreate()
        worker = HandlerThread("fluxdo-optional-plugin").also { it.start() }
        endpoint = Messenger(object : Handler(worker.looper) {
            override fun handleMessage(message: Message) {
                if (message.what != PluginProtocol.REQUEST) return
                val response = Message.obtain(null, PluginProtocol.RESPONSE)
                val out = Bundle()
                out.putInt(PluginProtocol.VERSION_KEY, PluginProtocol.VERSION)
                try {
                    val request = message.data
                    if (request.getInt(PluginProtocol.VERSION_KEY, -1) != PluginProtocol.VERSION) {
                        throw IllegalArgumentException("Unsupported plugin protocol")
                    }
                    val operation = request.getString(PluginProtocol.OPERATION_KEY)
                        ?: throw IllegalArgumentException("Missing operation")
                    val raw = request.getString(PluginProtocol.PAYLOAD_KEY) ?: "{}"
                    require(raw.toByteArray(Charsets.UTF_8).size <= PluginProtocol.MAX_JSON_BYTES) {
                        "Request too large"
                    }
                    // Enforce the schema inside the independently installed APK
                    // as well as at the host MethodChannel boundary.
                    val validated = PluginPayloadContract.normalize(operation, raw)
                    val responseJson = execute(operation, JSONObject(validated)).toString()
                    require(responseJson.toByteArray(Charsets.UTF_8).size <= PluginProtocol.MAX_JSON_BYTES) {
                        "Plugin result too large"
                    }
                    out.putString(PluginProtocol.RESULT_KEY, responseJson)
                } catch (error: Exception) {
                    out.putString(
                        PluginProtocol.ERROR_KEY,
                        (error.message ?: "Plugin failed").take(PluginProtocol.MAX_ERROR_CHARS),
                    )
                }
                response.data = out
                try {
                    message.replyTo?.send(response)
                } catch (_: RemoteException) {
                    // Host process was terminated.
                }
            }
        })
    }

    protected abstract fun execute(operation: String, arguments: JSONObject): JSONObject

    override fun onBind(intent: Intent?): IBinder = endpoint.binder

    override fun onDestroy() {
        worker.quitSafely()
        super.onDestroy()
    }
}
