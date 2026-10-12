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

/**
 * Explicit allowlist + same-signer verification + version negotiation.
 * Plugins are separate installable APKs, not Flutter/DEX code injected into the
 * app process. All communication uses bounded JSON through Android Messenger.
 */
class OptionalPluginChannel(
    private val context: Context,
    messenger: BinaryMessenger,
) {
    private data class Spec(
        val id: String,
        val name: String,
        val packageName: String,
        val serviceClass: String,
        val operations: Set<String>,
        val activityClass: String? = null,
    ) {
        val component get() = ComponentName(packageName, serviceClass)
    }

    private val specs = listOf(
        Spec(
            "deviceinfo", "设备诊断",
            "com.github.lingyan000.fluxdo.plugin.deviceinfo",
            "com.github.lingyan000.fluxdo.plugin.deviceinfo.DeviceInfoService",
            setOf("device.snapshot"),
        ),
        Spec(
            "network", "网络诊断",
            "com.github.lingyan000.fluxdo.plugin.network",
            "com.github.lingyan000.fluxdo.plugin.network.NetworkService",
            setOf("network.state", "network.lookup"),
        ),
        Spec(
            "cdk", "CDK 元宇宙",
            "com.github.lingyan000.fluxdo.plugin.cdk",
            "com.github.lingyan000.fluxdo.plugin.cdk.CdkPluginService",
            setOf("metaverse.capabilities"),
            "com.github.lingyan000.fluxdo.plugin.cdk.CdkActivity",
        ),
        Spec(
            "ldc", "LDC 元宇宙",
            "com.github.lingyan000.fluxdo.plugin.ldc",
            "com.github.lingyan000.fluxdo.plugin.ldc.LdcPluginService",
            setOf("metaverse.capabilities"),
            "com.github.lingyan000.fluxdo.plugin.ldc.LdcActivity",
        ),
    )
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
                            if (!info.exported || info.permission != PluginProtocol.BIND_PERMISSION) {
                                throw SecurityException("Companion activity is not protected")
                            }
                            context.startActivity(
                                Intent().setComponent(component)
                                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                            )
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
                        operation !in spec.operations ->
                            result.error("UNKNOWN_OPERATION", "Operation is not allowed", null)
                        payload.length > 8192 ->
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
    private fun describe(spec: Spec): Map<String, Any?> {
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
            service.permission == PluginProtocol.BIND_PERMISSION
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
        private val spec: Spec,
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
                if (error != null) fail("PLUGIN_ERROR", error)
                else succeed(data.getString(PluginProtocol.RESULT_KEY) ?: "{}")
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
