package com.github.lingyan000.fluxdo

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.camera2.CameraManager
import android.Manifest
import android.content.pm.PackageManager as AndroidPackageManager
import androidx.core.content.ContextCompat
import android.provider.MediaStore
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

    companion object {
        // Kept separate from the file picker and other activity-result request codes.
        private const val EXTERNAL_QR_REQUEST = 0x3B91
        private const val XR_QR_REQUEST = 0x3B92
        private const val ZXING_SCAN_ACTION = "com.google.zxing.client.android.SCAN"
    }

    private var pendingQrResult: MethodChannel.Result? = null
    private var pendingXrResult: MethodChannel.Result? = null

    /** Only standardized third-party scanner contracts are accepted, not undocumented PICO Intents. */
    fun handleActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode == XR_QR_REQUEST && pendingXrResult != null) {
            val reply = pendingXrResult
            pendingXrResult = null
            val raw = if (resultCode == Activity.RESULT_OK)
                data?.getStringExtra(PicoXrQrScanActivity.EXTRA_QR) else null
            reply?.success(raw)
            return true
        }
        if (requestCode != EXTERNAL_QR_REQUEST || pendingQrResult == null) return false
        val reply = pendingQrResult
        pendingQrResult = null
        val raw = if (resultCode == Activity.RESULT_OK) data?.getStringExtra("SCAN_RESULT") else null
        reply?.success(raw)
        return true
    }

    private fun startXrQrScanner(result: MethodChannel.Result) {
        val identity = listOf(Build.MANUFACTURER, Build.BRAND, Build.MODEL, Build.DEVICE)
            .joinToString(" ").lowercase(Locale.ROOT)
        if (!identity.contains("pico")) {
            result.error("NOT_PICO", "XR scanner is only offered on PICO", null)
            return
        }
        if (pendingXrResult != null) {
            result.error("BUSY", "XR camera is already scanning", null)
            return
        }
        pendingXrResult = result
        try {
            @Suppress("DEPRECATION")
            activity.startActivityForResult(
                Intent(activity, PicoXrQrScanActivity::class.java),
                XR_QR_REQUEST
            )
        } catch (e: RuntimeException) {
            pendingXrResult = null
            Log.w("PicoVr", "XR scanner launch failed", e)
            result.error("XR_LAUNCH_FAILED", "Unable to open headless XR scanner", null)
        }
    }

    private fun qrScanIntent(): Intent = Intent(ZXING_SCAN_ACTION).apply {
        addCategory(Intent.CATEGORY_DEFAULT)
        putExtra("SCAN_MODE", "QR_CODE_MODE")
        putExtra("SCAN_FORMATS", "QR_CODE")
        putExtra("SAVE_HISTORY", false)
    }

    private fun hasHandler(intent: Intent): Boolean = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            activity.packageManager.queryIntentActivities(
                intent, PackageManager.ResolveInfoFlags.of(
                    PackageManager.MATCH_DEFAULT_ONLY.toLong()
                )
            ).isNotEmpty()
        } else {
            @Suppress("DEPRECATION")
            activity.packageManager.queryIntentActivities(
                intent, PackageManager.MATCH_DEFAULT_ONLY
            ).isNotEmpty()
        }
    } catch (e: RuntimeException) {
        Log.w("PicoVr", "Intent availability probe failed: ${intent.action}", e)
        false
    }

    private fun startExternalQrScanner(result: MethodChannel.Result) {
        if (pendingQrResult != null) {
            result.error("BUSY", "An external QR scanner is already open", null)
            return
        }
        val intent = qrScanIntent()
        if (!hasHandler(intent)) {
            result.error("SCANNER_UNAVAILABLE", "No app implements the ZXing QR scan contract", null)
            return
        }
        pendingQrResult = result
        try {
            @Suppress("DEPRECATION")
            // Always surface the chooser, even when there is a default app:
            // a QR login may carry credentials read by the selected scanner.
            activity.startActivityForResult(
                Intent.createChooser(intent, "Scan login QR code"),
                EXTERNAL_QR_REQUEST
            )
        } catch (e: ActivityNotFoundException) {
            pendingQrResult = null
            result.error("SCANNER_UNAVAILABLE", "External QR scanner disappeared", null)
        } catch (e: SecurityException) {
            pendingQrResult = null
            result.error("SCANNER_DENIED", "The scanner denied this intent", null)
        } catch (e: RuntimeException) {
            pendingQrResult = null
            Log.w("PicoVr", "External QR scanner launch failed", e)
            result.error("SCANNER_FAILED", "Unable to launch external scanner", null)
        }
    }

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getCapabilities" -> result.success(getCapabilities())
                "scanWithExternalApp" -> startExternalQrScanner(result)
                "scanWithXrCamera" -> startXrQrScanner(result)
                "openNewWindow" -> result.success(openNewWindow())
                else -> result.notImplemented()
            }
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        pendingQrResult?.error("WINDOW_CLOSED", "The scanner's Flutter window was closed", null)
        pendingQrResult = null
        pendingXrResult?.error("WINDOW_CLOSED", "XR scan window was closed", null)
        pendingXrResult = null
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
        // A vendor-supplied camera Activity may exist even if the headset
        // exposes no camera devices through Camera2. This is not XR passthrough.
        val hasCaptureHandler = hasHandler(Intent(MediaStore.ACTION_IMAGE_CAPTURE))
        return mapOf(
            "hasCameraCaptureIntent" to hasCaptureHandler,
            "hasExternalQrScanner" to hasHandler(qrScanIntent()),
            "cameraCount" to cameraIds.size,
            "cameraPermissionGranted" to (
                ContextCompat.checkSelfPermission(activity, Manifest.permission.CAMERA) ==
                    AndroidPackageManager.PERMISSION_GRANTED
            ),
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
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N ||
            !PicoVrWindowActivity.reserveLaunch()) return false
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
            PicoVrWindowActivity.cancelLaunch()
            Log.w("PicoVr", "No activity for secondary window", e)
            false
        } catch (e: SecurityException) {
            PicoVrWindowActivity.cancelLaunch()
            Log.w("PicoVr", "Secondary window was blocked", e)
            false
        } catch (e: RuntimeException) {
            PicoVrWindowActivity.cancelLaunch()
            Log.w("PicoVr", "Secondary window failed", e)
            false
        }
    }
}
