#!/usr/bin/env python3
"""SDK-free tests for isolated Sticker native plugin registration."""
from __future__ import annotations

import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from build_sticker_companion import verify_drawing_dependency_graph


class StickerNativeDependenciesTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.stage = Path(self.tmp.name)
        self.baseline = [
            "file_picker", "flutter_avif_android", "gal",
            "path_provider_android", "share_plus",
        ]
        self.transitive = [
            "flutter_plugin_android_lifecycle", "jni",
            "jni_flutter", "sqflite_android",
        ]
        self._create(self.baseline + self.transitive)

    def _create(self, plugins: list[str], lock_packages: list[str] | None = None) -> None:
        packages = lock_packages if lock_packages is not None else plugins
        packages = list(dict.fromkeys(["flutter", "image", "slang"] + packages))
        self.stage.joinpath("pubspec.lock").write_text(
            "packages:\n"
            + "".join(f"  {name}:\n    dependency: transitive\n" for name in packages)
            + "sdks:\n  dart: '^3.13.0'\n"
        )
        self.stage.joinpath(".flutter-plugins-dependencies").write_text(
            json.dumps({"plugins": {"android": [{"name": n} for n in plugins]}})
        )

    def test_standalone_gradle_configuration_uses_late_safe_tasks(self) -> None:
        import inspect
        from build_sticker_companion import setup_project
        source = inspect.getsource(setup_project)
        self.assertIn("if (state.executed)", source)
        self.assertIn("afterEvaluate { alignCompilerTargets() }", source)
        self.assertIn('getMethod("getCompileOptions")', source)
        self.assertIn('getMethod("setTargetCompatibility", Any::class.java)', source)
        self.assertIn('getMethod("setSourceCompatibility", Any::class.java)', source)
        self.assertIn('getMethod("getTargetCompatibility")', source)
        self.assertIn("tasks.withType<JavaCompile>().configureEach", source)
        self.assertNotIn("kotlin.jvm.target.validation.mode=ignore", source)
        self.assertIn('tasks.register("patchStandaloneStickerAvifRedeclaration")', source)
        self.assertIn("dependsOn(patchTask)", source)

    def test_allows_known_transitive_plugins(self) -> None:
        count, found = verify_drawing_dependency_graph(self.stage)
        self.assertGreaterEqual(count, 8)
        self.assertEqual(set(found), set(self.baseline + self.transitive))

    def test_unknown_plugin_rejected_even_if_locked(self) -> None:
        self._create(self.baseline + self.transitive + ["untrusted_android_plugin"])
        with self.assertRaisesRegex(RuntimeError, "Unexpected native plugins"):
            verify_drawing_dependency_graph(self.stage)

    def test_unlocked_plugin_rejected(self) -> None:
        self._create(self.baseline + self.transitive, self.baseline)
        with self.assertRaisesRegex(RuntimeError, "missing lockfile"):
            verify_drawing_dependency_graph(self.stage)

    def test_core_dependency_rejected(self) -> None:
        self._create(self.baseline + self.transitive + ["flutter_inappwebview_android"])
        with self.assertRaisesRegex(RuntimeError, "Unexpected native plugins"):
            verify_drawing_dependency_graph(self.stage)

    def test_required_plugin_cannot_disappear(self) -> None:
        self._create([p for p in self.baseline + self.transitive if p != "gal"])
        with self.assertRaisesRegex(RuntimeError, "native plugins missing"):
            verify_drawing_dependency_graph(self.stage)


if __name__ == "__main__":
    unittest.main()
