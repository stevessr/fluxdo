#!/usr/bin/env python3
"""Validate actual signed Android Core/companion APK identities.

Fails closed on package ID mismatches or incompatible signing identities.
Use the Android SDK build-tools aapt and apksigner installed on the runner.
This complements Dart source exclusions with verifiable APK outputs.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

from android_plugin_catalog import HOST_PACKAGE, load_catalog

PREFIX = HOST_PACKAGE
PLUGINS = {spec.id: spec.package for spec in load_catalog().plugins}


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


def signing_identity(signatures: str) -> str:
    """Read legacy numbered and newer per-scheme apksigner certificate output.

    One identity may be printed for multiple signing schemes. Repeated signer
    records, multiple numbered signers, conflicting certificates and malformed
    digests must still fail. A source-stamp certificate is not an APK signer.
    """
    identities: set[str] = set()
    labels: set[str] = set()
    for line in signatures.splitlines():
        line = line.strip()
        if "certificate SHA-256 digest:" not in line:
            continue
        if line.startswith("Source Stamp Signer"):
            continue
        match = re.fullmatch(
            r"(Signer #[1-9][0-9]*|V[123](?:\.[0-9]+)? Signer):? "
            r"certificate SHA-256 digest: ([0-9a-fA-F:]+)", line,
        )
        if not match:
            raise RuntimeError("Unrecognized APK signer record")
        label, digest = match.groups()
        if label in labels or (label.startswith("Signer #") and label != "Signer #1"):
            raise RuntimeError("Expected exactly one signer per APK signing scheme")
        labels.add(label)
        # Accept either plain hex or properly paired colon-separated octets.
        if not re.fullmatch(r"(?:[0-9a-fA-F]{64}|(?:[0-9a-fA-F]{2}:){31}[0-9a-fA-F]{2})", digest):
            raise RuntimeError("Malformed signer SHA-256 digest")
        identities.add(digest.replace(":", "").lower())
    if len(identities) != 1:
        raise RuntimeError("Expected exactly one signer identity across APK signing schemes")
    return identities.pop()


def details(apk: Path, aapt: str, signer: str, build_mode: str | None = None) -> tuple[str, int, str]:
    if not apk.is_file() or apk.stat().st_size == 0:
        raise FileNotFoundError(apk)
    badging = output(aapt, "dump", "badging", str(apk))
    debuggable = "application-debuggable" in badging.splitlines()
    if build_mode is not None and debuggable != (build_mode == "debug"):
        raise RuntimeError(f"{apk.name}: debuggable flag does not match {build_mode}")
    first_line = badging.splitlines()[0] if badging else ""
    package_match = re.search("name='([^']+)'", first_line)
    version_match = re.search("versionCode='([0-9]+)'", first_line)
    if not package_match or not version_match:
        raise RuntimeError(f"Unreadable package/version: {apk}")
    version = int(version_match.group(1))
    if version <= 0:
        raise RuntimeError(f"Nonpositive Android versionCode: {apk}")
    signatures = output(signer, "verify", "--print-certs", str(apk))
    try:
        digest = signing_identity(signatures)
    except RuntimeError as error:
        raise RuntimeError(f"{apk.name}: {error}") from error
    return package_match.group(1), version, digest


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--core", type=Path, required=True)
    parser.add_argument("--report", type=Path, help="Write verified APK identities, sizes and SHA-256")
    parser.add_argument("--build-mode", choices=("debug", "release"), required=True)
    parser.add_argument(
        "--plugin", action="append", nargs=2, metavar=("ID", "APK"),
        default=[], help="Plugin ID followed by compiled APK path",
    )
    args = parser.parse_args()
    aapt = sdk_tool("aapt")
    signer = sdk_tool("apksigner")
    core_pkg, core_version, core_signer = details(args.core, aapt, signer, args.build_mode)
    if core_pkg != PREFIX:
        raise RuntimeError(f"Core applicationId changed: {core_pkg}")
    print(f"Core: {core_pkg} v{core_version} signer={core_signer[:16]}...")
    records = [artifact_record("core", args.core, core_pkg, core_version, core_signer)]
    seen: set[str] = set()
    for plugin_id, path in args.plugin:
        if plugin_id not in PLUGINS:
            raise RuntimeError(f"Unknown plugin ID: {plugin_id}")
        if plugin_id in seen:
            raise RuntimeError(f"Duplicate plugin ID: {plugin_id}")
        seen.add(plugin_id)
        apk = Path(path)
        pkg, version, digest = details(apk, aapt, signer, args.build_mode)
        if pkg != PLUGINS[plugin_id]:
            raise RuntimeError(
                f"{plugin_id} package mismatch: {pkg} != {PLUGINS[plugin_id]}"
            )
        if digest != core_signer:
            raise RuntimeError(
                f"{plugin_id} is NOT signed by the Core signing identity"
            )
        print(f"PASS: {plugin_id} ({pkg}) v{version} same-signer")
        records.append(artifact_record(plugin_id, apk, pkg, version, digest))
    if seen != PLUGINS.keys():
        raise RuntimeError(
            f"Expected all {sorted(PLUGINS)}, checked only {sorted(seen)}"
        )
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps({
            "schemaVersion": 1,
            "buildMode": args.build_mode,
            "protocolVersion": load_catalog().protocol,
            # This is verification evidence, not an authenticated update feed.
            "artifacts": records,
        }, indent=2) + "\n", encoding="utf-8")


def artifact_record(plugin_id: str, apk: Path, package: str, version: int, signer: str) -> dict:
    with apk.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    return {"id": plugin_id, "file": apk.name, "package": package,
            "versionCode": version, "signerSha256": signer,
            "sha256": digest, "bytes": apk.stat().st_size}


if __name__ == "__main__":
    try:
        main()
    except (ValueError, RuntimeError, FileNotFoundError, subprocess.CalledProcessError) as err:
        print(f"Android APK compatibility: FAILED: {err}", file=sys.stderr)
        sys.exit(1)
