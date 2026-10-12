package com.github.lingyan000.fluxdo.plugin.ldc

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.webkit.WebView
import android.webkit.WebViewClient
import android.webkit.WebResourceRequest

/**
 * Standalone LDC site view. Uses its own WebView cookie store;
 * host OAuth, session and balances deliberately remain in the core until a
 * credential delegation protocol with account revocation is implemented.
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
        view.loadUrl("https://credit.linux.do")
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
