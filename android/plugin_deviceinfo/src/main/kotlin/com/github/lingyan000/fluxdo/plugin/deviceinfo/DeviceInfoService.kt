package com.github.lingyan000.fluxdo.plugin.deviceinfo

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import com.github.lingyan000.fluxdo.plugin.api.PluginService
import org.json.JSONArray
import org.json.JSONObject

/** Independently updatable Android device diagnostic capability. */
class DeviceInfoService : PluginService() {
    override fun execute(operation: String, arguments: JSONObject): JSONObject {
        require(operation == "device.snapshot") { "Unsupported operation" }
        val memory = ActivityManager.MemoryInfo()
        (getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager).getMemoryInfo(memory)
        return JSONObject().apply {
            put("manufacturer", Build.MANUFACTURER)
            put("model", Build.MODEL)
            put("androidSdk", Build.VERSION.SDK_INT)
            put("release", Build.VERSION.RELEASE)
            put("securityPatch", Build.VERSION.SECURITY_PATCH)
            put("supportedAbis", JSONArray(Build.SUPPORTED_ABIS))
            put("memoryTotalBytes", memory.totalMem)
            put("memoryAvailableBytes", memory.availMem)
            put("lowMemory", memory.lowMemory)
        }
    }
}
