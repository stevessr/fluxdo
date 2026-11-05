"""Fail-closed checks for optional MiSans staged Android Core resources."""
import pathlib
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
import prepare_android_static_resources as modular


class AndroidStaticResourceStageTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.stage = pathlib.Path(self.tmp.name) / "stage"
        self.stage.mkdir()
        font = self.stage / "assets/fonts/MiSansVF.ttf"
        font.parent.mkdir(parents=True)
        font.write_bytes(b"dummy font")
        theme = self.stage / "lib/providers/theme_provider.dart"
        theme.parent.mkdir(parents=True)
        theme.write_text("const bool.fromEnvironment('FLUXDO_EXTERNAL_MISANS')")
        loader = self.stage / "lib/services/assets/optional_font_loader.dart"
        loader.parent.mkdir(parents=True)
        loader.write_text("loader")
        (self.stage / "pubspec.yaml").write_text(
            "name: example\nflutter:\n  uses-material-design: true\n"
            "  fonts:\n    - family: MiSans\n      fonts:\n"
            "        - asset: assets/fonts/MiSansVF.ttf\n"
        )

    def test_strips_font_and_preserves_other_manifest(self):
        modular.prepare(self.stage, self.stage.parent / "source")
        result = (self.stage / "pubspec.yaml").read_text()
        self.assertIn("uses-material-design: true", result)
        self.assertNotIn("  fonts:", result)
        self.assertFalse((self.stage / "assets/fonts/MiSansVF.ttf").exists())

    def test_refuses_any_folder_nested_in_source_repository(self):
        with self.assertRaisesRegex(ValueError, "source repository"):
            modular.prepare(self.stage, self.stage.parent)

    def test_real_manifest_and_font_fallback_can_be_staged(self):
        source = pathlib.Path(__file__).resolve().parents[3]
        for relative in (
            'pubspec.yaml',
            'assets/fonts/MiSansVF.ttf',
            'lib/providers/theme_provider.dart',
            'lib/services/assets/optional_font_loader.dart',
        ):
            dest = self.stage / relative
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source / relative, dest)
        modular.prepare(self.stage, source)
        self.assertFalse((self.stage / 'assets/fonts/MiSansVF.ttf').exists())
        manifest = (self.stage / 'pubspec.yaml').read_text(encoding='utf-8')
        self.assertNotIn('MiSansVF.ttf', manifest)
        self.assertNotIn('family: MiSans', manifest)
        self.assertIn('name: fluxdo', manifest)

    def test_refuses_source_root_and_unknown_font(self):
        with self.assertRaisesRegex(ValueError, "source repository"):
            modular.prepare(self.stage, self.stage)
        with self.assertRaisesRegex(ValueError, "font declarations changed"):
            modular.strip_font("flutter:\n  fonts:\n    - family: Other\n")


if __name__ == "__main__":
    unittest.main()
