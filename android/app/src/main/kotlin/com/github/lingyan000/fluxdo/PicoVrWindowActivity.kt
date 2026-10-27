package com.github.lingyan000.fluxdo

import android.os.Bundle
import android.os.SystemClock

/**
 * A second Flutter engine / Android task. Restrict concurrent secondary
 * engines to avoid OOM on a VR headset. Reservations cover rapid repeated taps
 * before Activity.onCreate has run and expire if the shell rejects a launch.
 */
class PicoVrWindowActivity : MainActivity() {
    companion object {
        private const val MAX_EXTRA_WINDOWS = 3
        private const val LAUNCH_TIMEOUT_MS = 15000L
        private var liveWindows = 0
        private val pendingLaunches = mutableListOf<Long>()

        @Synchronized
        fun reserveLaunch(): Boolean {
            val now = SystemClock.elapsedRealtime()
            pendingLaunches.removeAll { now - it > LAUNCH_TIMEOUT_MS }
            if (liveWindows + pendingLaunches.size >= MAX_EXTRA_WINDOWS) return false
            pendingLaunches.add(now)
            return true
        }

        @Synchronized
        fun cancelLaunch() {
            if (pendingLaunches.isNotEmpty()) pendingLaunches.removeAt(0)
        }

        @Synchronized
        private fun registerWindow() {
            if (pendingLaunches.isNotEmpty()) pendingLaunches.removeAt(0)
            liveWindows++
        }

        @Synchronized
        private fun unregisterWindow() {
            if (liveWindows > 0) liveWindows--
        }
    }

    private var counted = false

    override fun onCreate(savedInstanceState: Bundle?) {
        registerWindow()
        counted = true
        try {
            super.onCreate(savedInstanceState)
        } catch (e: Throwable) {
            unregisterWindow()
            counted = false
            throw e
        }
    }

    override fun onDestroy() {
        try {
            super.onDestroy()
        } finally {
            if (counted) {
                unregisterWindow()
                counted = false
            }
        }
    }
}
