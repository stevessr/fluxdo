package com.github.lingyan000.fluxdo.plugin.api

import org.json.JSONException
import org.json.JSONObject
import org.json.JSONTokener

/**
 * Validates the same narrow argument schemas enforced by the SDK-only Dart
 * contract. The host validates before binding and the companion validates
 * again before executing: neither side trusts arbitrary MethodChannel/IPC JSON.
 *
 * Update this allowlist when introducing a new operation. The catalog CI gate
 * rejects undeclared or unhandled operations instead of accepting raw fields.
 */
object PluginPayloadContract {
    private val emptyOperations = setOf(
        "device.snapshot",
        "network.state",
        "metaverse.capabilities",
        "reward.capabilities",
    )
    private val hostnameLabel =
        Regex("^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$")

    fun normalize(operation: String, raw: String): String {
        require(raw.toByteArray(Charsets.UTF_8).size <= PluginProtocol.MAX_JSON_BYTES) {
            "Plugin request exceeds UTF-8 byte limit"
        }
        val payload = try {
            val tokener = JSONTokener(raw)
            val value = tokener.nextValue()
            // JSONObject(String) is lenient on Android and may ignore
            // trailing bytes. IPC messages must contain one full JSON object.
            require(value is JSONObject && tokener.nextClean() == '\u0000') {
                "Plugin request must contain exactly one JSON object"
            }
            value
        } catch (_: JSONException) {
            throw IllegalArgumentException("Plugin request must be a JSON object")
        }
        if (operation == "network.lookup") {
            require(payload.length() == 1 && payload.has("hostname")) {
                "DNS lookup accepts only hostname"
            }
            val input = payload.opt("hostname") as? String
                ?: throw IllegalArgumentException("DNS hostname must be a string")
            val hostname = input.trim()
            val labels = hostname.removeSuffix(".").split('.')
            require(hostname.isNotEmpty() && hostname.length <= 253 &&
                labels.all { hostnameLabel.matches(it) }) {
                "Invalid DNS hostname"
            }
            return JSONObject().put("hostname", hostname).toString()
        }
        require(operation in emptyOperations) { "Undeclared plugin operation" }
        require(payload.length() == 0) { "Operation accepts no arguments" }
        return "{}"
    }
}
