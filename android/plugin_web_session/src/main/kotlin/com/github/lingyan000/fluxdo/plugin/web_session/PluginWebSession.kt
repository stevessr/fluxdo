package com.github.lingyan000.fluxdo.plugin.web_session

import android.app.Activity
import android.content.Context
import android.view.View
import android.webkit.CookieManager
import android.webkit.WebStorage
import android.webkit.WebView

/**
 * Account-scoped session boundary shared as bytecode by independent LDC/CDK
 * APKs. WebView cookies are LOCAL to each installed companion package; they
 * are never copied to/from FluxDO Core. Only a SHA-256-derived account slot
 * arrives over the signed Activity intent.
 *
 * Android WebView does not offer a per-widget ephemeral CookieManager. On a
 * profile switch (including guest) we clear *this APK's* cookies and web
 * storage before allowing a WebView to display the origin.
 */
object PluginWebSession {
    private const val PREFS = "fluxdo_isolated_web_account"
    private const val LAST_SLOT = "last_slot"
    private val digest = Regex("^[0-9a-f]{64}$")

    fun load(
        activity: Activity,
        view: WebView,
        requestedSlot: String?,
        homeUrl: String,
    ) {
        val slot = requestedSlot?.takeIf { it == "guest" || digest.matches(it) }
            ?: "guest"
        val preferences = activity.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val previous = preferences.getString(LAST_SLOT, null)

        if (slot != "guest" && slot == previous) {
            view.loadUrl(homeUrl)
            return
        }

        // Don't expose the previous user's already-authenticated page while
        // CookieManager.removeAllCookies asynchronously purges the jar.
        view.visibility = View.INVISIBLE
        CookieManager.getInstance().removeAllCookies {
            activity.runOnUiThread {
                if (activity.isFinishing || activity.isDestroyed) return@runOnUiThread
                CookieManager.getInstance().flush()
                WebStorage.getInstance().deleteAllData()
                view.clearCache(true)
                view.clearHistory()
                preferences.edit().putString(LAST_SLOT, slot).apply()
                view.visibility = View.VISIBLE
                view.loadUrl(homeUrl)
            }
        }
    }
}
