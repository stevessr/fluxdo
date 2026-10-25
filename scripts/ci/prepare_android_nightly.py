#!/usr/bin/env python3
"""Stage complete per-ABI Core/companion sets under stable nightly filenames."""
from __future__ import annotations

import argparse
from pathlib import Path
import re
import shutil

from android_plugin_catalog import load_catalog

ARCHITECTURES = ("arm64-v8a", "armeabi-v7a", "x86_64", "universal")
MODULES = {"core"} | {p.id.replace("_", "-") for p in load_catalog().plugins}


def prepare(source: Path, destination: Path) -> list[Path]:
    records: dict[tuple[str, str], Path] = {}
    for apk in sorted(source.glob("*.apk")):
        architecture = next((arch for arch in ARCHITECTURES if apk.name.endswith(f"-{arch}.apk")), None)
        if architecture is None or not apk.is_file() or apk.stat().st_size == 0:
            raise ValueError(f"Invalid APK artifact: {apk.name}")
        prefix = apk.name.removesuffix(f"-{architecture}.apk")
        if re.fullmatch(r"fluxdo-v[0-9][A-Za-z0-9.+_-]*", prefix):
            module = "core"
        elif prefix.startswith("fluxdo-plugin-"):
            module = prefix.removeprefix("fluxdo-plugin-")
            if module == "core":
                raise ValueError(f"Invalid companion identity: {apk.name}")
        else:
            raise ValueError(f"Unknown APK artifact: {apk.name}")
        identity = (architecture, module)
        if module not in MODULES or identity in records:
            raise ValueError(f"Unknown or duplicate APK identity: {apk.name}")
        records[identity] = apk
    if not records:
        raise ValueError("No APK artifacts to publish")
    for arch in {key[0] for key in records}:
        if {module for architecture, module in records if architecture == arch} != MODULES:
            raise ValueError(f"Incomplete Core/companion set for {arch}")
    if destination.exists() and any(destination.iterdir()):
        raise ValueError("Nightly staging must be empty")
    destination.mkdir(parents=True, exist_ok=True)
    staged = []
    for (arch, module), apk in sorted(records.items()):
        name = f"fluxdo-nightly-{arch}.apk" if module == "core" else f"fluxdo-plugin-{module}-{arch}.apk"
        target = destination / name
        shutil.copy2(apk, target)
        staged.append(target)
    return staged


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    for artifact in prepare(args.source, args.destination):
        print(artifact)
