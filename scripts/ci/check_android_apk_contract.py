#!/usr/bin/env python3
"""Validate actual signed Android Core/companion APK identities.

Fails closed on package ID mismatches or incompatible signing identities.
Use the Android SDK build-tools aapt and apksigner installed on the runner.
This complements Dart source exclusions with verifiable APK outputs.
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

PREFIX = "com.github.lingyan000.fluxdo"
PLUGINS = {
    "deviceinfo": PREFIX + ".plugin.deviceinfo",
    "network": PREFIX + ".plugin.network",
    "cdk": PREFIX + ".plugin.cdk",
    "ldc": PREFIX + ".plugin.ldc",
    "ldc_reward": PREFIX + ".plugin.ldc_reward",
    "sticker": PREFIX + ".plugin.sticker",
}


def sdk_tool(name: str) -> str:
    found = shutil.which(name)
    if found:
        return found
    root = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT")
    if root:
        build_tools = Path(root) / "build-tools"
        if build_tools.exists():
            for version in sorted(build_tools.iterdir(), reverse=True):
                path = version / name
                if path.is_file():
                    return str(path)
    raise RuntimeError(f"Android SDK tool {name} not found")


def output(*args: str) -> str:
    result = subprocess.run(
        args, check=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, encoding="utf-8", errors="replace",
    )
    return result.stdout


def details(apk: Path, aapt: str, signer: str) -> tuple[str, int, str]:
    if not apk.is_file() or apk.stat().st_size == 0:
        raise FileNotFoundError(apk)
    badging = output(aapt, "dump", "badging", str(apk))
    first_line = badging.splitlines()[0] if badging else ""
    package_match = re.search("name='([^']+)'", first_line)
    version_match = re.search("versionCode='([0-9]+)'", first_line)
    if not package_match or not version_match:
        raise RuntimeError(f"Unreadable package/version: {apk}")
    version = int(version_match.group(1))
    if version <= 0:
        raise RuntimeError(f"Nonpositive Android versionCode: {apk}")
    signatures = output(signer, "verify", "--print-certs", str(apk))
    digest = re.findall(
        "Signer #[0-9]+ certificate SHA-256 digest: ([0-9a-fA-F:]{64,95})",
        signatures,
    )
    if len(digest) != 1:
        raise RuntimeError(f"Expected exactly one signer for {apk.name}: {signatures}")
    return package_match.group(1), version, digest[0].replace(":", "").lower()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--core", type=Path, required=True)
    parser.add_argument(
        "--plugin", action="append", nargs=2, metavar=("ID", "APK"),
        default=[], help="Plugin ID followed by compiled APK path",
    )
    args = parser.parse_args()
    aapt = sdk_tool("aapt")
    signer = sdk_tool("apksigner")
    core_pkg, core_version, core_signer = details(args.core, aapt, signer)
    if core_pkg != PREFIX:
        raise RuntimeError(f"Core applicationId changed: {core_pkg}")
    print(f"Core: {core_pkg} v{core_version} signer={core_signer[:16]}...")
    seen: set[str] = set()
    for plugin_id, path in args.plugin:
        if plugin_id not in PLUGINS:
            raise RuntimeError(f"Unknown plugin ID: {plugin_id}")
        if plugin_id in seen:
            raise RuntimeError(f"Duplicate plugin ID: {plugin_id}")
        seen.add(plugin_id)
        apk = Path(path)
        pkg, version, digest = details(apk, aapt, signer)
        if pkg != PLUGINS[plugin_id]:
            raise RuntimeError(
                f"{plugin_id} package mismatch: {pkg} != {PLUGINS[plugin_id]}"
            )
        if digest != core_signer:
            raise RuntimeError(
                f"{plugin_id} is NOT signed by the Core signing identity"
            )
        print(f"PASS: {plugin_id} ({pkg}) v{version} same-signer")
    if seen != PLUGINS.keys():
        raise RuntimeError(
            f"Expected all {sorted(PLUGINS)}, checked only {sorted(seen)}"
        )


if __name__ == "__main__":
    try:
        main()
    except (ValueError, RuntimeError, FileNotFoundError, subprocess.CalledProcessError) as err:
        print(f"Android APK compatibility: FAILED: {err}", file=sys.stderr)
        sys.exit(1)
