package com.github.lingyan000.fluxdo.plugin.ldc

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import com.github.lingyan000.fluxdo.plugin.web_session.PluginWebSession
import android.view.Menu
import android.view.View
import android.view.MenuItem
import android.webkit.WebView
import android.webkit.WebViewClient
import android.webkit.WebResourceRequest

/**
 * Standalone LDC site view. Uses its own WebView cookie store;
 * host credentials are never copied; the APK clears cookies when the
 * hashed FluxDO account partition changes (including guest sessions).
 */
class LdcActivity : Activity() {
    private var browser: WebView? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val view = WebView(this)
        browser = view
        view.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            allowFileAccess = false
            allowContentAccess = false
            javaScriptCanOpenWindowsAutomatically = false
            setSupportMultipleWindows(false)
        }
        view.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(
                view: WebView?, request: WebResourceRequest?
            ): Boolean {
                val uri = request?.url ?: return true
                // OAuth widgets/iframes load cross-site resources; only
                // top-level navigation should be delegated to the browser.
                if (!request.isForMainFrame) return false
                val host = uri.host?.lowercase()
                val trusted = uri.scheme == "https" &&
                    host in setOf("credit.linux.do", "connect.linux.do", "linux.do")
                if (trusted) return false
                if (uri.scheme == "https" && host != null) {
                    try { startActivity(Intent(Intent.ACTION_VIEW, uri)) } catch (_: Exception) {}
                }
                return true
            }
        }
        setContentView(view)
        PluginWebSession.load(
            this, view, intent.getStringExtra("account_slot"),
            "https://credit.linux.do",
        )
    }

    override fun onCreateOptionsMenu(menu: Menu): Boolean {
        menu.add(0, 1, 0, "首页").setShowAsAction(MenuItem.SHOW_AS_ACTION_IF_ROOM)
        menu.add(0, 2, 1, "余额 / 我的信息")
        menu.add(0, 3, 2, "刷新").setShowAsAction(MenuItem.SHOW_AS_ACTION_IF_ROOM)
        menu.add(0, 4, 3, "清除插件登录状态")
        return true
    }

    override fun onOptionsItemSelected(item: MenuItem): Boolean {
        // Never allow the toolbar to navigate while account data is purging.
        if (item.itemId in 1..3 && browser?.visibility != View.VISIBLE) return true
        when (item.itemId) {
            1 -> browser?.loadUrl("https://credit.linux.do")
            2 -> browser?.loadUrl("https://credit.linux.do/api/v1/oauth/user-info")
            3 -> browser?.reload()
            4 -> browser?.let {
                // Guest sessions are intentionally transient. Clearing this
                // plugin never signs out the host app or another plugin.
                PluginWebSession.load(this, it, "guest", "https://credit.linux.do")
            }
            else -> return super.onOptionsItemSelected(item)
        }
        return true
    }

    override fun onDestroy() {
        browser?.apply {
            stopLoading()
            loadUrl("about:blank")
            destroy()
        }
        browser = null
        super.onDestroy()
    }
}
