"""Behavior checks for module planning, generated consumers and native isolation."""
from __future__ import annotations

import copy
import hashlib
import json
from pathlib import Path
import shutil
from tempfile import TemporaryDirectory
import unittest
from zipfile import ZipFile

from android_plugin_catalog import CATALOG, ROOT, load_catalog
from build_native_plugins import build_command, inspect_native_apk, select_plugins, verify_source_graph
from generate_android_plugin_catalog import generated_files, synchronize


class AndroidPluginCatalogTest(unittest.TestCase):
    def setUp(self):
        self.tmp = TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.catalog_path = self.root / "android_modular/plugins.json"
        self.catalog_path.parent.mkdir()
        self.data = json.loads(CATALOG.read_text())
        self.write(self.data)

    def write(self, data):
        self.catalog_path.write_text(json.dumps(data), encoding="utf-8")

    def test_real_catalog_checks_all_generated_consumers(self):
        catalog = load_catalog()
        self.assertEqual(len(catalog.native), 5)
        self.assertEqual(len(catalog.plugins), 6)
        synchronize(check=True)
        verify_source_graph(ROOT, catalog)

    def test_invalid_identity_dependency_and_version_are_rejected(self):
        cases = [
            ("id", "../escape"), ("package", "com.other.application"),
            ("module", "../app"), ("service", "com.other.Service"),
            ("activity", "com.other.Activity"), ("kind", "remote"),
            ("libraries", ["plugin_api", "app"]),
            ("libraries", ["plugin_api", "plugin_network"]),
            ("operations", ["device.snapshot", "device.snapshot"]),
            ("operations", ["arbitrary shell command"]),
            ("operations", []), ("versionCode", 0), ("versionCode", True),
            ("versionCode", 2100000000), ("versionName", "1.0\ninjected=value"),
            ("typoVersionCode", 2),
        ]
        for field, value in cases:
            with self.subTest(field=field, value=value):
                data = copy.deepcopy(self.data)
                data["plugins"][0][field] = value
                self.write(data)
                with self.assertRaises(ValueError):
                    load_catalog(self.catalog_path)

    def test_duplicate_plugin_and_duplicate_json_key_rejected(self):
        self.data["plugins"].append(self.data["plugins"][0])
        self.write(self.data)
        with self.assertRaisesRegex(ValueError, "Duplicate plugin ID"):
            load_catalog(self.catalog_path)
        self.catalog_path.write_text('{"schemaVersion": 1, "schemaVersion": 1}')
        with self.assertRaisesRegex(ValueError, "Duplicate catalog key"):
            load_catalog(self.catalog_path)

    def test_application_cannot_shadow_shared_library(self):
        item = self.data["plugins"][0]
        item.update(id="api", module="plugin_api",
                    package="com.github.lingyan000.fluxdo.plugin.api",
                    service="com.github.lingyan000.fluxdo.plugin.api.ApiService")
        self.write(self.data)
        with self.assertRaisesRegex(ValueError, "collides with shared library"):
            load_catalog(self.catalog_path)

    def test_generator_detects_stale_files_and_is_repeatable(self):
        synchronize(self.root)
        synchronize(self.root, check=True)
        contents = {p: (self.root / p).read_bytes() for p in generated_files(load_catalog())}
        synchronize(self.root)
        self.assertEqual(contents, {p: (self.root / p).read_bytes() for p in contents})
        path = self.root / "android/native_plugins/settings.gradle.kts"
        path.write_text(path.read_text() + '\ninclude(":app")\n')
        with self.assertRaisesRegex(RuntimeError, "Stale plugin catalog"):
            synchronize(self.root, check=True)

    def test_updating_one_module_preserves_other_versions(self):
        self.data["plugins"][1]["versionCode"] = 9
        self.data["plugins"][1]["versionName"] = "0.9.0"
        self.write(self.data)
        catalog = load_catalog(self.catalog_path)
        command = build_command("gradle", self.root, catalog.native, "release")
        self.assertIn("-PpluginVersionCode.network=9", command)
        self.assertIn("-PpluginVersionCode.deviceinfo=1", command)
        self.assertEqual(catalog.plugin("sticker").version_code, 1)

    def test_subset_selects_only_requested_tasks(self):
        selected = select_plugins(load_catalog(), ["network", "ldc"])
        command = build_command("gradle", self.root, selected, "debug", 12, "0.12.0")
        tasks = [arg for arg in command if arg.startswith(":")]
        self.assertEqual(tasks, [":plugin_network:assembleDebug", ":plugin_ldc:assembleDebug"])
        self.assertEqual(command[command.index("-p") + 1], str(self.root / "android/native_plugins"))
        self.assertIn("-PpluginVersionCode.ldc=12", command)

    def test_unknown_duplicate_or_flutter_selection_is_rejected(self):
        for ids in (["unknown"], ["sticker"], ["network", "network"]):
            with self.subTest(ids=ids), self.assertRaises(ValueError):
                select_plugins(load_catalog(), ids)

    def test_native_dependency_cannot_link_host_or_another_apk(self):
        catalog = load_catalog()
        modules = [p.module for p in catalog.native] + ["plugin_api", "plugin_web_session"]
        for module in modules:
            target = self.root / f"android/{module}/build.gradle.kts"
            target.parent.mkdir(parents=True)
            shutil.copyfile(ROOT / target.relative_to(self.root), target)
        target = self.root / "android/plugin_network/build.gradle.kts"
        baseline = target.read_text()
        for dependency in ("app", "plugin_ldc"):
            target.write_text(baseline + f'\ndependencies {{ implementation(project(":{dependency}")) }}\n')
            with self.subTest(dependency=dependency), self.assertRaisesRegex(RuntimeError, "Gradle dependencies"):
                verify_source_graph(self.root, catalog)

    def test_native_apk_audit_measures_real_bytes_and_rejects_flutter(self):
        apk = self.root / "network.apk"
        with ZipFile(apk, "w") as archive:
            archive.writestr("AndroidManifest.xml", b"binary XML fixture")
            archive.writestr("classes.dex", b"dex fixture")
        record = inspect_native_apk(apk)
        self.assertEqual(record["bytes"], apk.stat().st_size)
        self.assertEqual(record["sha256"], hashlib.sha256(apk.read_bytes()).hexdigest())
        with ZipFile(apk, "a") as archive:
            archive.writestr("lib/arm64-v8a/libflutter.so", b"unexpected")
        with self.assertRaisesRegex(RuntimeError, "Flutter/host payload"):
            inspect_native_apk(apk)


if __name__ == "__main__":
    unittest.main()
