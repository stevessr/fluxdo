package com.github.lingyan000.fluxdo

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Android-only VPN bypass bridge.
 *
 * When enabled and a VPN is active, FluxDO binds its process to the best currently
 * available non-VPN network (Wi-Fi/Ethernet/Cellular). Android only permits this
 * when the active VPN was established with VpnService.Builder.allowBypass(), and
 * VPN lockdown policies can still block the resulting traffic.
 *
 * The binding is intentionally process-wide so Cronet / dart:io / WebView-created
 * sockets that follow the process default network share the same route.
 */
class VpnBypassChannel(
    context: Context,
    messenger: BinaryMessenger,
) {
    companion object {
        private const val TAG = "VpnBypass"
        private const val CHANNEL = "com.fluxdo/vpn_bypass"
        private const val PREFS_FILE = "FlutterSharedPreferences"
        private const val PREFS_KEY = "flutter.vpn_bypass_enabled"
    }

    private val appContext = context.applicationContext
    private val connectivityManager =
        appContext.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    private val channel = MethodChannel(messenger, CHANNEL)
    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var enabled: Boolean = appContext
        .getSharedPreferences(PREFS_FILE, Context.MODE_PRIVATE)
        .getBoolean(PREFS_KEY, false)

    @Volatile
    private var watching = false

    @Volatile
    private var boundNetwork: Network? = null

    private var lastStatus: Map<String, Any?> = emptyMap()

    private val networkCallback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) {
            rebindAndPublish()
        }

        override fun onLost(network: Network) {
            rebindAndPublish()
        }

        override fun onCapabilitiesChanged(
            network: Network,
            networkCapabilities: NetworkCapabilities,
        ) {
            rebindAndPublish()
        }
    }

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "setEnabled" -> {
                    val value = call.argument<Boolean>("enabled")
                    if (value == null) {
                        result.error("INVALID_ARGS", "enabled is required", null)
                    } else {
                        result.success(setEnabled(value))
                    }
                }

                "getStatus" -> result.success(currentStatus())
                else -> result.notImplemented()
            }
        }

        if (enabled) {
            startWatching()
            rebindAndPublish()
        } else {
            clearProcessBinding()
            publishStatus(currentStatus())
        }
    }

    fun dispose() {
        stopWatching()
        channel.setMethodCallHandler(null)
        // Keep the current process binding while the Flutter engine/activity is
        // being reattached. A newly-created channel instance reads the persisted
        // preference and immediately resumes monitoring. Process death clears the
        // binding automatically.
    }

    @Synchronized
    private fun setEnabled(value: Boolean): Map<String, Any?> {
        enabled = value
        if (!value) {
            stopWatching()
            clearProcessBinding()
            return currentStatus(reasonOverride = "disabled")
        }

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            clearProcessBinding()
            return currentStatus(reasonOverride = "unsupported")
        }

        startWatching()
        return rebind()
    }

    private fun startWatching() {
        if (watching || Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        try {
            // NetworkRequest adds NOT_VPN by default. Remove it so the callback is
            // also notified when the VPN itself appears/disappears; rebind() then
            // selects only physical/non-VPN candidate networks.
            val request = NetworkRequest.Builder()
                .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                .removeCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
                .build()
            connectivityManager.registerNetworkCallback(request, networkCallback)
            watching = true
        } catch (e: Throwable) {
            Log.w(TAG, "registerNetworkCallback failed: ${e.message}", e)
        }
    }

    private fun stopWatching() {
        if (!watching) return
        try {
            connectivityManager.unregisterNetworkCallback(networkCallback)
        } catch (_: Throwable) {
            // Callback can already be unregistered during engine/activity teardown.
        } finally {
            watching = false
        }
    }

    @Synchronized
    private fun rebindAndPublish() {
        if (!enabled) return
        publishStatus(rebind())
    }

    @Synchronized
    private fun rebind(): Map<String, Any?> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            clearProcessBinding()
            return currentStatus(reasonOverride = "unsupported")
        }

        val networks = try {
            connectivityManager.allNetworks.toList()
        } catch (e: Throwable) {
            Log.w(TAG, "Unable to enumerate networks: ${e.message}", e)
            clearProcessBinding()
            return currentStatus(reasonOverride = "enumerationFailed")
        }

        val vpnActive = networks.any { network ->
            connectivityManager.getNetworkCapabilities(network)
                ?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true
        }

        // Do not pin the process to one physical network when no VPN is present:
        // letting Android choose the default preserves normal Wi-Fi/cellular failover.
        if (!vpnActive) {
            clearProcessBinding()
            return currentStatus(
                reasonOverride = "waitingForVpn",
                vpnActiveOverride = false,
            )
        }

        val candidate = networks
            .mapNotNull { network ->
                val caps = connectivityManager.getNetworkCapabilities(network)
                    ?: return@mapNotNull null
                if (!caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) {
                    return@mapNotNull null
                }
                if (!caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)) {
                    return@mapNotNull null
                }
                Candidate(network, caps, score(caps))
            }
            .maxByOrNull { it.score }

        if (candidate == null) {
            clearProcessBinding()
            return currentStatus(
                reasonOverride = "noNonVpnNetwork",
                vpnActiveOverride = true,
            )
        }

        if (boundNetwork == candidate.network &&
            connectivityManager.boundNetworkForProcess == candidate.network
        ) {
            return statusForCandidate(
                candidate,
                reason = "bound",
                vpnActive = true,
            )
        }

        val success = try {
            connectivityManager.bindProcessToNetwork(candidate.network)
        } catch (e: Throwable) {
            Log.w(TAG, "bindProcessToNetwork failed: ${e.message}", e)
            false
        }

        if (!success) {
            boundNetwork = null
            return statusForCandidate(
                candidate,
                reason = "bindFailed",
                vpnActive = true,
                bound = false,
            )
        }

        boundNetwork = candidate.network
        Log.i(TAG, "Bound process to non-VPN ${transportName(candidate.capabilities)}")
        return statusForCandidate(
            candidate,
            reason = "bound",
            vpnActive = true,
        )
    }

    private fun clearProcessBinding() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            boundNetwork = null
            return
        }
        try {
            connectivityManager.bindProcessToNetwork(null)
        } catch (e: Throwable) {
            Log.w(TAG, "Clearing process network binding failed: ${e.message}", e)
        } finally {
            boundNetwork = null
        }
    }

    private fun currentStatus(
        reasonOverride: String? = null,
        vpnActiveOverride: Boolean? = null,
    ): Map<String, Any?> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return mapOf(
                "supported" to false,
                "enabled" to enabled,
                "vpnActive" to false,
                "bound" to false,
                "validated" to false,
                "transport" to "other",
                "reason" to (reasonOverride ?: "unsupported"),
            )
        }

        val currentBound = connectivityManager.boundNetworkForProcess
        val caps = currentBound?.let(connectivityManager::getNetworkCapabilities)
        val vpnActive = vpnActiveOverride ?: try {
            connectivityManager.allNetworks.any { network ->
                connectivityManager.getNetworkCapabilities(network)
                    ?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true
            }
        } catch (_: Throwable) {
            false
        }

        return mapOf(
            "supported" to true,
            "enabled" to enabled,
            "vpnActive" to vpnActive,
            "bound" to (enabled && currentBound != null),
            "validated" to (
                caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) == true
            ),
            "transport" to (caps?.let(::transportName) ?: "other"),
            "reason" to (
                reasonOverride
                    ?: if (!enabled) "disabled"
                    else if (!vpnActive) "waitingForVpn"
                    else if (currentBound != null) "bound"
                    else "noNonVpnNetwork"
            ),
        )
    }

    private fun statusForCandidate(
        candidate: Candidate,
        reason: String,
        vpnActive: Boolean,
        bound: Boolean = true,
    ): Map<String, Any?> = mapOf(
        "supported" to true,
        "enabled" to enabled,
        "vpnActive" to vpnActive,
        "bound" to bound,
        "validated" to candidate.capabilities.hasCapability(
            NetworkCapabilities.NET_CAPABILITY_VALIDATED,
        ),
        "transport" to transportName(candidate.capabilities),
        "reason" to reason,
    )

    private fun score(capabilities: NetworkCapabilities): Int {
        var score = 0
        if (capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)) {
            score += 1000
        }
        if (capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)) {
            score += 100
        }
        score += when {
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> 400
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> 350
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> 200
            else -> 50
        }
        return score
    }

    private fun transportName(capabilities: NetworkCapabilities): String = when {
        capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
        capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
        capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "cellular"
        else -> "other"
    }

    private fun publishStatus(status: Map<String, Any?>) {
        if (status == lastStatus) return
        lastStatus = status
        mainHandler.post {
            channel.invokeMethod("statusChanged", status)
        }
    }

    private data class Candidate(
        val network: Network,
        val capabilities: NetworkCapabilities,
        val score: Int,
    )
}
