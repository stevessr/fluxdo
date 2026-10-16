#!/usr/bin/env python3
"""Build Android Core WITHOUT plugin Dart implementations or avatar assets.

Other platforms compile the untouched root workspace normally. This tool uses
a disposable source copy so there are no in-place pubspec/source mutations and
a failed build cannot corrupt the developer's working tree.

Android plugin APKs use their own application IDs and update independently.
"""
from __future__ import annotations

import argparse
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[2]
OVERLAY = ROOT / "android_modular/core_overlay"
AVATAR_ROOT = "assets/images/avater/"
EXCLUDED_AVATAR_ASSETS = (
    "stevessr", "llm", "touhou", "blue_archive", "witch_judgment",
)
# Fail-closed: these implementations cannot appear in staged Android Core.
# If another module still imports them, the build will fail rather than silently
# produce the old monolith.
EXCLUDED_DART = (
    "lib/models/stevessr_render_params.dart",
    "lib/services/stevessr_character_assets.dart",
    "lib/services/stevessr_text_layout.dart",
    "lib/services/avatar_delta_codec.dart",
    "lib/models/ldc_user_info.dart",
    "lib/models/cdk_user_info.dart",
    "lib/providers/ldc_providers.dart",
    "lib/providers/cdk_providers.dart",
    "lib/services/ldc_oauth_service.dart",
    "lib/services/cdk_oauth_service.dart",
    "lib/widgets/ldc_balance_card.dart",
    "lib/widgets/cdk_balance_card.dart",
)
EXCLUDED_TREES = (
    "lib/widgets/stevessr",
    "lib/modules/ldc_reward/models",
    "lib/modules/ldc_reward/providers",
    "lib/modules/ldc_reward/services",
)
EXCLUDED_REWARD_WIDGETS = (
    # Android Core gets tiny API-compatible overlays instead.
    "lib/modules/ldc_reward/widgets/ldc_reward_sheet.dart",
    "lib/modules/ldc_reward/widgets/ldc_reward_config_tile.dart",
)
SOURCE_IGNORES = (
    ".git", ".dart_tool", ".gradle", ".idea", ".vscode", "build",
    "dist", "target", ".pub-cache", ".pytest_cache", "__pycache__",
)


def _core_copy_ignores(directory: str, names: list[str]) -> set[str]:
    """Prune all avatar bytes before staging, not just at Flutter pubspec."""
    ignored = set(shutil.ignore_patterns(*SOURCE_IGNORES)(directory, names))
    if Path(directory).resolve() == (ROOT / "assets/images").resolve():
        ignored.add("avater")
    return ignored


def run(args: list[str], cwd: Path) -> None:
    print("+", " ".join(args), flush=True)
    subprocess.run(args, cwd=cwd, check=True)


def strip_host_reward_credentials(source: str) -> str:
    """Remove only the old account-secret gate from the Android reward action.

    The core uses the API-compatible reward overlay, which launches the
    separately signed plugin with PUBLIC recipient identity. Credential reads
    belong neither in Core nor in its plugin Intent payload. We match logical
    lines rather than brittle exact indentation, and reject ambiguous edits.
    """
    lines = source.splitlines(keepends=True)
    credential_lines = [
        index for index, line in enumerate(lines)
        if "ldcRewardCredentialsProvider.future," in line
    ]
    call_lines = [
        index for index, line in enumerate(lines)
        if line.strip().startswith("showLdcRewardSheet(")
    ]
    if len(credential_lines) != 1 or len(call_lines) != 1:
        raise RuntimeError("LDC reward callsite changed; refusing unsafe Core build")
    credential_index, call_index = credential_lines[0], call_lines[0]
    if call_index <= credential_index or call_index - credential_index > 40:
        raise RuntimeError("LDC reward callsite is ambiguous")
    final_check = call_index - 1
    if lines[final_check].strip() != "if (!mounted) return;":
        raise RuntimeError("LDC reward post-authorization guard changed")
    indent = len(lines[final_check]) - len(lines[final_check].lstrip())
    try_candidates = [
        index for index in range(max(0, credential_index - 6), credential_index)
        if lines[index].strip() == "try {"
        and len(lines[index]) - len(lines[index].lstrip()) == indent
    ]
    if len(try_candidates) != 1:
        raise RuntimeError("LDC reward credential try block changed")
    start = try_candidates[0]
    removed = "".join(lines[start:final_check])
    for token in (
        "final credentials = await ref.read(",
        "ldcRewardCredentialsProvider.future,",
        "if (credentials == null)",
        "} catch (error) {",
        "toast_rewardNotConfigured",
    ):
        if token not in removed:
            raise RuntimeError(f"LDC reward credential gate changed: {token}")
    rewritten = "".join(lines[:start] + lines[final_check:])
    if "ldcRewardCredentialsProvider" in rewritten:
        # The import in Core must also be replaced by the overlay. A lingering
        # symbol usage here would compile the removed credential service.
        raise RuntimeError("LDC reward credential use remained in action")
    return rewritten


def prepare(destination: Path) -> None:
    if destination.exists():
        raise RuntimeError(f"Refusing to overwrite existing directory: {destination}")
    shutil.copytree(
        ROOT, destination,
        ignore=_core_copy_ignores,
        symlinks=False,
    )
    # Copy overlays only after cloning the original source, so other targets
    # (iOS, Windows, macOS, Linux, web) remain completely unchanged.
    for src in OVERLAY.rglob("*.dart"):
        relative = src.relative_to(OVERLAY)
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(src, target)

    # Post action menu used to read host LDC Basic Auth credentials before
    # opening the reward sheet. Android now delegates to the separate LDC APK.
    # Remove the credential lookup at build time; desktop keeps original code.
    menu = destination / (
        "lib/widgets/post/post_item/widgets/"
        "post_footer_section/actions/menu_actions.dart"
    )
    original_menu = menu.read_text()
    menu.write_text(strip_host_reward_credentials(original_menu))

    for rel in EXCLUDED_DART:
        (destination / rel).unlink(missing_ok=True)
    for rel in EXCLUDED_TREES:
        shutil.rmtree(destination / rel, ignore_errors=True)

    pubspec = destination / "pubspec.yaml"
    before = pubspec.read_text()
    lines = before.splitlines(keepends=True)
    removed: set[str] = set()
    filtered = []
    for line in lines:
        match = re.fullmatch(
            r"\s*-\s*assets/images/avater/([^/]+)/\s*\r?\n?",
            line,
        )
        if match and match.group(1) in EXCLUDED_AVATAR_ASSETS:
            removed.add(match.group(1))
            continue
        filtered.append(line)
    if removed != set(EXCLUDED_AVATAR_ASSETS):
        raise RuntimeError(
            "pubspec avatar asset list drift: "
            f"removed={sorted(removed)}, expected={EXCLUDED_AVATAR_ASSETS}"
        )
    pubspec.write_text("".join(filtered))

    verify_sources(destination)
    print("Android Core staging prepared. All other platform sources untouched.")


def verify_sources(stage: Path) -> None:
    manifest = (stage / "pubspec.yaml").read_text()
    # Character sprites belong only to the separately compiled Sticker APK.
    assert not (stage / "assets/images/avater").exists(), (
        "Sticker assets leaked into Android Core staging directory"
    )
    for group in EXCLUDED_AVATAR_ASSETS:
        assert f"{AVATAR_ROOT}{group}/" not in manifest, (
            f"Avatar assets still declared in Android Core: {group}"
        )
    for rel in EXCLUDED_DART:
        assert not (stage / rel).exists(), f"Feature implementation remained: {rel}"
    for rel in EXCLUDED_TREES:
        assert not (stage / rel).exists(), f"Feature subtree remained: {rel}"
    for rel in EXCLUDED_REWARD_WIDGETS:
        assert (stage / rel).is_file(), f"Missing safe reward API stub: {rel}"
    for rel in (
        "lib/pages/metaverse_page.dart",
        "lib/pages/stevessr_generator_page.dart",
        "lib/services/stevessr_export_service.dart",
    ):
        staged = (stage / rel).read_text()
        assert "StevessrCharacterAssets" not in staged
        assert "LdcOAuthService" not in staged
        assert "CdkOAuthService" not in staged
        assert "MediaQuery" not in staged or rel.endswith("metaverse_page.dart")

    # Generated by tool/gen_l10n.dart during the later Flutter wrapper prep.
    # These files do not exist in a clean checkout; exempt only exact names.
    pending_generated = {
        (stage / "lib/l10n/slang/strings.g.dart").resolve(),
        (stage / "lib/l10n/generated/app_localizations_compat.g.dart").resolve(),
    }
    # Fail before Flutter compilation if the staged code still imports an
    # implementation which was physically removed. Check imports/exports/parts
    # including conditional and package:fluxdo imports; do not rely on
    # Platform.isAndroid tree shaking.
    missing = []
    for source in (stage / "lib").rglob("*.dart"):
        body = source.read_text(encoding="utf-8")
        # A conditional Dart directive can name several alternative sources:
        #   import 'stub.dart' if (dart.library.io) 'native.dart';
        # Checking only its first URI misses a removed plugin implementation.
        # Work on complete, semicolon-terminated directives (also multiline).
        for declaration in re.finditer(
            r"""(?ms)^[ \t]*(?:import|export|part)\b(?![ \t]+of\b)\s+([^;]+);""",
            body,
        ):
            for uri in re.findall(r"""['"]([^'"]+[.]dart)['"]""", declaration.group(1)):
                if uri.startswith("dart:") or uri.startswith("package:flutter/"):
                    continue
                if uri.startswith("package:fluxdo/"):
                    target = stage / "lib" / uri[len("package:fluxdo/"):]
                elif uri.startswith("package:") or uri.startswith("http"):
                    continue
                else:
                    target = source.parent / uri
                resolved = target.resolve()
                if not resolved.is_relative_to(stage.resolve()):
                    missing.append(f"{source.relative_to(stage)} -> {uri} (escapes stage)")
                elif not target.is_file() and resolved not in pending_generated:
                    missing.append(f"{source.relative_to(stage)} -> {uri}")
    if missing:
        raise RuntimeError(
            "Broken Dart import graph in Android Core:\\n" +
            "\\n".join(missing[:30])
        )


def check_apk(apk: Path) -> None:
    if not apk.is_file() or apk.stat().st_size == 0:
        raise RuntimeError(f"Missing Android Core APK: {apk}")
    with ZipFile(apk) as archive:
        assets = [name for name in archive.namelist() if
                  "flutter_assets/assets/images/avater/" in name]
        if assets:
            raise RuntimeError(
                "Android Core still contains standalone avatar assets: "
                + ", ".join(assets[:10])
            )
    print(f"Verified avatar assets absent in {apk.name}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=("debug", "release"), default="release")
    parser.add_argument(
        "--abi", choices=("android-arm", "android-arm64", "android-x64", "all"),
        default="android-arm64",
    )
    parser.add_argument("--split-debug-info", action="store_true")
    parser.add_argument("--prepare-only", action="store_true")
    parser.add_argument("--keep-stage", action="store_true")
    args = parser.parse_args()

    stage_parent = Path(tempfile.mkdtemp(prefix="fluxdo-modular-core-"))
    stage = stage_parent / "fluxdo"
    try:
        prepare(stage)
        if args.prepare_only:
            return
        run(["flutter", "pub", "get"], cwd=stage)
        # flutterw.dart always calls project_prep.dart app, which regenerates
        # the complete 40MB+ avatar pack INSIDE Core staging. That defeats
        # source isolation and wastes CPU/disk. Prepare ONLY Core's actual
        # dependencies: l10n, proxy cert and Rust native libraries.
        run(["dart", "tool/gen_l10n.dart"], cwd=stage)
        native_targets = (
            "android-arm,android-arm64,android-x64"
            if args.abi == "all" else args.abi
        )
        run([
            "dart", "tool/project_tasks.dart", "native:prepare", "android",
            "--" + args.mode, "--target-platform=" + native_targets,
        ], cwd=stage)
        verify_sources(stage)
        build = [
            "flutter", "build", "apk", "--" + args.mode,
            "--dart-define=cronetHttpNoPlay=true",
        ]
        if args.abi != "all":
            build += ["--target-platform", args.abi]
        if args.split_debug_info:
            build.append("--split-debug-info=build/symbols")
        run(build, cwd=stage)
        # Flutter must not regenerate the excluded avatar tree either.
        verify_sources(stage)
        apk = stage / "build/app/outputs/flutter-apk/app-release.apk"
        if args.mode == "debug":
            apk = stage / "build/app/outputs/flutter-apk/app-debug.apk"
        check_apk(apk)
        result_dir = ROOT / "build/app/outputs/flutter-apk"
        result_dir.mkdir(parents=True, exist_ok=True)
        shutil.copy2(apk, result_dir / apk.name)
        if args.split_debug_info:
            symbols = stage / "build/symbols"
            if symbols.exists():
                shutil.copytree(symbols, ROOT / "build/symbols", dirs_exist_ok=True)
        print(f"Modular Android Core copied to {result_dir / apk.name}")
    finally:
        if args.keep_stage:
            print(f"Kept staged project at {stage}")
        else:
            shutil.rmtree(stage_parent, ignore_errors=True)


if __name__ == "__main__":
    main()
