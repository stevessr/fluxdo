#!/usr/bin/env python3
"""Remove optional MiSans only from a DISPOSABLE Android Core staging copy.

Never mutate the repository. Does NOT build an APK or imply measured savings.
The runtime must use FLUXDO_EXTERNAL_MISANS=true and system fallback.
"""
import argparse
from pathlib import Path


def strip_font(pubspec: str) -> str:
    marker = "\n  fonts:\n"
    if pubspec.count(marker) != 1:
        raise ValueError("Expected exactly one top-level Flutter fonts section")
    head, tail = pubspec.split(marker)
    if tail.count("- family:") != 1 or tail.count("- family: MiSans") != 1:
        raise ValueError("Flutter font declarations changed; refusing to strip")
    if tail.count("assets/fonts/MiSansVF.ttf") != 1:
        raise ValueError("MiSans font path changed; refusing to strip")
    if any(line.strip() and not line.startswith((" ", "\t")) for line in tail.splitlines()):
        raise ValueError("Unexpected top-level pubspec content after MiSans")
    return head.rstrip() + "\n"


def prepare(stage: Path, repo: Path) -> None:
    stage, repo = stage.resolve(), repo.resolve()
    if (stage == repo or stage.is_relative_to(repo) or
            repo.is_relative_to(stage) or (stage / ".git").exists()):
        raise ValueError("Refusing to modify the source repository")
    pubspec = stage / "pubspec.yaml"
    font = stage / "assets/fonts/MiSansVF.ttf"
    theme = stage / "lib/providers/theme_provider.dart"
    loader = stage / "lib/services/assets/optional_font_loader.dart"
    if not font.is_file() or not theme.is_file() or not loader.is_file():
        raise ValueError("Missing font or dynamic system fallback implementation")
    if "FLUXDO_EXTERNAL_MISANS" not in theme.read_text():
        raise ValueError("No safe system fallback for missing MiSans")
    rewritten = strip_font(pubspec.read_text(encoding="utf-8"))
    pubspec.write_text(rewritten, encoding="utf-8")
    font.unlink()
    if font.exists() or "MiSansVF.ttf" in pubspec.read_text():
        raise AssertionError("MiSans was not excluded from Android staging")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--stage", type=Path, required=True,
                        help="already copied temp Flutter workspace, not repo")
    args = parser.parse_args()
    prepare(args.stage, Path(__file__).resolve().parents[2])
    print("Android Core font staging prepared; build with "
          "--dart-define=FLUXDO_EXTERNAL_MISANS=true")


if __name__ == "__main__":
    main()
