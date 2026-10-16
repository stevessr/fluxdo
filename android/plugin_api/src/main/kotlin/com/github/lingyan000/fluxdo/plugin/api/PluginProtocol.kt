package com.github.lingyan000.fluxdo.plugin.api

/**
 * Stable, small cross-APK wire contract. Never pass Flutter engine or Dart AOT
 * objects across the package boundary. Bump VERSION for incompatible changes.
 */
object PluginProtocol {
    const val VERSION = 1
    // UTF-8 wire limits prevent a plugin from crashing Binder with a huge reply.
    const val MAX_JSON_BYTES = 8192
    const val MAX_ERROR_CHARS = 256
    const val CHANNEL = "com.github.lingyan000.fluxdo/optional_plugins"
    const val BIND_PERMISSION = "com.github.lingyan000.fluxdo.permission.BIND_PLUGIN"
    const val PROTOCOL_METADATA = "com.github.lingyan000.fluxdo.plugin.PROTOCOL"

    const val REQUEST = 1
    const val RESPONSE = 2
    const val VERSION_KEY = "protocol"
    const val OPERATION_KEY = "operation"
    const val PAYLOAD_KEY = "payload"
    const val RESULT_KEY = "result"
    const val ERROR_KEY = "error"
}
