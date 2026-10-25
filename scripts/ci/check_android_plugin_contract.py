#!/usr/bin/env python3
"""Fail fast if the independently installable plugin APK contract drifts."""
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

from android_plugin_catalog import HOST_PACKAGE, load_catalog
from build_native_plugins import verify_source_graph
from generate_android_plugin_catalog import HOST_CATALOG, synchronize

ROOT = Path(__file__).resolve().parents[2]
ANDROID = "{http://schemas.android.com/apk/res/android}"
CATALOG = load_catalog()
MAIN_PACKAGE = HOST_PACKAGE
PERMISSION = MAIN_PACKAGE + ".permission.BIND_PLUGIN"
VERSION = str(CATALOG.protocol)
PLUGINS = {spec.module: (spec.package, spec.service) for spec in CATALOG.native}


def check(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def attr(node: ET.Element, key: str) -> str | None:
    return node.get(ANDROID + key)


def main() -> None:
    synchronize(check=True)
    verify_source_graph(ROOT, CATALOG)
    manifest = ET.parse(ANDROID_PATH := ROOT / "android/app/src/main/AndroidManifest.xml").getroot()
    check(any(attr(item, "name") == PERMISSION and
              attr(item, "protectionLevel") == "signature"
              for item in manifest.findall("permission")),
          f"{ANDROID_PATH}: missing signature protection")
    queried = {attr(item, "name") for item in manifest.findall("./queries/package")}

    host = (ROOT / "android/app/src/main/kotlin/com/github/lingyan000/fluxdo/"
            "OptionalPluginChannel.kt").read_text()
    host_catalog = (ROOT / HOST_CATALOG).read_text()
    check("private val specs = OptionalPluginCatalog.specs" in host,
          "Host must consume generated module allowlist")
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
        check(f'"{package}"' in host_catalog and f'"{service_name}"' in host_catalog,
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
        'if (clearing) return',
        'preferences.edit().remove(LAST_SLOT).commit()',
        'only the newest pending view',
        'pending = null',
        'val cacheCleared = try',
        'if (!cacheCleared',
    ):
        check(feature in web_session, f"WebView account isolation missing: {feature}")
    check('PluginProtocol.MAX_JSON_BYTES' in host and
          'JSONObject(raw)' in host, "Host must bound and parse plugin replies")
    plugin_service = (ROOT / "android/plugin_api/src/main/kotlin/com/github/"
                      "lingyan000/fluxdo/plugin/api/PluginService.kt").read_text()
    check(plugin_service.count("PluginProtocol.MAX_JSON_BYTES") >= 2,
          "Plugin service must bound both request and response UTF-8 bytes")
    payload_policy = (ROOT / "android/plugin_api/src/main/kotlin/com/github/"
                      "lingyan000/fluxdo/plugin/api/PluginPayloadContract.kt").read_text()
    policy_match = re.search(
        r"private val emptyOperations\\s*=\\s*setOf\\((.*?)\\)",
        payload_policy, re.S,
    )
    check(policy_match is not None, "Missing native empty-payload allowlist")
    empty_operations = set(re.findall(r'"([a-z][a-z0-9_]*\\.[a-z][a-z0-9_]*)"',
                                      policy_match.group(1)))
    special_operations = set(re.findall(r'operation\\s*==\\s*"([^"]+)"',
                                        payload_policy))
    declared_operations = {op for spec in CATALOG.native for op in spec.operations}
    check(empty_operations | special_operations == declared_operations and
          not (empty_operations & special_operations),
          "Native payload schema does not match the declarative operation catalog")
    for mandatory in (
        "PluginProtocol.MAX_JSON_BYTES",
        "payload.length() == 0",
        'payload.length() == 1 && payload.has("hostname")',
        'payload.opt("hostname") as? String',
        "hostnameLabel.matches(it)",
    ):
        check(mandatory in payload_policy, f"Native payload policy missing: {mandatory}")
    check("PluginPayloadContract.normalize" in host and
          "PluginPayloadContract.normalize" in plugin_service,
          "Host and companion must both validate IPC payload schemas")
    check('MAX_JSON_BYTES = 8192' in protocol,
          "Unexpected IPC size limit")
    check('Intent.FLAG_ACTIVITY_CLEAR_TASK' in host,
          "Companion launches must clear previously authenticated Activity task")
    check(
        "account_slot" in host and "accountSlot" in host and
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
