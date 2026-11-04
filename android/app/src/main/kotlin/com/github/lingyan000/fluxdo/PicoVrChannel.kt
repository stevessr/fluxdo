package com.github.lingyan000.fluxdo

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.ImageFormat
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
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
        private const val QR_SCAN_REQUEST_CODE = 0x50C0
        private const val QR_SCAN_ACTION = "com.google.zxing.client.android.SCAN"
    }

    private var pendingQrResult: MethodChannel.Result? = null

    /** Optional Android scanner Activity; does not expose PICO XR frames. */
    private fun qrScannerIntent(): Intent = Intent(QR_SCAN_ACTION).apply {
        putExtra("SCAN_MODE", "QR_CODE_MODE")
    }

    private fun hasExternalQrScanner(): Boolean = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            activity.packageManager.queryIntentActivities(
                qrScannerIntent(),
                PackageManager.ResolveInfoFlags.of(PackageManager.MATCH_DEFAULT_ONLY.toLong())
            ).isNotEmpty()
        } else {
            @Suppress("DEPRECATION")
            activity.packageManager.queryIntentActivities(
                qrScannerIntent(), PackageManager.MATCH_DEFAULT_ONLY
            ).isNotEmpty()
        }
    } catch (e: RuntimeException) {
        Log.w("PicoVr", "External QR scanner lookup failed", e)
        false
    }

    private fun scanWithExternalQrScanner(result: MethodChannel.Result) {
        if (pendingQrResult != null) {
            result.error("QR_SCAN_BUSY", "A QR scan is already running", null)
            return
        }
        if (!hasExternalQrScanner()) {
            result.error("QR_SCAN_UNAVAILABLE", "No compatible QR scanner is installed", null)
            return
        }
        try {
            pendingQrResult = result
            @Suppress("DEPRECATION")
            activity.startActivityForResult(qrScannerIntent(), QR_SCAN_REQUEST_CODE)
        } catch (e: RuntimeException) {
            pendingQrResult = null
            Log.w("PicoVr", "External QR scanner launch failed", e)
            result.error("QR_SCAN_LAUNCH_FAILED", e.message, null)
        }
    }

    /** The result is owned by this Activity, not shared with other windows. */
    fun handleActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != QR_SCAN_REQUEST_CODE) return false
        val callback = pendingQrResult ?: return true
        pendingQrResult = null
        val content = if (resultCode == Activity.RESULT_OK) {
            data?.getStringExtra("SCAN_RESULT")
                ?: data?.getStringExtra(Intent.EXTRA_TEXT)
                ?: data?.dataString
        } else null
        callback.success(content?.takeIf { it.isNotBlank() })
        return true
    }

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getCapabilities" -> result.success(getCapabilities())
                "scanWithExternalQrScanner" -> scanWithExternalQrScanner(result)
                "getWindowStatus" -> result.success(PicoVrWindowActivity.windowStatus())
                "openNewWindow" -> result.success(
                    openNewWindow(
                        call.argument<Int>("topicId"),
                        call.argument<Int>("postNumber")
                    )
                )
                "consumeLaunchRequest" -> result.success(
                    (activity as? PicoVrWindowActivity)?.consumeLaunchRequest()
                )
                else -> result.notImplemented()
            }
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        pendingQrResult?.error("QR_SCAN_CANCELLED", "Scanner Activity was destroyed", null)
        pendingQrResult = null
    }

    private fun getCapabilities(): Map<String, Any> {
        val identity = listOf(Build.MANUFACTURER, Build.BRAND, Build.MODEL, Build.DEVICE)
            .joinToString(" ").lowercase(Locale.ROOT)
        // CameraX/mobile_scanner requires a camera enumerated by Android Camera2.
        // PICO headset passthrough needs a separate XR camera integration.
        val hasScannerCamera = try {
            val manager = activity.getSystemService(Context.CAMERA_SERVICE) as CameraManager
            manager.cameraIdList.any { cameraId ->
                try {
                    val characteristics = manager.getCameraCharacteristics(cameraId)
                    val caps = characteristics.get(
                        CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES
                    ) ?: intArrayOf()
                    val backwardCompatible = caps.contains(
                        CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES_BACKWARD_COMPATIBLE
                    )
                    val outputs = characteristics.get(
                        CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP
                    )
                    backwardCompatible &&
                        !outputs?.getOutputSizes(ImageFormat.YUV_420_888).isNullOrEmpty()
                } catch (e: Exception) {
                    Log.w("PicoVr", "Camera2 device is not usable for QR scanning", e)
                    false
                }
            }
        } catch (e: Exception) {
            Log.w("PicoVr", "Camera2 enumeration failed", e)
            false
        }
        // A vendor-supplied camera Activity may exist even if the headset
        // exposes no camera devices through Camera2. This is not XR passthrough.
        val captureIntent = Intent(MediaStore.ACTION_IMAGE_CAPTURE)
        val hasCaptureHandler = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                activity.packageManager.queryIntentActivities(
                    captureIntent, PackageManager.ResolveInfoFlags.of(
                        PackageManager.MATCH_DEFAULT_ONLY.toLong()
                    )
                ).isNotEmpty()
            } else {
                @Suppress("DEPRECATION")
                activity.packageManager.queryIntentActivities(
                    captureIntent, PackageManager.MATCH_DEFAULT_ONLY
                ).isNotEmpty()
            }
        } catch (e: Exception) {
            Log.w("PicoVr", "Camera capture intent lookup failed", e)
            false
        }
        return mapOf(
            "hasCameraCaptureIntent" to hasCaptureHandler,
            "hasExternalQrScanner" to hasExternalQrScanner(),
            "isPico" to identity.contains("pico"),
            "model" to Build.MODEL,
            "hasCamera2" to hasScannerCamera,
            "maxWindows" to PicoVrWindowActivity.MAX_TOTAL_WINDOWS,
            "supportsMultipleWindows" to (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N),
            "isInMultiWindowMode" to (
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && activity.isInMultiWindowMode
            ),
        )
    }

    private fun openNewWindow(topicId: Int?, postNumber: Int?): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return false
        val reservationId = PicoVrWindowActivity.reserveLaunch() ?: run {
            Log.i("PicoVr", "Reached the limit of 10 FluxDO windows including main")
            return false
        }
        return try {
            // NEW_TASK | MULTIPLE_TASK creates an independent Activity/FlutterEngine
            // even if another secondary Fluxdo window is already running.
            val intent = Intent(activity, PicoVrWindowActivity::class.java).apply {
                action = Intent.ACTION_MAIN
                putExtra(PicoVrWindowActivity.EXTRA_RESERVATION_ID, reservationId)
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_MULTIPLE_TASK or
                        Intent.FLAG_ACTIVITY_LAUNCH_ADJACENT
                )
                if (topicId != null && topicId > 0) {
                    putExtra(PicoVrWindowActivity.EXTRA_TOPIC_ID, topicId)
                    if (postNumber != null && postNumber > 0) {
                        putExtra(PicoVrWindowActivity.EXTRA_POST_NUMBER, postNumber)
                    }
                }
            }
            // Android's real multi-task / multi-window path, not an in-app
            // imitation. The XR shell chooses panel geometry and may ignore
            // LAUNCH_ADJACENT if it does not implement native placement.
            activity.startActivity(intent)
            true
        } catch (e: ActivityNotFoundException) {
            PicoVrWindowActivity.cancelLaunch(reservationId)
            Log.w("PicoVr", "No activity for secondary window", e)
            false
        } catch (e: SecurityException) {
            PicoVrWindowActivity.cancelLaunch(reservationId)
            Log.w("PicoVr", "Secondary window was blocked", e)
            false
        } catch (e: RuntimeException) {
            PicoVrWindowActivity.cancelLaunch(reservationId)
            Log.w("PicoVr", "Secondary window failed", e)
            false
        }
    }
}
