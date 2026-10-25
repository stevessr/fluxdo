package com.github.lingyan000.fluxdo.plugin.web_session

import android.app.Activity
import android.content.Context
import android.content.SharedPreferences
import android.os.Handler
import android.os.Looper
import android.view.View
import android.webkit.CookieManager
import android.webkit.WebStorage
import android.webkit.WebView

/**
 * Each installed companion owns its WebView cookie/storage jar. We never copy
 * credentials from FluxDO Core. Switching account slots clears the companion
 * jar before exposing another user's WebView.
 *
 * CookieManager.removeAllCookies is asynchronous. Multiple Activity launches
 * can arrive before the callback, so they must share ONE in-flight purge;
 * only the newest pending view may be shown after the purge completes.
 */
object PluginWebSession {
    private const val PREFS = "fluxdo_isolated_web_account"
    private const val LAST_SLOT = "last_slot"
    private val digest = Regex("^[0-9a-f]{64}$")

    private data class PendingOpen(
        val activity: Activity,
        val view: WebView,
        val slot: String,
        val homeUrl: String,
        val preferences: SharedPreferences,
    )

    // All access is on the Android main thread.
    private var clearing = false
    private var pending: PendingOpen? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    fun load(
        activity: Activity,
        view: WebView,
        requestedSlot: String?,
        homeUrl: String,
    ) {
        check(Looper.myLooper() == Looper.getMainLooper()) {
            "WebView session changes must run on the UI thread"
        }
        val slot = requestedSlot?.takeIf { it == "guest" || digest.matches(it) }
            ?: "guest"
        val preferences = activity.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

        // Block network activity and prevent a stale page from becoming visible
        // even if a second launch arrives during the asynchronous purge.
        view.visibility = View.INVISIBLE
        view.stopLoading()
        view.loadUrl("about:blank")

        if (!clearing && slot != "guest" &&
            slot == preferences.getString(LAST_SLOT, null)) {
            view.visibility = View.VISIBLE
            view.loadUrl(homeUrl)
            return
        }

        // Invalidate the persisted slot BEFORE the async boundary. A process
        // death mid-purge can never cause the next launch to trust old cookies.
        if (!preferences.edit().remove(LAST_SLOT).commit()) {
            // If a second launch cannot invalidate the slot, revoke the
            // previous pending launch as well. Never show stale account data.
            pending = null
            return
        }
        pending = PendingOpen(activity, view, slot, homeUrl, preferences)
        if (clearing) return

        clearing = true
        try {
            CookieManager.getInstance().removeAllCookies {
            mainHandler.post {
                val cleared = try {
                    CookieManager.getInstance().flush()
                    WebStorage.getInstance().deleteAllData()
                    true
                } catch (_: Exception) {
                    false
                }
                val open = pending
                pending = null
                clearing = false
                if (!cleared || open == null ||
                    open.activity.isFinishing || open.activity.isDestroyed) {
                    // Leave the slot invalidated; the next launch must purge again.
                    return@post
                }
                val cacheCleared = try {
                    open.view.clearCache(true)
                    open.view.clearHistory()
                    true
                } catch (_: Exception) {
                    false
                }
                if (!cacheCleared || !open.preferences.edit()
                        .putString(LAST_SLOT, open.slot).commit()) {
                    // Cookies or view state might be only partially cleared;
                    // refuse to expose any prior authenticated page.
                    return@post
                }
                open.view.visibility = View.VISIBLE
                open.view.loadUrl(open.homeUrl)
            }
        }
        } catch (_: Exception) {
            pending = null
            clearing = false
            // LAST_SLOT has already been invalidated. Retry requires a fresh
            // purge rather than trusting the old cookie jar.
        }
    }
}
