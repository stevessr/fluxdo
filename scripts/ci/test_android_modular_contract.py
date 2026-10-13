#!/usr/bin/env python3
"""Fast, SDK-free regression checks for Android-only Core feature removal.

These tests run before Gradle/Flutter and ensure deletion/asset exclusions are
fail-closed. Real APK builds and device tests remain separate required gates.
"""
from __future__ import annotations

import sys
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_android_core_modular as modular


class AndroidCoreIsolationTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.stage = Path(self.temp.name)
        (self.stage / "pubspec.yaml").write_text(
            "name: fluxdo\nflutter:\n  assets:\n    - assets/logo.svg\n",
            encoding="utf-8",
        )
        for name in modular.EXCLUDED_REWARD_WIDGETS:
            target = self.stage / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text("class RewardStub {}\n", encoding="utf-8")
        for name in (
            "lib/pages/metaverse_page.dart",
            "lib/pages/stevessr_generator_page.dart",
            "lib/services/stevessr_export_service.dart",
        ):
            target = self.stage / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text("class PluginEntry {}\n", encoding="utf-8")

    def test_core_builder_does_not_run_full_avatar_project_prep(self) -> None:
        import inspect
        source = inspect.getsource(modular.main)
        self.assertNotIn('"tool/flutterw.dart"', source)
        self.assertNotIn('"tool/project_prep.dart", "app"', source)
        self.assertIn('"tool/gen_l10n.dart"', source)
        self.assertIn('"native:prepare"', source)
        self.assertIn('verify_sources(stage)', source)

    def test_minimal_isolated_core_is_valid(self) -> None:
        modular.verify_sources(self.stage)

    def test_physical_avatar_bytes_are_rejected(self) -> None:
        leaked = self.stage / "assets/images/avater/stevessr"
        leaked.mkdir(parents=True)
        (leaked / "sprite.webp").write_bytes(b"fake")
        with self.assertRaisesRegex(AssertionError, "assets leaked"):
            modular.verify_sources(self.stage)

    def test_old_avatar_bundle_is_rejected(self) -> None:
        with (self.stage / "pubspec.yaml").open("a") as out:
            out.write("    - assets/images/avater/stevessr/\n")
        with self.assertRaisesRegex(AssertionError, "Avatar assets"):
            modular.verify_sources(self.stage)

    def test_direct_import_of_removed_module_is_rejected(self) -> None:
        source = self.stage / "lib/pages/more.dart"
        source.write_text(
            "import '../providers/ldc_providers.dart';\n"
            "class A {}\n",
            encoding="utf-8",
        )
        with self.assertRaisesRegex(RuntimeError, "ldc_providers.dart"):
            modular.verify_sources(self.stage)

    def test_package_import_of_removed_module_is_rejected(self) -> None:
        source = self.stage / "lib/pages/more.dart"
        source.write_text(
            "export 'package:fluxdo/models/stevessr_render_params.dart';\n",
            encoding="utf-8",
        )
        with self.assertRaisesRegex(RuntimeError, "stevessr_render_params.dart"):
            modular.verify_sources(self.stage)

    def test_generated_l10n_imports_may_be_pending(self) -> None:
        source = self.stage / "lib/l10n/app_localizations.dart"
        source.parent.mkdir(parents=True, exist_ok=True)
        source.write_text(
            "import 'slang/strings.g.dart';\n"
            "part 'generated/app_localizations_compat.g.dart';\n",
            encoding="utf-8",
        )
        modular.verify_sources(self.stage)

    def test_deleted_reward_service_cannot_survive(self) -> None:
        source = self.stage / "lib/modules/ldc_reward/services/ldc_reward_service.dart"
        source.parent.mkdir(parents=True, exist_ok=True)
        source.write_text("class LdcRewardService {}\n", encoding="utf-8")
        with self.assertRaisesRegex(AssertionError, "Feature subtree"):
            modular.verify_sources(self.stage)


if __name__ == "__main__":
    unittest.main()
