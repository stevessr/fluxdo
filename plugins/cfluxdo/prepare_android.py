#!/usr/bin/env python3
"""将指定 CFluxDo 原生功能构建为无桌面入口的 Fluxdo 外部插件。"""

from __future__ import annotations

import argparse
from pathlib import Path
import re
import xml.etree.ElementTree as ET

ANDROID_NS = "http://schemas.android.com/apk/res/android"
ANDROID = "{" + ANDROID_NS + "}"
ACTION = "com.github.lingyan000.fluxdo.action.PLUGIN"
API_META = "com.github.lingyan000.fluxdo.plugin.API_VERSION"
CATEGORY_META = "com.github.lingyan000.fluxdo.plugin.CATEGORY"
AUTH_SCHEME = "discourse"
AUTH_HOST = "auth_redirect"
ET.register_namespace("android", ANDROID_NS)

PLUGINS = {
    "cdk": {
        "package": "com.github.lingyan000.fluxdo.plugin.cdk",
        "label": "LINUX DO CDK",
        "target": "plugin_cdk_main.dart",
    },
    "ldshop": {
        "package": "com.github.lingyan000.fluxdo.plugin.ldshop",
        "label": "LD 士多",
        "target": "plugin_ldshop_main.dart",
    },
}


def patch(root: Path, plugin: str) -> None:
    config = PLUGINS[plugin]
    manifest = root / "android/app/src/main/AndroidManifest.xml"
    gradle = root / "android/app/build.gradle.kts"

    tree = ET.parse(manifest)
    app = tree.getroot().find("application")
    if app is None:
        raise RuntimeError("missing Android application element")
    app.set(ANDROID + "label", config["label"])

    targets = [
        a for a in app.findall("activity")
        if a.get(ANDROID + "name") == ".MainActivity"
    ]
    if len(targets) != 1:
        raise RuntimeError("expected one .MainActivity")
    main = targets[0]
    main.set(ANDROID + "exported", "true")

    # 移除主站链接/桌面入口；仅保留精确匹配的 Discourse 授权回调。
    # 不得注册整个 discourse:// scheme，否则会抢占其他客户端的链接。
    for activity in app.findall("activity") + app.findall("activity-alias"):
        for entry in list(activity.findall("intent-filter")):
            activity.remove(entry)

    for entry in list(main.findall("meta-data")):
        if entry.get(ANDROID + "name") in {API_META, CATEGORY_META}:
            main.remove(entry)
    metadata = ET.SubElement(main, "meta-data")
    metadata.set(ANDROID + "name", API_META)
    metadata.set(ANDROID + "value", "1")
    category_meta = ET.SubElement(main, "meta-data")
    category_meta.set(ANDROID + "name", CATEGORY_META)
    category_meta.set(ANDROID + "value", "app")

    entry = ET.SubElement(main, "intent-filter")
    action = ET.SubElement(entry, "action")
    action.set(ANDROID + "name", ACTION)
    category = ET.SubElement(entry, "category")
    category.set(ANDROID + "name", "android.intent.category.DEFAULT")

    # UserApiKeyLoginFlow 使用 Discourse 站点默认白名单内的固定回调。
    # Flutter app_links 必须从 Android 收到 VIEW Intent 才能完成 OTP 兑换。
    auth = ET.SubElement(main, "intent-filter")
    auth_action = ET.SubElement(auth, "action")
    auth_action.set(ANDROID + "name", "android.intent.action.VIEW")
    for name in ("android.intent.category.DEFAULT", "android.intent.category.BROWSABLE"):
        auth_category = ET.SubElement(auth, "category")
        auth_category.set(ANDROID + "name", name)
    auth_data = ET.SubElement(auth, "data")
    auth_data.set(ANDROID + "scheme", AUTH_SCHEME)
    auth_data.set(ANDROID + "host", AUTH_HOST)

    # 购物与 CDK 不需要安装其他 APK 或扫描所有已安装应用。
    for permission in list(tree.getroot().findall("uses-permission")):
        if permission.get(ANDROID + "name") in {
            "android.permission.REQUEST_INSTALL_PACKAGES",
            "android.permission.QUERY_ALL_PACKAGES",
        }:
            tree.getroot().remove(permission)

    ET.indent(tree, space="    ")
    tree.write(manifest, encoding="unicode", xml_declaration=True)

    content = gradle.read_text(encoding="utf-8")
    pattern = r'applicationId\s*=\s*"com\.github\.molchuan\.cfluxdo"'
    updated, count = re.subn(
        pattern,
        'applicationId = "' + config["package"] + '"',
        content,
    )
    if count != 1:
        raise RuntimeError("CFluxDo Gradle applicationId changed; review upstream")
    gradle.write_text(updated, encoding="utf-8")
    verify(root, plugin)


def verify(root: Path, plugin: str) -> None:
    config = PLUGINS[plugin]
    tree = ET.parse(root / "android/app/src/main/AndroidManifest.xml")
    app = tree.getroot().find("application")
    assert app is not None
    assert app.get(ANDROID + "label") == config["label"]
    matches = []
    auth_callbacks = []
    for activity in app.findall("activity") + app.findall("activity-alias"):
        for entry in activity.findall("intent-filter"):
            names = {
                a.get(ANDROID + "name") for a in entry.findall("action")
            }
            categories = {
                c.get(ANDROID + "name") for c in entry.findall("category")
            }
            assert "android.intent.action.MAIN" not in names
            assert "android.intent.category.LAUNCHER" not in categories
            if ACTION in names:
                assert names == {ACTION}
                assert categories == {"android.intent.category.DEFAULT"}
                assert not entry.findall("data")
                assert activity.get(ANDROID + "exported") == "true"
                matches.append(activity)
            elif "android.intent.action.VIEW" in names:
                # 任何 HTTPS / broad custom-scheme 捕获都应被拒绝。
                assert activity.get(ANDROID + "name") == ".MainActivity"
                assert names == {"android.intent.action.VIEW"}
                assert categories == {
                    "android.intent.category.DEFAULT",
                    "android.intent.category.BROWSABLE",
                }
                data = entry.findall("data")
                assert len(data) == 1
                assert data[0].attrib == {
                    ANDROID + "scheme": AUTH_SCHEME,
                    ANDROID + "host": AUTH_HOST,
                }
                auth_callbacks.append(activity)
            else:
                raise AssertionError("unexpected intent filter in external plugin")
    assert len(matches) == 1, "exactly one exported Fluxdo plugin entry required"
    assert len(auth_callbacks) == 1, "exactly one narrow OAuth callback required"
    assert any(
        child.get(ANDROID + "name") == API_META
        and child.get(ANDROID + "value") == "1"
        for child in matches[0].findall("meta-data")
    ), "missing API version metadata"
    assert any(
        child.get(ANDROID + "name") == CATEGORY_META
        and child.get(ANDROID + "value") == "app"
        for child in matches[0].findall("meta-data")
    ), "business plugins must be categorized as app"
    permissions = {
        item.get(ANDROID + "name")
        for item in tree.getroot().findall("uses-permission")
    }
    assert "android.permission.QUERY_ALL_PACKAGES" not in permissions
    assert "android.permission.REQUEST_INSTALL_PACKAGES" not in permissions
    gradle = (root / "android/app/build.gradle.kts").read_text(encoding="utf-8")
    assert 'applicationId = "' + config["package"] + '"' in gradle
    print(f"{plugin}: plugin manifest OK; package={config['package']}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--plugin", choices=PLUGINS, required=True)
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args()
    if args.verify_only:
        verify(args.root, args.plugin)
    else:
        patch(args.root, args.plugin)


if __name__ == "__main__":
    main()
