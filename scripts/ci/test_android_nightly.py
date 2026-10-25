from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from prepare_android_nightly import MODULES, prepare


class AndroidNightlyTest(unittest.TestCase):
    def setUp(self):
        self.tmp = TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.source = Path(self.tmp.name) / "dist"
        self.target = Path(self.tmp.name) / "nightly"
        self.source.mkdir()

    def complete_set(self, arch):
        for module in MODULES:
            prefix = "fluxdo-v0.2.29-abcdef-20261025" if module == "core" else f"fluxdo-plugin-{module}"
            (self.source / f"{prefix}-{arch}.apk").write_bytes(f"{module}-{arch}".encode())

    def test_two_architectures_preserve_all_modules_without_overwriting(self):
        for arch in ("arm64-v8a", "x86_64"):
            self.complete_set(arch)
        outputs = prepare(self.source, self.target)
        self.assertEqual(len(outputs), 14)
        for arch in ("arm64-v8a", "x86_64"):
            self.assertEqual((self.target / f"fluxdo-nightly-{arch}.apk").read_bytes(), f"core-{arch}".encode())
            for module in MODULES - {"core"}:
                self.assertEqual((self.target / f"fluxdo-plugin-{module}-{arch}.apk").read_bytes(), f"{module}-{arch}".encode())

    def test_missing_companion_is_rejected_before_any_copy(self):
        self.complete_set("arm64-v8a")
        (self.source / "fluxdo-plugin-sticker-arm64-v8a.apk").unlink()
        with self.assertRaisesRegex(ValueError, "Incomplete"):
            prepare(self.source, self.target)
        self.assertFalse(self.target.exists())

    def test_unknown_duplicate_empty_and_unscoped_artifacts_are_rejected(self):
        self.complete_set("arm64-v8a")
        for name, content in (
            ("fluxdo-v1.0-other-arm64-v8a.apk", b"duplicate core"),
            ("fluxdo-plugin-unknown-arm64-v8a.apk", b"unknown"),
            ("fluxdo-plugin-network.apk", b"unscoped"),
            ("fluxdo-plugin-network-x86_64.apk", b""),
        ):
            extra = self.source / name
            extra.write_bytes(content)
            with self.subTest(name=name), self.assertRaises(ValueError):
                prepare(self.source, self.target)
            self.assertFalse(self.target.exists())
            extra.unlink()

    def test_stale_destination_cannot_leak_old_apks(self):
        self.complete_set("universal")
        self.target.mkdir()
        (self.target / "stale.apk").write_bytes(b"old")
        with self.assertRaisesRegex(ValueError, "must be empty"):
            prepare(self.source, self.target)


if __name__ == "__main__":
    unittest.main()
