package com.github.lingyan000.fluxdo.plugin.ldc_reward

import com.github.lingyan000.fluxdo.plugin.api.PluginService
import org.json.JSONObject

/** Standalone reward IPC: discovery only, NEVER performs an unaudited transfer. */
class LdcRewardPluginService : PluginService() {
    override fun execute(operation: String, arguments: JSONObject): JSONObject {
        require(operation == "reward.capabilities") { "Unsupported operation" }
        return JSONObject().apply {
            put("id", "ldc_reward")
            put("transactionApiEnabled", false)
            put("credentialsSharedWithHost", false)
            put("manualWebHandoff", true)
            put("protocol", 1)
        }
    }
}
