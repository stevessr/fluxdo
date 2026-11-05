"""Prevent independent Python, Flutter IO, signature and settings ID drift."""
import pathlib
import re
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts/ci"))
from asset_packs import PACKS


def block(path, pattern):
    text = (ROOT / path).read_text(encoding="utf-8")
    match = re.search(pattern, text, flags=re.S)
    if match is None:
        raise AssertionError(f"Contract block not found: {path}")
    return match.group(1)


class PackContractTests(unittest.TestCase):
    def test_backend_roots_and_catalog_match(self):
        body = block("lib/services/assets/static_asset_pack_backend_io.dart",
                     r"const _roots = <String, String>\{(.*?)\};")
        actual = dict(re.findall(r"^\s*'([^']+)':\s*'([^']+)',?",
                                 body, flags=re.M))
        expected = {key: path.rstrip("/") for key, (path, _) in PACKS.items()}
        self.assertEqual({key: value.rstrip("/") for key, value in actual.items()},
                         expected)
        self.assertEqual(len(actual), len(expected))

    def test_signed_catalog_and_manager_allow_exactly_same_ids(self):
        ids = set(re.findall(
            r"'([^']+)'",
            block("lib/services/assets/signed_asset_catalog.dart",
                  r"static const _ids = <String>\{(.*?)\};")))
        labels = set(re.findall(
            r"^\s*'([^']+)':",
            block("lib/pages/static_asset_pack_manager_page.dart",
                  r"static const _labels = <String, String>\{(.*?)\};"),
            flags=re.M))
        self.assertEqual(ids, set(PACKS))
        self.assertEqual(labels, set(PACKS))


if __name__ == "__main__":
    unittest.main()
