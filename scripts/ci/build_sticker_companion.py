#!/usr/bin/env python3
"""Build a real, separately installable Flutter sticker companion APK.

Runs outside the root Dart workspace to avoid nested-workspace conflicts.
Requires root 'dart tool/project_prep.dart test' to have generated l10n and
avatar delta assets. Uses the same applicationId on every update.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shutil
from zipfile import ZipFile
import subprocess
import tempfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "android_companions/sticker"
PACKAGE = "com.github.lingyan000.fluxdo.plugin.sticker"
ANDROID_NS = "{http://schemas.android.com/apk/res/android}"

# Copy only the editor's Dart import closure. No entire FluxDO package, no
# account/network/chat code, and no broad plugin registration in the APK.
DRAWING_SOURCES = (
    "lib/pages/stevessr_generator_page.dart",
    "lib/models/stevessr_render_params.dart",
    "lib/services/stevessr_export_service.dart",
    "lib/services/stevessr_text_layout.dart",
    "lib/services/stevessr_character_assets.dart",
    "lib/services/avatar_delta_codec.dart",
    "lib/utils/screenshot_utils.dart",
    "lib/l10n/s.dart",
    "lib/l10n/app_localizations.dart",
)
DRAWING_TREES = ("lib/widgets/stevessr", "lib/l10n/slang", "lib/l10n/generated")
SHIM_TREE = SOURCE / "shims/lib"
FORBIDDEN_IMPORTED_PACKAGES = (
    "package:fluxdo/",
    "package:dio/",
    "package:flutter_riverpod/",
    "package:flutter_local_notifications/",
    "package:rhttp/",
)


def stage_drawing_sources(target: Path) -> None:
    for relative in DRAWING_SOURCES:
        source = ROOT / relative
        if not source.is_file():
            raise FileNotFoundError(
                f"Missing generated or checked-in drawing code: {source}; "
                "run dart tool/project_prep.dart test"
            )
        destination = target / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, destination)
    for relative in DRAWING_TREES:
        source = ROOT / relative
        if not source.is_dir():
            raise FileNotFoundError(
                f"Missing generated drawing/localization tree: {source}; "
                "run dart tool/project_prep.dart test"
            )
        shutil.copytree(source, target / relative, dirs_exist_ok=True)
    for source in SHIM_TREE.rglob("*.dart"):
        destination = target / "lib" / source.relative_to(SHIM_TREE)
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, destination)

    # The temporary companion app must own every imported source.
    # Reject accidental references to the full app or unknown external code.
    import re
    external_packages = set()
    for source in (target / "lib").rglob("*.dart"):
        contents = source.read_text(encoding="utf-8")
        for forbidden in FORBIDDEN_IMPORTED_PACKAGES:
            if forbidden in contents:
                raise RuntimeError(
                    f"Heavy host dependency leaked into companion: "
                    f"{source.relative_to(target)}: {forbidden}"
                )
        for match in re.finditer(
            r"""(?m)^[ ]*(?:import|export|part)[ ]+['"]([^'"]+[.]dart)['"]""",
            contents,
        ):
            uri = match.group(1)
            if uri.startswith("dart:"):
                continue
            if uri.startswith("package:"):
                package = uri[len("package:"):].split("/", 1)[0]
                external_packages.add(package)
                continue
            if not (source.parent / uri).is_file():
                raise RuntimeError(
                    f"Missing local drawing dependency: "
                    f"{source.relative_to(target)} imports {uri}"
                )
    allowed = {
        "flutter", "flutter_localizations", "intl",
        "slang", "slang_flutter", "file_picker", "flutter_avif",
        "image", "cross_file", "path_provider", "share_plus", "gal",
    }
    if external_packages - allowed:
        raise RuntimeError(
            f"Unexpected external drawing dependencies: "
            f"{sorted(external_packages - allowed)}"
        )
    print("Sticker source isolation: OK; no FluxDO root dependency")



def execute(*args: str, cwd: Path) -> None:
    print("+", " ".join(args), flush=True)
    subprocess.run(args, cwd=cwd, check=True)


def setup_project(target: Path, mode: str) -> None:
    execute(
        "flutter", "create", "--platforms=android", "--org=com.github.lingyan000.fluxdo.plugin",
        "--project-name=sticker", "--no-pub", str(target),
        cwd=ROOT,
    )
    yaml = (SOURCE / "pubspec.yaml").read_text()
    if "fluxdo:" in yaml or "path: ../.." in yaml:
        raise RuntimeError("Sticker APK must not depend on the FluxDO app")
    (target / "pubspec.yaml").write_text(yaml)
    (target / "lib/main.dart").write_text((SOURCE / "lib/main.dart").read_text())
    stage_drawing_sources(target)

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
    # This is a host-launched capability APK, NOT an independently launchable
    # application. Do not advertise a launcher icon that cannot be opened
    # without the host's signature-level permission.
    for intent_filter in list(activity.findall("intent-filter")):
        activity.remove(intent_filter)
    # Host-only launch, including ACTION_GET_CONTENT image handoff.
    # Third-party apps must not be able to impersonate an export request.
    activity.set(
        ANDROID_NS + "permission",
        "com.github.lingyan000.fluxdo.permission.BIND_PLUGIN",
    )
    ET.SubElement(manifest.getroot(), "uses-permission", {
        ANDROID_NS + "name":
            "com.github.lingyan000.fluxdo.permission.BIND_PLUGIN",
    })
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
    # flutter create derives "<org>.sticker" as the exact expected package.
    # Explicitly verify rather than allowing a non-upgradable package ID.
    if f'applicationId = "{PACKAGE}"' not in gradle:
        raise RuntimeError(
            f"Unexpected Sticker applicationId; expected {PACKAGE}"
        )
    if f'namespace = "{PACKAGE}"' not in gradle:
        raise RuntimeError(
            f"Unexpected Sticker Android namespace; expected {PACKAGE}"
        )
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
    original_props = ROOT / "android/key.properties"
    if mode == "release" and not original_props.is_file():
        raise RuntimeError("Release requires the same android/key.properties as FluxDO")
    # Core :app signs *all* build variants with the release key when present.
    # Apply the identical rule here so debug Core and debug Sticker match.
    if original_props.is_file():
        anchor = 'signingConfig = signingConfigs.getByName("debug")'
        if anchor not in gradle:
            raise RuntimeError("Generated Flutter release signing layout changed")
        signing_block = '''
    signingConfigs {
        create("fluxdoSharedRelease") {
            val props = java.util.Properties().apply {
                java.io.File("PLACEHOLDER_PROPS").inputStream().use { load(it) }
            }
            val keyLocation = java.io.File(props.getProperty("storeFile"))
            // Match :app's existing signing resolution order: relative paths
            // are based on android/app, then the Android project root.
            storeFile = if (keyLocation.isAbsolute) keyLocation else
                sequenceOf(
                    java.io.File("PLACEHOLDER_ANDROID/app", props.getProperty("storeFile")),
                    java.io.File("PLACEHOLDER_ANDROID", props.getProperty("storeFile")),
                ).firstOrNull { it.isFile }
            require(storeFile?.isFile == true) { "Release keystore not found" }
            storePassword = props.getProperty("storePassword")
            keyAlias = props.getProperty("keyAlias")
            keyPassword = props.getProperty("keyPassword")
            enableV1Signing = true
            enableV2Signing = true
            enableV3Signing = true
        }
    }

'''
        signing_block = signing_block.replace(
            "PLACEHOLDER_PROPS", original_props.as_posix()
        ).replace("PLACEHOLDER_ANDROID", (ROOT / "android").as_posix())
        if "    buildTypes {" not in gradle:
            raise RuntimeError("Expected Flutter Android buildTypes block")
        gradle = gradle.replace("    buildTypes {", signing_block + "    buildTypes {", 1)
        gradle = gradle.replace(
            anchor, 'signingConfig = signingConfigs.getByName("fluxdoSharedRelease")', 1
        )
        # Flutter's template declares release only; add an explicit debug
        # signer in the generated app. Same-signer check must pass locally.
        gradle = gradle.replace(
            "    buildTypes {",
            '    buildTypes {\n        getByName("debug") {\n'
            '            signingConfig = signingConfigs.getByName("fluxdoSharedRelease")\n'
            '        }',
            1,
        )
    build_file.write_text(gradle)

    # The original FluxDO Android Gradle setup patches a duplicate Java/Kotlin
    # FlutterAvifPlugin class. A standalone Sticker app cannot inherit the
    # host Gradle fix, so reproduce only this narrowly scoped workaround.
    root_gradle = target / "android/build.gradle.kts"
    build_script = root_gradle.read_text()
    if "patchStandaloneStickerAvifRedeclaration" not in build_script:
        build_script += """
// flutter_avif_android 3.1.0 still contains both Java and Kotlin plugin
// classes under the same name; use the same fix as FluxDO Core.
subprojects {
    if (name == "flutter_avif_android") {
        afterEvaluate {
            val patchTask = tasks.register("patchStandaloneStickerAvifRedeclaration") {
                doFirst {
                    val duplicate = file(
                        "src/main/java/com/teknorota/flutter_avif/FlutterAvifPlugin.java"
                    )
                    if (duplicate.isFile) duplicate.delete()
                }
            }
            tasks.matching {
                it.name.startsWith("compile")
            }.configureEach {
                dependsOn(patchTask)
            }
        }
    }
}
"""
    root_gradle.write_text(build_script)


def verify_drawing_dependency_graph(target: Path) -> None:
    """Reject accidental Flutter native-plugin dependencies from the host."""
    lockfile = target / "pubspec.lock"
    if not lockfile.is_file():
        raise RuntimeError("Sticker Flutter pub get did not produce a lockfile")
    lock = lockfile.read_text()
    if "  fluxdo:" in lock.splitlines():
        raise RuntimeError("The sticker APK resolved the full FluxDO dependency")
    registration = target / ".flutter-plugins-dependencies"
    if registration.is_file():
        data = json.loads(registration.read_text())
        plugins = [item["name"] for item in data.get("plugins", {}).get("android", [])]
        allowed_prefixes = (
            "file_picker", "flutter_avif", "gal", "path_provider",
            "share_plus",
        )
        unexpected = [
            name for name in plugins
            if not name.startswith(allowed_prefixes)
        ]
        if unexpected:
            raise RuntimeError(
                "Unexpected native plugins in Sticker-only APK: "
                + ", ".join(unexpected)
            )
        print(f"Sticker Android native plugin registry: {plugins}")


def verify_sticker_apk(apk: Path) -> None:
    with ZipFile(apk) as bundle:
        entries = bundle.namelist()
    if not any("flutter_assets/assets/images/avater/" in name for name in entries):
        raise RuntimeError("Sticker APK lost its companion-only character assets")
    blocked_assets = (
        "flutter_assets/assets/certs/",
        "flutter_assets/assets/cook/",
        "flutter_assets/assets/polyfill/",
        "flutter_assets/assets/ai_brands/",
    )
    for asset in blocked_assets:
        if any(asset in name for name in entries):
            raise RuntimeError(f"FluxDO host asset leaked into Sticker: {asset}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=["debug", "release"], default="debug")
    parser.add_argument("--abi", choices=["android-arm", "android-arm64", "android-x64", "universal"],
                        default="android-arm64")
    parser.add_argument("--version-code", type=int)
    parser.add_argument("--version-name")
    args = parser.parse_args()
    if args.version_code is not None and not (1 <= args.version_code < 2100000000):
        parser.error("--version-code must be a positive Android-compatible int")
    with tempfile.TemporaryDirectory(prefix="fluxdo-sticker-companion-") as temp:
        target = Path(temp) / "sticker"
        setup_project(target, args.mode)
        execute("flutter", "pub", "get", cwd=target)
        verify_drawing_dependency_graph(target)
        flutter_abis = (
            "android-arm,android-arm64,android-x64"
            if args.abi == "universal" else args.abi
        )
        command = ["flutter", "build", "apk", "--" + args.mode,
                   "--target-platform", flutter_abis, "--no-pub"]
        if args.version_code is not None:
            command += ["--build-number", str(args.version_code)]
        if args.version_name:
            command += ["--build-name", args.version_name]
        execute(*command, cwd=target)
        apk_dir = target / "build/app/outputs/flutter-apk"
        candidates = list(apk_dir.glob("*.apk"))
        assert len(candidates) == 1, f"Expected single APK: {candidates}"
        verify_sticker_apk(candidates[0])
        dest = ROOT / "build/plugin_sticker"
        dest.mkdir(parents=True, exist_ok=True)
        out = dest / f"fluxdo-sticker-{args.abi}-{args.mode}.apk"
        shutil.copy2(candidates[0], out)
        print(f"Independent companion APK: {out} ({out.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
