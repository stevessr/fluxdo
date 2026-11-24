package com.github.stevessr.fluxdo.resources;

import android.app.Activity;
import android.app.AlertDialog;
import android.os.Bundle;

public final class PackActivity extends Activity {
    @Override public void onCreate(Bundle saved) {
        super.onCreate(saved);
        new AlertDialog.Builder(this)
            .setTitle("Fluxdo Offline Fonts & Emoji")
            .setMessage("Offline resources are available in Fluxdo appearance settings.\n离线资源已安装，在 Fluxdo 外观设置中选择字体或 Emoji 风格即可使用。\nLicense notices: assets/licenses/")
            .setPositiveButton(android.R.string.ok, (dialog, which) -> finish())
            .setOnCancelListener(dialog -> finish())
            .show();
    }
}
