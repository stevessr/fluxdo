#!/usr/bin/env python3
"""Fail fast if the independently installable plugin APK contract drifts."""
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
ANDROID = "{http://schemas.android.com/apk/res/android}"
MAIN_PACKAGE = "com.github.lingyan000.fluxdo"
PERMISSION = MAIN_PACKAGE + ".permission.BIND_PLUGIN"
VERSION = "1"

PLUGINS = {
    "plugin_deviceinfo": (
        MAIN_PACKAGE + ".plugin.deviceinfo",
        MAIN_PACKAGE + ".plugin.deviceinfo.DeviceInfoService",
    ),
    "plugin_network": (
        MAIN_PACKAGE + ".plugin.network",
        MAIN_PACKAGE + ".plugin.network.NetworkService",
    ),
    "plugin_cdk": (
        MAIN_PACKAGE + ".plugin.cdk",
        MAIN_PACKAGE + ".plugin.cdk.CdkPluginService",
    ),
    "plugin_ldc": (
        MAIN_PACKAGE + ".plugin.ldc",
        MAIN_PACKAGE + ".plugin.ldc.LdcPluginService",
    ),
    "plugin_ldc_reward": (
        MAIN_PACKAGE + ".plugin.ldc_reward",
        MAIN_PACKAGE + ".plugin.ldc_reward.LdcRewardPluginService",
    ),
}


def check(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def attr(node: ET.Element, key: str) -> str | None:
    return node.get(ANDROID + key)


def main() -> None:
    manifest = ET.parse(ANDROID_PATH := ROOT / "android/app/src/main/AndroidManifest.xml").getroot()
    check(any(attr(item, "name") == PERMISSION and
              attr(item, "protectionLevel") == "signature"
              for item in manifest.findall("permission")),
          f"{ANDROID_PATH}: missing signature protection")
    queried = {attr(item, "name") for item in manifest.findall("./queries/package")}

    host = (ROOT / "android/app/src/main/kotlin/com/github/lingyan000/fluxdo/"
            "OptionalPluginChannel.kt").read_text()
    protocol = (ROOT / "android/plugin_api/src/main/kotlin/com/github/"
                "lingyan000/fluxdo/plugin/api/PluginProtocol.kt").read_text()
    settings = (ROOT / "android/settings.gradle.kts").read_text()
    check(re.search(r"const val VERSION\s*=\s*" + VERSION + r"\b", protocol) is not None,
          "Unexpected plugin wire protocol version")
    check('include(":plugin_api")' in settings, "Missing Gradle plugin_api module")
    check('include(":plugin_web_session")' in settings,
          "Missing LDC/CDK-only WebView session library")
    for companion in ("plugin_ldc", "plugin_cdk"):
        deps = (ROOT / f"android/{companion}/build.gradle.kts").read_text()
        check('implementation(project(":plugin_web_session"))' in deps,
              f"{companion}: WebView isolation must be compiled inside companion APK")
    host_gradle = (ROOT / "android/app/build.gradle.kts").read_text()
    check('implementation(project(":plugin_web_session"))' not in host_gradle,
          "WebView session code leaked into Core's dependencies")


    for module, (package, service_name) in PLUGINS.items():
        check(f'include(":{module}")' in settings, f"Missing Gradle {module}")
        gradle = (ROOT / f"android/{module}/build.gradle.kts").read_text()
        check(f'applicationId = "{package}"' in gradle,
              f"{module}: wrong application ID")
        check(package in queried, f"{module}: not visible through <queries>")
        check(f'"{package}"' in host and f'"{service_name}"' in host,
              f"{module}: host allowlist doesn't match")
        plugin_manifest = ET.parse(ROOT / f"android/{module}/src/main/AndroidManifest.xml").getroot()
        check(any(attr(item, "name") == PERMISSION
                  for item in plugin_manifest.findall("uses-permission")),
              f"{module}: missing signature permission request")
        services = plugin_manifest.findall("./application/service")
        check(len(services) == 1, f"{module}: expected one exported service")
        service = services[0]
        service_class = attr(service, "name") or ""
        if service_class.startswith("."):
            service_class = package + service_class
        check(service_class == service_name, f"{module}: wrong service class")
        check(attr(service, "exported") == "true", f"{module}: service not exported")
        check(attr(service, "permission") == PERMISSION,
              f"{module}: service must require signature permission")
        check(any(attr(meta, "name") == MAIN_PACKAGE + ".plugin.PROTOCOL"
                  and attr(meta, "value") == VERSION
                  for meta in service.findall("meta-data")),
              f"{module}: protocol version mismatch")

    # LDC/CDK host account switches must not reuse the previous app's
    # authenticated WebView session. No cookie/token may cross the APK IPC.
    web_session = (ROOT / "android/plugin_web_session/src/main/kotlin/com/github/"
                   "lingyan000/fluxdo/plugin/web_session/PluginWebSession.kt").read_text()
    account_host = (ROOT / "lib/services/android_optional_plugin_service.dart").read_text()
    metaverse_overlay = (ROOT / "android_modular/core_overlay/lib/pages/metaverse_page.dart").read_text()
    plugin_manager = (ROOT / "lib/pages/android_plugins_page.dart").read_text()
    for feature in (
        'CookieManager.getInstance().removeAllCookies',
        'WebStorage.getInstance().deleteAllData()',
        'view.visibility = View.INVISIBLE',
        'slot != "guest"',
    ):
        check(feature in web_session, f"WebView account isolation missing: {feature}")
    check('Intent.FLAG_ACTIVITY_CLEAR_TASK' in host,
          "Companion launches must clear previously authenticated Activity task")
    check(
        "'account_slot'" in host and "'accountSlot'" in host and
        "^[0-9a-f]{64}$" in host,
        "Host must pass only validated opaque account slots",
    )
    for feature in ("sessionSlotForUsername", "sha256.convert"):
        check(feature in account_host,
              f"Flutter account partition hashing missing: {feature}")
    check("sessionSlotForUsername" in metaverse_overlay and
          "sessionSlotForUsername" in plugin_manager,
          "Metaverse launches must receive current account slot")
    for name in ("cdk", "ldc"):
        activity = (ROOT / f"android/plugin_{name}/src/main/kotlin/com/github/"
                    f"lingyan000/fluxdo/plugin/{name}/{name.capitalize()}Activity.kt").read_text()
        check("PluginWebSession.load(" in activity and "account_slot" in activity,
              f"{name}: must clear old WebView profile before loading site")

    sticker_host = (ROOT / "android/app/src/main/kotlin/com/github/"
                    "lingyan000/fluxdo/StickerCompanionChannel.kt").read_text()
    sticker_native = (ROOT / "android_companions/sticker/StickerActivity.kt").read_text()
    sticker_builder = (ROOT / "scripts/ci/build_sticker_companion.py").read_text()
    check(MAIN_PACKAGE + ".plugin.sticker" in queried,
          "Missing sticker package visibility")
    check("PackageManager.SIGNATURE_MATCH" in sticker_host,
          "Sticker host must validate same signer")
    check('"$PACKAGE.files"' in sticker_host, "Sticker URI authority not validated")
    check("FileProvider.getUriForFile" in sticker_native,
          "Sticker companion must export grantable content URIs")
    check("android/key.properties" in sticker_builder,
          "Sticker release signer must refer to main keystore")
    for name in ("cdk", "ldc", "ldc_reward"):
        entry = (ROOT / f"android/plugin_{name}/src/main/AndroidManifest.xml")
        root = ET.parse(entry).getroot()
        activities = root.findall("./application/activity")
        check(len(activities) == 1 and
              attr(activities[0], "permission") == PERMISSION and
              attr(activities[0], "exported") == "true",
              f"{name}: companion Activity must require same-signature permission")

    print("Android optional APK contract: OK (five native modules + Flutter sticker companion, signed IPC, protocol v1)")


if __name__ == "__main__":
    try:
        main()
    except (AssertionError, OSError, ET.ParseError) as error:
        print(f"Android optional APK contract: FAILED: {error}", file=sys.stderr)
        sys.exit(1)
