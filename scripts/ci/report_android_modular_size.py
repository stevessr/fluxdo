#!/usr/bin/env python3
"""Reproducible APK size accounting for modular Android release builds."""
from __future__ import annotations

import argparse
from pathlib import Path
from zipfile import ZipFile


def mib(value: int) -> str:
    return f"{value / (1024 * 1024):.2f} MiB"


def inspect_apk(path: Path) -> tuple[int, int]:
    if not path.is_file():
        raise FileNotFoundError(path)
    with ZipFile(path) as apk:
        avatar_bytes = sum(
            record.compress_size for record in apk.infolist()
            if "flutter_assets/assets/images/avater/" in record.filename
        )
    return path.stat().st_size, avatar_bytes


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--core", type=Path, required=True)
    parser.add_argument("--plugin", type=Path, action="append", default=[])
    parser.add_argument("--baseline", type=Path)
    args = parser.parse_args()

    core_bytes, avatars = inspect_apk(args.core)
    if avatars:
        raise RuntimeError(f"Android Core still contains {mib(avatars)} of avatar assets")
    lines = [
        "# FluxDO modular APK size report",
        "",
        "| APK | Compressed bytes |",
        "|---|---:|",
        f"| Core ({args.core.name}) | {mib(core_bytes)} |",
    ]
    total = core_bytes
    for plugin in args.plugin:
        size, _ = inspect_apk(plugin)
        total += size
        lines.append(f"| {plugin.name} | {mib(size)} |")
    lines += [
        f"| All optional APKs + Core | {mib(total)} |",
        "",
        "The **Core** is installed by default. Plugins are optional, so total",
        "download size is not the default installation cost. Compression includes",
        "Flutter engine and native ABIs of the individual packages.",
    ]
    if args.baseline:
        baseline_bytes, baseline_avatar = inspect_apk(args.baseline)
        lines += [
            "",
            f"Monolithic baseline: {mib(baseline_bytes)}; "
            f"Core reduction: {mib(baseline_bytes - core_bytes)} "
            f"({(baseline_bytes-core_bytes)*100 / baseline_bytes:.1f}%).",
            f"Baseline avatar assets: {mib(baseline_avatar)}.",
        ]
    text = "\n".join(lines) + "\n"
    report = Path("build/android_modular_sizes.md")
    report.parent.mkdir(parents=True, exist_ok=True)
    report.write_text(text)
    print(text)


if __name__ == "__main__":
    main()
