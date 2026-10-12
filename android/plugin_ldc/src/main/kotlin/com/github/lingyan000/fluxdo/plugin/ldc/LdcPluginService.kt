package com.github.lingyan000.fluxdo.plugin.ldc
import com.github.lingyan000.fluxdo.plugin.api.PluginService
import org.json.JSONObject

/** LDC companion capability discovery. No host session material crosses this IPC. */
class LdcPluginService : PluginService() {
    override fun execute(operation: String, arguments: JSONObject): JSONObject {
        require(operation == "metaverse.capabilities") { "Unsupported operation" }
        return JSONObject().apply {
            put("id", "ldc")
            put("entryUrl", "https://credit.linux.do")
            put("isolatedSession", true)
            put("hostBalanceMigrationComplete", false)
        }
    }
}
