package com.github.lingyan000.fluxdo

import android.os.Bundle
import android.os.SystemClock

/**
 * Each additional panel owns a real Android task and Flutter engine.
 *
 * PICO supports up to ten panels total; count the primary MainActivity as
 * one, leaving at most nine additional FluxDO panels. Reservation tokens
 * protect against rapid taps while the Android shell starts an Activity.
 */
class PicoVrWindowActivity : MainActivity() {
    companion object {
        const val MAX_TOTAL_WINDOWS = 10
        private const val MAX_EXTRA_WINDOWS = MAX_TOTAL_WINDOWS - 1
        private const val LAUNCH_TIMEOUT_MS = 15000L

        const val EXTRA_TOPIC_ID = "com.fluxdo.pico.window.TOPIC_ID"
        const val EXTRA_POST_NUMBER = "com.fluxdo.pico.window.POST_NUMBER"
        const val EXTRA_RESERVATION_ID = "com.fluxdo.pico.window.RESERVATION_ID"

        private var liveWindows = 0
        private var nextReservationId = 0L
        private val pendingLaunches = mutableMapOf<Long, Long>()

        @Synchronized
        private fun pruneExpiredLaunches() {
            val now = SystemClock.elapsedRealtime()
            pendingLaunches.entries.removeAll { now - it.value > LAUNCH_TIMEOUT_MS }
        }

        /** Null means the app already has nine secondary (ten total) panels. */
        @Synchronized
        fun reserveLaunch(): Long? {
            pruneExpiredLaunches()
            if (liveWindows + pendingLaunches.size >= MAX_EXTRA_WINDOWS) return null
            val id = ++nextReservationId
            pendingLaunches[id] = SystemClock.elapsedRealtime()
            return id
        }

        @Synchronized
        fun cancelLaunch(reservationId: Long) {
            pendingLaunches.remove(reservationId)
        }

        @Synchronized
        private fun registerWindow(reservationId: Long?) {
            if (reservationId != null) pendingLaunches.remove(reservationId)
            liveWindows++
        }

        @Synchronized
        private fun unregisterWindow() {
            if (liveWindows > 0) liveWindows--
        }

        /** Lightweight snapshot; does not enumerate Camera2 on every tap. */
        @Synchronized
        fun windowStatus(): Map<String, Int> {
            pruneExpiredLaunches()
            return mapOf(
                "maxWindows" to MAX_TOTAL_WINDOWS,
                "openWindows" to (1 + liveWindows),
                "pendingWindows" to pendingLaunches.size,
                "availableSlots" to (MAX_EXTRA_WINDOWS - liveWindows - pendingLaunches.size).coerceAtLeast(0),
            )
        }
    }

    /**
     * Consume the topic from this Activity's Intent only, not shared app
     * state. Independent panels can open different topics simultaneously.
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
        val reservationId = intent?.let {
            if (it.hasExtra(EXTRA_RESERVATION_ID)) {
                it.getLongExtra(EXTRA_RESERVATION_ID, -1L).takeIf { id -> id > 0 }
            } else {
                null
            }
        }
        registerWindow(reservationId)
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
