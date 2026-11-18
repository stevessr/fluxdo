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

    # 只暴露受 Fluxdo 管理的插件入口：不得抢主站 HTTPS 深链、授权回调或桌面启动器。
    for activity in app.findall("activity") + app.findall("activity-alias"):
        for entry in list(activity.findall("intent-filter")):
            activity.remove(entry)

    for entry in list(main.findall("meta-data")):
        if entry.get(ANDROID + "name") == API_META:
            main.remove(entry)
    metadata = ET.SubElement(main, "meta-data")
    metadata.set(ANDROID + "name", API_META)
    metadata.set(ANDROID + "value", "1")

    entry = ET.SubElement(main, "intent-filter")
    action = ET.SubElement(entry, "action")
    action.set(ANDROID + "name", ACTION)
    category = ET.SubElement(entry, "category")
    category.set(ANDROID + "name", "android.intent.category.DEFAULT")

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
    for activity in app.findall("activity") + app.findall("activity-alias"):
        for entry in activity.findall("intent-filter"):
            names = {
                a.get(ANDROID + "name") for a in entry.findall("action")
            }
            categories = {
                c.get(ANDROID + "name") for c in entry.findall("category")
            }
            assert "android.intent.action.MAIN" not in names
            assert "android.intent.action.VIEW" not in names
            assert "android.intent.category.LAUNCHER" not in categories
            if ACTION in names:
                assert "android.intent.category.DEFAULT" in categories
                assert activity.get(ANDROID + "exported") == "true"
                matches.append(activity)
    assert len(matches) == 1, "exactly one exported Fluxdo plugin entry required"
    assert any(
        child.get(ANDROID + "name") == API_META
        and child.get(ANDROID + "value") == "1"
        for child in matches[0].findall("meta-data")
    ), "missing API version metadata"
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
