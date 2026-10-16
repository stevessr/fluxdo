package com.github.lingyan000.fluxdo.plugin.cdk
import com.github.lingyan000.fluxdo.plugin.api.PluginService
import org.json.JSONObject

/** CDK companion capability discovery. No host session material crosses this IPC. */
class CdkPluginService : PluginService() {
    override fun execute(operation: String, arguments: JSONObject): JSONObject {
        require(operation == "metaverse.capabilities") { "Unsupported operation" }
        return JSONObject().apply {
            put("id", "cdk")
            put("entryUrl", "https://cdk.linux.do")
            put("isolatedSession", true)
            put("hostBalanceMigrationComplete", false)
        }
    }
}
