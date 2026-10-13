#!/usr/bin/env python3
"""Verify minimal Sticker Dart source tree can stand alone without fluxdo."""
from __future__ import annotations

from pathlib import Path
import sys
from tempfile import TemporaryDirectory

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_sticker_companion import SOURCE, stage_drawing_sources


def main() -> None:
    manifest = (SOURCE / "pubspec.yaml").read_text()
    if any(term in manifest for term in ("\n  fluxdo:", "path: ../..")):
        raise RuntimeError("Standalone APK depends on root Flutter application")
    for forbidden in (
        "flutter_riverpod:", "flutter_inappwebview:", "rhttp:",
        "flutter_local_notifications:", "dio:", "cronet_http:",
        "firebase_", "flutter_foreground_task:",
    ):
        if forbidden in manifest:
            raise RuntimeError(f"Unexpected monolith-only dependency: {forbidden}")
    with TemporaryDirectory(prefix="sticker-source-check-") as temp:
        stage = Path(temp)
        (stage / "lib").mkdir()
        (stage / "lib/main.dart").write_text((SOURCE / "lib/main.dart").read_text())
        stage_drawing_sources(stage)
        dart_sources = sorted((stage / "lib").rglob("*.dart"))
        if len(dart_sources) < 10:
            raise RuntimeError("Sticker staging unexpectedly omitted render pipeline")
        if any("package:fluxdo/" in source.read_text() for source in dart_sources):
            raise RuntimeError("Found full FluxDO package import in Sticker")
        if any("discourse" in str(source) for source in dart_sources):
            raise RuntimeError("Sticker still bundles forum services")
        files_size = sum(file.stat().st_size for file in dart_sources)
        print(
            f"Sticker isolation PASS: {len(dart_sources)} Dart files, "
            f"{files_size:,} source bytes, no FluxDO root dependency"
        )


if __name__ == "__main__":
    main()
