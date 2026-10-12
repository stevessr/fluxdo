package com.github.lingyan000.fluxdo.plugin.network

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.SystemClock
import com.github.lingyan000.fluxdo.plugin.api.PluginService
import java.net.InetAddress
import org.json.JSONArray
import org.json.JSONObject

/** Network diagnostics run in the plugin's process, not the Flutter process. */
class NetworkService : PluginService() {
    override fun execute(operation: String, arguments: JSONObject): JSONObject =
        when (operation) {
            "network.state" -> {
                val manager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                val caps = manager.getNetworkCapabilities(manager.activeNetwork)
                JSONObject().apply {
                    put("connected", caps != null)
                    put("validated", caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) == true)
                    put("wifi", caps?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true)
                    put("cellular", caps?.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) == true)
                    put("vpn", caps?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true)
                }
            }
            "network.lookup" -> {
                val hostname = arguments.optString("hostname", "").trim()
                require(hostname.length in 1..253 && hostname.matches(Regex("[a-zA-Z0-9.-]+")) &&
                    !hostname.startsWith("-") && !hostname.endsWith("-")) { "Invalid hostname" }
                val start = SystemClock.elapsedRealtime()
                val addresses = InetAddress.getAllByName(hostname)
                JSONObject().apply {
                    put("hostname", hostname)
                    put("elapsedMs", SystemClock.elapsedRealtime() - start)
                    put("addresses", JSONArray(addresses.take(16).map { it.hostAddress }))
                }
            }
            else -> throw IllegalArgumentException("Unsupported operation")
        }
}
