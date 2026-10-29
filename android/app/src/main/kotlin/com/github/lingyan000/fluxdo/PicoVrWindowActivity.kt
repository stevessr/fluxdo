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
        const val EXTRA_TOPIC_ID = "com.fluxdo.pico.window.TOPIC_ID"
        const val EXTRA_POST_NUMBER = "com.fluxdo.pico.window.POST_NUMBER"
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

    /**
     * The intent belongs to this Activity/task. Consume it only after the
     * corresponding Flutter engine has finished its own initial navigation.
     * No static process-global pending topic: multiple panels may start at once.
     */
    fun consumeLaunchRequest(): Map<String, Int>? {
        val launchIntent = intent ?: return null
        val topicId = launchIntent.getIntExtra(EXTRA_TOPIC_ID, -1)
        if (topicId <= 0) return null
        val postNumber = launchIntent.getIntExtra(EXTRA_POST_NUMBER, 0)
        launchIntent.removeExtra(EXTRA_TOPIC_ID)
        launchIntent.removeExtra(EXTRA_POST_NUMBER)
        return mapOf("topicId" to topicId, "postNumber" to postNumber)
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
