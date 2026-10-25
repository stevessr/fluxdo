#!/usr/bin/env python3
"""Build selected native companion APKs without evaluating the Flutter host."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
from zipfile import ZipFile

from android_plugin_catalog import ROOT, SHARED_LIBRARIES, PluginCatalog, PluginSpec, load_catalog
from generate_android_plugin_catalog import synchronize


def select_plugins(catalog: PluginCatalog, ids: list[str]) -> tuple[PluginSpec, ...]:
    if not ids:
        return catalog.native
    if len(set(ids)) != len(ids):
        raise ValueError("Duplicate --plugin selection")
    selected = tuple(catalog.plugin(plugin_id) for plugin_id in ids)
    if any(spec.kind != "native" for spec in selected):
        raise ValueError("Flutter Sticker must use build_sticker_companion.py")
    return selected


def verify_source_graph(root: Path, catalog: PluginCatalog) -> None:
    """Allow only shared API/session libraries, never an app-to-app link."""
    expected = {spec.module: set(spec.libraries) for spec in catalog.native}
    expected.update({library: set() for library in SHARED_LIBRARIES})
    for module, libraries in expected.items():
        source = (root / f"android/{module}/build.gradle.kts").read_text(encoding="utf-8")
        declarations = re.findall(r'\bproject\s*\(([^)]*)\)', source)
        actual = set()
        for declaration in declarations:
            match = re.fullmatch(r'\s*":([a-zA-Z0-9_]+)"\s*', declaration)
            if match is None:
                raise RuntimeError(f"{module}: dynamic Gradle project dependency is unsupported")
            actual.add(match.group(1))
        if actual != libraries:
            raise RuntimeError(f"{module}: Gradle dependencies {actual} != catalog {libraries}")
        if any(token in source for token in ("dev.flutter", "evaluationDependsOn", 'project(":app")')):
            raise RuntimeError(f"{module}: Flutter host dependency in native graph")


def build_command(gradle: str, root: Path, plugins: tuple[PluginSpec, ...],
                  mode: str, version_code: int | None = None,
                  version_name: str | None = None) -> list[str]:
    if mode not in ("debug", "release") or not plugins:
        raise ValueError("Expected a build variant and at least one native module")
    if version_code is not None and not 1 <= version_code < 2100000000:
        raise ValueError("--version-code must be a positive Android-compatible int")
    if version_name is not None and not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9.+_-]{0,79}", version_name):
        raise ValueError("Invalid --version-name")
    command = [gradle, "--no-daemon", "--console=plain", "-p", str(root / "android/native_plugins")]
    for spec in plugins:
        command += [
            f"-PpluginVersionCode.{spec.id}={version_code if version_code is not None else spec.version_code}",
            f"-PpluginVersionName.{spec.id}={version_name if version_name is not None else spec.version_name}",
        ]
    command += [f":{spec.module}:assemble{mode.capitalize()}" for spec in plugins]
    return command


def inspect_native_apk(path: Path) -> dict:
    if not path.is_file() or path.stat().st_size == 0:
        raise RuntimeError(f"Native build did not produce {path}")
    with ZipFile(path) as apk:
        entries = apk.namelist()
    if "AndroidManifest.xml" not in entries or "classes.dex" not in entries:
        raise RuntimeError(f"Not a native Android application APK: {path}")
    forbidden = ("flutter_assets/", "libflutter.so", "libapp.so", "libdoh_proxy.so")
    if any(token in name for name in entries for token in forbidden):
        raise RuntimeError(f"Flutter/host payload leaked into native APK: {path}")
    with path.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    return {"bytes": path.stat().st_size, "sha256": digest}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=("debug", "release"), default="debug")
    parser.add_argument("--plugin", action="append", default=[], help="Native ID; repeat to select a subset")
    parser.add_argument("--version-code", type=int)
    parser.add_argument("--version-name")
    parser.add_argument("--plan", action="store_true", help="Print build plan without Java, Android SDK or Flutter")
    args = parser.parse_args()
    catalog = load_catalog()
    synchronize(check=True)
    verify_source_graph(ROOT, catalog)
    selected = select_plugins(catalog, args.plugin)
    wrapper = ROOT / "android/gradlew"
    gradle = shutil.which("gradle") or (str(wrapper) if wrapper.is_file() else "gradle")
    command = build_command(gradle, ROOT, selected, args.mode, args.version_code, args.version_name)
    if args.plan:
        print(json.dumps({"command": command, "modules": [s.module for s in selected]}, indent=2))
        return
    if args.mode == "release" and not (ROOT / "android/key.properties").is_file():
        raise RuntimeError("Native Release requires FluxDO android/key.properties; debug fallback is forbidden")
    if not (os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT") or
            (ROOT / "android/native_plugins/local.properties").is_file()):
        raise RuntimeError("Set ANDROID_HOME or ANDROID_SDK_ROOT for the independent native project")
    # No pub get, Flutter plugin loader, host CA, Dart assets or Rust build.
    subprocess.run(command, cwd=ROOT, check=True)
    records = []
    for spec in selected:
        relative = Path(f"{spec.module}/outputs/apk/{args.mode}/{spec.module}-{args.mode}.apk")
        source = ROOT / "build/native_plugins" / relative
        record = inspect_native_apk(source)
        destination = ROOT / "build" / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
        records.append({"id": spec.id, "package": spec.package,
                        "apk": str(destination.relative_to(ROOT)), **record})
    report = ROOT / f"build/native_plugins/native-{args.mode}-artifacts.json"
    report.write_text(json.dumps({"schemaVersion": 1, "mode": args.mode, "artifacts": records},
                                 indent=2) + "\n", encoding="utf-8")
    print(f"Built {len(records)} native companions; artifact hashes: {report}")


if __name__ == "__main__":
    main()
