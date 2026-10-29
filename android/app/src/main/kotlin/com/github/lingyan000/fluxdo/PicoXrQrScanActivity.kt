package com.github.lingyan000.fluxdo

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import com.google.zxing.BinaryBitmap
import com.google.zxing.DecodeHintType
import com.google.zxing.PlanarYUVLuminanceSource
import com.google.zxing.ReaderException
import com.google.zxing.common.HybridBinarizer
import com.google.zxing.qrcode.QRCodeReader
import java.util.EnumMap
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

/**
 * Short-lived, non-exported, PICO-only headless OpenXR camera session.
 * Raw frames never leave this Activity; only decoded QR text is returned.
 *
 * A 2D Flutter window cannot simply open Camera2 for the PICO passthrough
 * cameras. The native bridge requests XR_MND_headless and XR_PICO_camera_image
 * on the active runtime. Failure never falls back to undocumented vendor APIs.
 */
class PicoXrQrScanActivity : Activity() {
    companion object {
        const val EXTRA_QR = "SCAN_RESULT"
        private const val CAMERA_PERMISSION_REQUEST = 0x513
        @Volatile private var nativeLoaded = false
        private val nextScanToken = AtomicLong(1)

        private fun loadLibrary(): Boolean {
            if (nativeLoaded) return true
            return try {
                System.loadLibrary("pico_xr_qr")
                nativeLoaded = true
                true
            } catch (_: UnsatisfiedLinkError) {
                false
            }
        }
    }

    private external fun scanNative(timeoutMillis: Long, scanToken: Long): String?
    private external fun cancelNative(scanToken: Long)
    private external fun lastNativeError(): String

    private val executor = Executors.newSingleThreadExecutor()
    @Volatile private var scanToken = 0L
    private val scanning = AtomicBoolean(false)
    private val mainHandler = Handler(Looper.getMainLooper())
    private var active = false
    private var restartWhenIdle = false
    private var invalidatedScanToken = 0L
    private var permissionRequestPending = false
    private var permissionDeclined = false
    private lateinit var description: TextView
    private lateinit var retry: Button
    private val reader = QRCodeReader()
    private val hints = EnumMap<DecodeHintType, Any>(DecodeHintType::class.java).apply {
        put(DecodeHintType.POSSIBLE_FORMATS, listOf(com.google.zxing.BarcodeFormat.QR_CODE))
        put(DecodeHintType.TRY_HARDER, true)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // The QR being scanned may contain a login secret. Keep it out of
        // screen captures and recent-task thumbnails while scanning.
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
            WindowManager.LayoutParams.FLAG_SECURE)
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(36, 36, 36, 36)
        }
        description = TextView(this).apply {
            text = "PICO XR camera QR scanner\nPoint your headset towards the QR code."
            textSize = 18f
            gravity = Gravity.CENTER
        }
        retry = Button(this).apply {
            text = "Try XR camera"
            setOnClickListener {
                permissionDeclined = false
                ensurePermissionAndScan()
            }
        }
        root.addView(description)
        root.addView(retry)
        root.addView(Button(this).apply {
            text = "Cancel"
            setOnClickListener { finishWithCancel() }
        })
        setContentView(root)
        if (!loadLibrary()) {
            description.text = "OpenXR scanner native library is unavailable."
            retry.isEnabled = false
            return
        }
        // onResume starts capture after Activity becomes foreground.
    }

    private fun ensurePermissionAndScan() {
        if (!active || isFinishing || isDestroyed || !loadLibrary()) return
        if (Build.VERSION.SDK_INT >= 23 &&
            checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            if (!permissionRequestPending && !permissionDeclined) {
                permissionRequestPending = true
                requestPermissions(arrayOf(Manifest.permission.CAMERA), CAMERA_PERMISSION_REQUEST)
            }
            return
        }
        if (!scanning.compareAndSet(false, true)) {
            // onResume may race the worker still unwinding from onPause.
            // Request exactly one restart after that worker has exited.
            restartWhenIdle = true
            return
        }
        restartWhenIdle = false
        retry.isEnabled = false
        val token = nextScanToken.incrementAndGet()
        scanToken = token
        description.text = "Scanning PICO XR color cameras…"
        executor.execute {
            var code: String? = null
            var error = "XR scanner unavailable"
            try {
                code = scanNative(20000L, token)
                error = lastNativeError()
            } catch (_: UnsatisfiedLinkError) {
                error = "OpenXR scanner native symbols unavailable"
            } catch (_: Exception) {
                error = "XR scanner failed"
            }
            val found = code
            val diagnostic = error
            mainHandler.post {
                // The next scan must never receive an older scan's callback.
                if (scanToken != token) return@post
                scanning.set(false)
                scanToken = 0L
                if (isFinishing || isDestroyed) return@post
                if (!active) {
                    retry.isEnabled = true
                    return@post
                }
                val invalidated = invalidatedScanToken == token
                if (!invalidated && !found.isNullOrEmpty()) {
                    setResult(RESULT_OK, Intent().putExtra(EXTRA_QR, found))
                    finish()
                    return@post
                }
                if (restartWhenIdle) {
                    restartWhenIdle = false
                    ensurePermissionAndScan()
                    return@post
                }
                description.text = if (invalidated) {
                    "Previous scan stopped when the window lost focus. Try again."
                } else {
                    // No frame bytes or scanned QR contents in diagnostics.
                    diagnostic
                }
                retry.isEnabled = true
            }
        }
    }

    /**
     * The native scan thread calls this on its own JNI thread.
     * A PlanarYUVLuminanceSource accepts a tightly packed grayscale plane.
     * ZXing runs locally and no screenshot is saved.
     */
    @Suppress("unused")
    private fun decodeQrFrame(gray: ByteArray, width: Int, height: Int): String? {
        if (width <= 0 || height <= 0 || width > 1024 || height > 1024 ||
            gray.size != width * height) return null
        return try {
            val source = PlanarYUVLuminanceSource(gray, width, height, 0, 0, width, height, false)
            val bitmap = BinaryBitmap(HybridBinarizer(source))
            reader.decode(bitmap, hints).text
        } catch (_: ReaderException) {
            null
        } finally {
            reader.reset()
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<out String>, grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == CAMERA_PERMISSION_REQUEST) {
            permissionRequestPending = false
            permissionDeclined = grantResults.firstOrNull() != PackageManager.PERMISSION_GRANTED
            if (!permissionDeclined) {
                ensurePermissionAndScan()
            } else {
                description.text = "Camera permission denied. Return to Fluxdo to import a QR image."
                retry.isEnabled = true
            }
        }
    }

    override fun onResume() {
        super.onResume()
        active = true
        if (loadLibrary()) ensurePermissionAndScan()
    }

    override fun onPause() {
        active = false
        // Any result computed during the transition to background is stale,
        // even if a native frame finished decoding just before cancellation.
        invalidatedScanToken = scanToken
        if (nativeLoaded && scanToken != 0L) cancelNative(scanToken)
        super.onPause()
    }

    private fun finishWithCancel() {
        if (nativeLoaded && scanToken != 0L) cancelNative(scanToken)
        setResult(RESULT_CANCELED)
        finish()
    }

    override fun onDestroy() {
        if (nativeLoaded && scanToken != 0L) cancelNative(scanToken)
        executor.shutdown()
        mainHandler.removeCallbacksAndMessages(null)
        super.onDestroy()
    }
}
