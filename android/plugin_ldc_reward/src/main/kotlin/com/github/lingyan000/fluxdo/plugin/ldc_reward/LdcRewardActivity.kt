package com.github.lingyan000.fluxdo.plugin.ldc_reward

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.net.Uri
import android.os.Bundle

/**
 * The reward menu is its own updateable APK. It deliberately cannot send
 * payments without a reviewed idempotent transaction implementation.
 * Host passes only public post identity; no cookies, secrets or money.
 */
class LdcRewardActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val target = intent.getStringExtra("recipient_username")
            ?.trim()?.take(64).orEmpty()
        val userId = intent.getLongExtra("recipient_user_id", -1L)
        val destination = if (target.isNotEmpty() && userId > 0L) {
            "接收人：$target (#$userId)"
        } else {
            "未提供有效的接收人"
        }
        AlertDialog.Builder(this)
            .setTitle("LDC 打赏 · 独立插件")
            .setMessage(
                "$destination\n\n自动打赏交易尚未开放。请在 LDC 官方站点自行确认" +
                "收款人、额度及交易结果。此插件不读取 FluxDO 的密钥或 Cookie。"
            )
            .setPositiveButton("打开 LDC 官方站点") { _, _ ->
                try {
                    startActivity(Intent(Intent.ACTION_VIEW,
                        Uri.parse("https://credit.linux.do")))
                } catch (_: Exception) {
                    // Browser not installed; do not attempt any transfer.
                }
                finish()
            }
            .setNegativeButton("取消") { _, _ -> finish() }
            .setOnCancelListener { finish() }
            .show()
    }
}
