package com.github.lingyan000.fluxdo

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.hardware.camera2.CameraManager
import android.os.Build
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

/** Standard Android panel compatibility: XR passthrough is not assumed to be Camera2. */
class PicoVrChannel(
    private val activity: MainActivity,
    messenger: BinaryMessenger,
) {
    private val channel = MethodChannel(messenger, "com.fluxdo/pico_vr")

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getCapabilities" -> result.success(getCapabilities())
                "openNewWindow" -> result.success(openNewWindow())
                else -> result.notImplemented()
            }
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }

    private fun getCapabilities(): Map<String, Any> {
        val identity = listOf(Build.MANUFACTURER, Build.BRAND, Build.MODEL, Build.DEVICE)
            .joinToString(" ").lowercase(Locale.ROOT)
        // CameraX/mobile_scanner requires a camera enumerated by Android Camera2.
        // PICO headset passthrough needs a separate XR camera integration.
        val cameraIds = try {
            (activity.getSystemService(Context.CAMERA_SERVICE) as CameraManager)
                .cameraIdList.toList()
        } catch (e: Exception) {
            Log.w("PicoVr", "Camera2 enumeration failed", e)
            emptyList()
        }
        return mapOf(
            "isPico" to identity.contains("pico"),
            "model" to Build.MODEL,
            "hasCamera2" to cameraIds.isNotEmpty(),
            "supportsMultipleWindows" to (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N),
            "isInMultiWindowMode" to (
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && activity.isInMultiWindowMode
            ),
        )
    }

    private fun openNewWindow(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return false
        return try {
            // NEW_TASK | MULTIPLE_TASK creates an independent Activity/FlutterEngine
            // even if another secondary Fluxdo window is already running.
            val intent = Intent(activity, PicoVrWindowActivity::class.java).apply {
                action = Intent.ACTION_MAIN
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_MULTIPLE_TASK)
            }
            activity.startActivity(intent)
            true
        } catch (e: ActivityNotFoundException) {
            Log.w("PicoVr", "No activity for secondary window", e)
            false
        } catch (e: SecurityException) {
            Log.w("PicoVr", "Secondary window was blocked", e)
            false
        } catch (e: RuntimeException) {
            Log.w("PicoVr", "Secondary window failed", e)
            false
        }
    }
}
