package com.github.lingyan000.fluxdo

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Message
import android.os.Messenger
import android.os.RemoteException
import com.github.lingyan000.fluxdo.plugin.api.PluginProtocol
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

/**
 * Explicit allowlist + same-signer verification + version negotiation.
 * Plugins are separate installable APKs, not Flutter/DEX code injected into the
 * app process. All communication uses bounded JSON through Android Messenger.
 */
class OptionalPluginChannel(
    private val context: Context,
    messenger: BinaryMessenger,
) {
    private val specs = OptionalPluginCatalog.specs
    private val channel = MethodChannel(messenger, PluginProtocol.CHANNEL)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val active = mutableSetOf<Invocation>()
    private var disposed = false

    init {
        channel.setMethodCallHandler { call, result ->
            if (disposed) {
                result.error("DISPOSED", "Plugin host was detached", null)
                return@setMethodCallHandler
            }
            when (call.method) {
                "list" -> result.success(specs.map(::describe))
                "launch" -> {
                    val spec = specs.firstOrNull {
                        it.id == call.argument<String>("id") && it.activityClass != null
                    }
                    if (spec == null || describe(spec)["compatible"] != true) {
                        result.error("PLUGIN_UNAVAILABLE", "Signed metaverse companion unavailable", null)
                    } else {
                        try {
                            val component = ComponentName(spec.packageName, spec.activityClass!!)
                            val info = context.packageManager.getActivityInfo(component, 0)
                            if (!info.exported || !info.enabled ||
                                info.permission != PluginProtocol.BIND_PERMISSION) {
                                throw SecurityException("Companion activity is not protected")
                            }
                            val launch = Intent().setComponent(component)
                                // Separate package task: discard any prior
                                // companion Activity before changing accounts,
                                // otherwise Back could reveal a stale WebView.
                                .addFlags(
                                    Intent.FLAG_ACTIVITY_NEW_TASK or
                                        Intent.FLAG_ACTIVITY_CLEAR_TASK
                                )
                            if (spec.id == "ldc" || spec.id == "cdk") {
                                // SHA-256 username partition, not an account token.
                                // A missing slot always means an ephemeral guest
                                // session; plugins clear cookies before opening.
                                val payload = call.argument<Map<String, Any?>>("payload")
                                    ?: emptyMap()
                                val slot = (payload["accountSlot"] as? String)
                                    ?: "guest"
                                require(slot == "guest" ||
                                    Regex("^[0-9a-f]{64}$").matches(slot)) {
                                    "Invalid account isolation slot"
                                }
                                launch.putExtra("account_slot", slot)
                            }
                            if (spec.id == "ldc_reward") {
                                // Public post identity only. Never pass tokens,
                                // payment amounts, cookies or Basic Auth secrets.
                                val raw = call.argument<Map<String, Any?>>("payload")
                                    ?: emptyMap()
                                val username = (raw["username"] as? String)
                                    ?.trim()?.take(64).orEmpty()
                                val userId = (raw["userId"] as? Number)
                                    ?.toLong() ?: -1L
                                require(username.isNotEmpty() && userId > 0L) {
                                    "Missing recipient identity"
                                }
                                launch.putExtra("recipient_username", username)
                                launch.putExtra("recipient_user_id", userId)
                            }
                            context.startActivity(launch)
                            result.success(true)
                        } catch (error: Exception) {
                            result.error("LAUNCH_FAILED", error.message, null)
                        }
                    }
                }
                "invoke" -> {
                    val id = call.argument<String>("id")
                    val operation = call.argument<String>("operation")
                    val payload = call.argument<String>("payload") ?: "{}"
                    val spec = specs.firstOrNull { it.id == id }
                    when {
                        spec == null -> result.error("UNKNOWN_PLUGIN", "Unknown plugin id", null)
                        operation == null || operation !in spec.operations ->
                            result.error("UNKNOWN_OPERATION", "Operation is not allowed", null)
                        payload.toByteArray(Charsets.UTF_8).size > PluginProtocol.MAX_JSON_BYTES ->
                            result.error("INVALID_ARGS", "Request too large", null)
                        describe(spec)["compatible"] != true ->
                            result.error("PLUGIN_UNAVAILABLE", "Plugin missing, unsigned or incompatible", null)
                        else -> Invocation(spec, operation!!, payload, result).start()
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun describe(spec: OptionalPluginSpec): Map<String, Any?> {
        val pm = context.packageManager
        val packageInfo = try {
            pm.getPackageInfo(spec.packageName, 0)
        } catch (_: PackageManager.NameNotFoundException) {
            null
        }
        if (packageInfo == null) {
            return mapOf(
                "id" to spec.id, "name" to spec.name,
                "package" to spec.packageName, "installed" to false,
                "compatible" to false, "version" to null,
                "reason" to "not_installed",
            )
        }
        val signed = pm.checkSignatures(context.packageName, spec.packageName) ==
            PackageManager.SIGNATURE_MATCH
        val service = try {
            pm.getServiceInfo(spec.component, PackageManager.GET_META_DATA)
        } catch (_: PackageManager.NameNotFoundException) {
            null
        }
        val declaredApi = service?.metaData?.getInt(
            PluginProtocol.PROTOCOL_METADATA, -1,
        ) ?: -1
        val correctlyProtected = service?.exported == true &&
            service.enabled && service.permission == PluginProtocol.BIND_PERMISSION
        val compatible = signed && correctlyProtected && declaredApi == PluginProtocol.VERSION
        return mapOf(
            "id" to spec.id, "name" to spec.name,
            "package" to spec.packageName, "installed" to true,
            "compatible" to compatible, "version" to packageInfo.versionName,
            "reason" to when {
                !signed -> "signature_mismatch"
                !correctlyProtected -> "unprotected_service"
                declaredApi != PluginProtocol.VERSION -> "incompatible_protocol"
                else -> "ready"
            },
        )
    }

    private inner class Invocation(
        private val spec: OptionalPluginSpec,
        private val operation: String,
        private val payload: String,
        private val result: MethodChannel.Result,
    ) : ServiceConnection {
        private var finished = false
        private var bound = false
        private val timeout = Runnable { fail("TIMEOUT", "Plugin did not respond") }
        private val receiver = Messenger(object : Handler(Looper.getMainLooper()) {
            override fun handleMessage(message: Message) {
                if (message.what != PluginProtocol.RESPONSE || finished) return
                val data = message.data
                if (data.getInt(PluginProtocol.VERSION_KEY, -1) != PluginProtocol.VERSION) {
                    fail("PROTOCOL", "Plugin protocol mismatch")
                    return
                }
                val error = data.getString(PluginProtocol.ERROR_KEY)
                if (error != null) {
                    fail("PLUGIN_ERROR", error.take(PluginProtocol.MAX_ERROR_CHARS))
                    return
                }
                val raw = data.getString(PluginProtocol.RESULT_KEY)
                if (raw == null ||
                    raw.toByteArray(Charsets.UTF_8).size > PluginProtocol.MAX_JSON_BYTES) {
                    fail("PROTOCOL", "Plugin response missing or too large")
                    return
                }
                try {
                    JSONObject(raw) // The v1 protocol requires a JSON object.
                    succeed(raw)
                } catch (_: Exception) {
                    fail("PROTOCOL", "Plugin returned invalid JSON")
                }
            }
        })

        fun start() {
            active.add(this)
            mainHandler.postDelayed(timeout, 15000L)
            try {
                bound = context.bindService(
                    Intent().setComponent(spec.component),
                    this,
                    Context.BIND_AUTO_CREATE,
                )
                if (!bound) fail("BIND_FAILED", "Could not bind plugin")
            } catch (error: Exception) {
                fail("BIND_FAILED", error.message ?: "Could not bind plugin")
            }
        }

        override fun onServiceConnected(name: ComponentName, service: IBinder) {
            if (finished) return
            val request = Message.obtain(null, PluginProtocol.REQUEST).apply {
                data = Bundle().apply {
                    putInt(PluginProtocol.VERSION_KEY, PluginProtocol.VERSION)
                    putString(PluginProtocol.OPERATION_KEY, operation)
                    putString(PluginProtocol.PAYLOAD_KEY, payload)
                }
                replyTo = receiver
            }
            try {
                Messenger(service).send(request)
            } catch (error: RemoteException) {
                fail("IPC_FAILED", error.message ?: "Plugin process unavailable")
            }
        }

        override fun onServiceDisconnected(name: ComponentName) {
            fail("DISCONNECTED", "Plugin process disconnected")
        }

        override fun onBindingDied(name: ComponentName) {
            fail("BINDING_DIED", "Plugin was updated; retry the operation")
        }

        override fun onNullBinding(name: ComponentName) {
            fail("NULL_BINDING", "Plugin did not provide a service")
        }

        private fun succeed(value: String) = finish { result.success(value) }

        fun fail(code: String, reason: String) =
            finish { result.error(code, reason, null) }

        private inline fun finish(deliver: () -> Unit) {
            if (finished) return
            finished = true
            mainHandler.removeCallbacks(timeout)
            active.remove(this)
            if (bound) {
                bound = false
                try { context.unbindService(this) } catch (_: IllegalArgumentException) {}
            }
            deliver()
        }
    }

    fun dispose() {
        if (disposed) return
        disposed = true
        channel.setMethodCallHandler(null)
        active.toList().forEach { it.fail("DISPOSED", "Plugin host was detached") }
    }
}
