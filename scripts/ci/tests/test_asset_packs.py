"""静态资源包构建和完整性验证，无 Flutter 依赖。"""
import pathlib
import sys
import tempfile
import unittest
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
import asset_packs


class AssetPacksTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = pathlib.Path(self.tmp.name)
        for pack_id, (path, optional) in asset_packs.PACKS.items():
            if optional:
                continue
            file = self.root / path
            if not file.suffix:
                file = file / "example.webp"
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_bytes((pack_id + path).encode())

    def test_deterministic_and_verifiable(self):
        out1 = self.root / "out1"
        out2 = self.root / "out2"
        a = asset_packs.build(self.root, out1)
        b = asset_packs.build(self.root, out2)
        self.assertEqual(a, b)
        self.assertEqual(asset_packs.verify(out1 / "catalog.json"), a)
        for pack in a["packs"]:
            self.assertEqual((out1 / pack["filename"]).read_bytes(), (out2 / pack["filename"]).read_bytes())
        self.assertEqual(set(a["skippedGenerated"]), {"avatar-llm", "avatar-stevessr"})

    def test_selected_pack_build(self):
        output = self.root / "selected"
        catalog = asset_packs.build(self.root, output, {"render-cook"})
        self.assertEqual([pack["id"] for pack in catalog["packs"]], ["render-cook"])
        self.assertEqual(catalog["skippedGenerated"], [])
        self.assertEqual(asset_packs.verify(output / "catalog.json"), catalog)
        with self.assertRaisesRegex(ValueError, "未知资源包"):
            asset_packs.build(self.root, output, {"unknown"})

    def test_tampered_zip_fails(self):
        out = self.root / "out"
        catalog = asset_packs.build(self.root, out)
        file = out / catalog["packs"][0]["filename"]
        file.write_bytes(file.read_bytes() + b"tamper")
        with self.assertRaisesRegex(ValueError, "校验和"):
            asset_packs.verify(out / "catalog.json")

    def test_generated_pack(self):
        file = self.root / "assets/images/avater/llm/manifest.json"
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text('{"version":1}')
        catalog = asset_packs.build(self.root, self.root / "out")
        self.assertIn("avatar-llm", {p["id"] for p in catalog["packs"]})

    def test_missing_mandatory_asset(self):
        (self.root / "assets/fonts/MiSansVF.ttf").unlink()
        with self.assertRaisesRegex(ValueError, "缺少必需资源"):
            asset_packs.build(self.root, self.root / "out")

    def test_symlink_rejected(self):
        file = self.root / "assets/ai_brands/link.svg"
        try:
            file.symlink_to(self.root / "assets/fonts/MiSansVF.ttf")
        except (NotImplementedError, OSError):
            self.skipTest("文件系统不支持符号链接")
        with self.assertRaisesRegex(ValueError, "不安全资源"):
            asset_packs.build(self.root, self.root / "out")

    def test_traversal_rejected(self):
        for name in ("../escape", "a/../escape", "/root", "a\\b", "a//b"):
            self.assertFalse(asset_packs.safe_path(name))


if __name__ == "__main__":
    unittest.main()
