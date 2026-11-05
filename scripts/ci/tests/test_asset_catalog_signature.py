"""Valid and tampered OpenSSL Ed25519 signatures over packaged catalogs."""
import pathlib
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
import asset_packs
import sign_asset_catalog


class SignedCatalogTest(unittest.TestCase):
    def test_sign_verify_and_reject_tampering(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            for pack_id, (path, optional) in asset_packs.PACKS.items():
                if optional:
                    continue
                file = root / path
                if not file.suffix:
                    file /= "example.webp"
                file.parent.mkdir(parents=True, exist_ok=True)
                file.write_bytes(pack_id.encode())
            out = root / "out"
            asset_packs.build(root, out)
            private, public = root / "private.pem", root / "public.pem"
            subprocess.run(["openssl", "genpkey", "-algorithm", "Ed25519",
                            "-out", str(private)], check=True)
            subprocess.run(["openssl", "pkey", "-in", str(private), "-pubout",
                            "-out", str(public)], check=True)
            catalog, signature = out / "catalog.json", out / "catalog.sig"
            sign_asset_catalog.sign(catalog, private, signature)
            self.assertEqual(len(signature.read_bytes()), 64)
            sign_asset_catalog.check(catalog, public, signature)
            signature.write_bytes(b"\x00" * 64)
            with self.assertRaises(subprocess.CalledProcessError):
                sign_asset_catalog.check(catalog, public, signature)


if __name__ == "__main__":
    unittest.main()
