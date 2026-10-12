#!/usr/bin/env python3
"""Build a real, separately installable Flutter sticker companion APK.

Runs outside the root Dart workspace to avoid nested-workspace conflicts.
Requires root 'dart tool/project_prep.dart test' to have generated l10n and
avatar delta assets. Uses the same applicationId on every update.
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "android_companions/sticker"
PACKAGE = "com.github.lingyan000.fluxdo.plugin.sticker"
ANDROID_NS = "{http://schemas.android.com/apk/res/android}"


def execute(*args: str, cwd: Path) -> None:
    print("+", " ".join(args), flush=True)
    subprocess.run(args, cwd=cwd, check=True)


def setup_project(target: Path) -> None:
    execute(
        "flutter", "create", "--platforms=android", "--org=com.github.lingyan000.fluxdo.plugin",
        "--project-name=sticker", "--no-pub", str(target),
        cwd=ROOT,
    )
    yaml = (SOURCE / "pubspec.yaml").read_text()
    # This is a standalone project in a temporary directory, not a nested
    # Flutter workspace member. The path dependency still reuses real sources.
    yaml = yaml.replace("path: ../..", f"path: {ROOT.as_posix()}")
    (target / "pubspec.yaml").write_text(yaml)
    (target / "lib/main.dart").write_text((SOURCE / "lib/main.dart").read_text())

    source_assets = ROOT / "assets/images/avater"
    for name in ["stevessr", "llm", "touhou", "blue_archive", "witch_judgment"]:
        source_dir = source_assets / name
        dest = target / "assets/images/avater" / name
        assert source_dir.is_dir(), f"Missing avatar assets: {source_dir}"
        shutil.copytree(source_dir, dest, dirs_exist_ok=True)
    for name in ["stevessr", "llm"]:
        assert (target / f"assets/images/avater/{name}/manifest.json").is_file(), (
            "Missing generated avatar manifests; run dart tool/project_prep.dart test"
        )

    font = ROOT / "assets/fonts/MiSansVF.ttf"
    assert font.is_file(), f"Missing MiSans font: {font}"
    outfont = target / "assets/fonts/MiSansVF.ttf"
    outfont.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(font, outfont)

    src = target / "android/app/src/main"
    kotlin_path = src / "kotlin/com/github/lingyan000/fluxdo/plugin/sticker"
    kotlin_path.mkdir(parents=True, exist_ok=True)
    shutil.copy2(SOURCE / "StickerActivity.kt", kotlin_path / "StickerActivity.kt")
    paths_xml = src / "res/xml/companion_file_paths.xml"
    paths_xml.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(SOURCE / "android_file_paths.xml", paths_xml)

    ET.register_namespace("android", "http://schemas.android.com/apk/res/android")
    manifest_path = src / "AndroidManifest.xml"
    manifest = ET.parse(manifest_path)
    application = manifest.getroot().find("application")
    assert application is not None
    activity = application.find("activity")
    assert activity is not None
    activity.set(ANDROID_NS + "name", ".StickerActivity")
    activity.set(ANDROID_NS + "exported", "true")
    application.set(ANDROID_NS + "label", "FluxDO StevesSR")
    provider = ET.SubElement(application, "provider", {
        ANDROID_NS + "name": "androidx.core.content.FileProvider",
        ANDROID_NS + "authorities": "${applicationId}.files",
        ANDROID_NS + "exported": "false",
        ANDROID_NS + "grantUriPermissions": "true",
    })
    ET.SubElement(provider, "meta-data", {
        ANDROID_NS + "name": "android.support.FILE_PROVIDER_PATHS",
        ANDROID_NS + "resource": "@xml/companion_file_paths",
    })
    manifest.write(manifest_path, encoding="utf-8", xml_declaration=True)

    build_file = target / "android/app/build.gradle.kts"
    gradle = build_file.read_text()
    # Flutter currently emits a Kotlin DSL Android project. Preserve generated
    # Flutter Gradle wiring; only inject the APK's native bridge requirements.
    assert "flutter.compileSdkVersion" in gradle
    gradle = gradle.replace(
        "ndkVersion = flutter.ndkVersion",
        'ndkVersion = "28.2.13676358"',
    )
    if "dependencies {" not in gradle:
        gradle += '\n\ndependencies {\n    implementation("androidx.core:core:1.16.0")\n}\n'
    else:
        gradle = gradle.replace(
            "dependencies {",
            'dependencies {\n    implementation("androidx.core:core:1.16.0")',
            1,
        )
    build_file.write_text(gradle)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=["debug", "release"], default="debug")
    parser.add_argument("--abi", choices=["android-arm", "android-arm64", "android-x64"],
                        default="android-arm64")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="fluxdo-sticker-companion-") as temp:
        target = Path(temp) / "sticker"
        setup_project(target)
        execute("flutter", "pub", "get", cwd=target)
        execute("flutter", "build", "apk", "--" + args.mode,
                "--target-platform", args.abi, "--no-pub", cwd=target)
        apk_dir = target / "build/app/outputs/flutter-apk"
        candidates = list(apk_dir.glob("*.apk"))
        assert len(candidates) == 1, f"Expected single APK: {candidates}"
        dest = ROOT / "build/plugin_sticker"
        dest.mkdir(parents=True, exist_ok=True)
        out = dest / f"fluxdo-sticker-{args.abi}-{args.mode}.apk"
        shutil.copy2(candidates[0], out)
        print(f"Independent companion APK: {out} ({out.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
