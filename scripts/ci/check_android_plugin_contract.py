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

    # Activity-based companions use the same allowlist/signature boundary.
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
    for name in ("cdk", "ldc"):
        entry = (ROOT / f"android/plugin_{name}/src/main/AndroidManifest.xml")
        root = ET.parse(entry).getroot()
        activities = root.findall("./application/activity")
        check(len(activities) == 1 and
              attr(activities[0], "permission") == PERMISSION and
              attr(activities[0], "exported") == "true",
              f"{name}: companion Activity must require same-signature permission")

    print("Android optional APK contract: OK (four native modules + Flutter sticker companion, signed IPC, protocol v1)")


if __name__ == "__main__":
    try:
        main()
    except (AssertionError, OSError, ET.ParseError) as error:
        print(f"Android optional APK contract: FAILED: {error}", file=sys.stderr)
        sys.exit(1)
