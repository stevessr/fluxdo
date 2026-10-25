"""APK identity/report behavior without pretending to compile/sign Android code."""
from contextlib import redirect_stdout
import io
import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

import check_android_apk_contract as checker


class AndroidApkContractTest(unittest.TestCase):
    def setUp(self):
        self.tmp = TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.apk = self.root / "test.apk"
        self.apk.write_bytes(b"fixture, not a real signed APK")
        self.digest = "ab" * 32

    def test_release_rejects_debuggable_apk(self):
        with patch.object(checker, "output", return_value="application-debuggable\n"):
            with self.assertRaisesRegex(RuntimeError, "debuggable flag"):
                checker.details(self.apk, "aapt", "apksigner", "release")

    def test_package_version_and_signer_are_read_from_sdk_output(self):
        outputs = [
            f"package: name='{checker.PREFIX}' versionCode='42'\napplication-debuggable\n",
            f"Signer #1 certificate SHA-256 digest: {self.digest.upper()}\n",
        ]
        with patch.object(checker, "output", side_effect=outputs):
            self.assertEqual(checker.details(self.apk, "aapt", "apksigner", "debug"),
                             (checker.PREFIX, 42, self.digest))

    def test_current_ci_v2_signer_output_is_recognized(self):
        # Captured format from the b78fe26e APK gate, which compiled all APKs
        # successfully but encountered the per-scheme apksigner output.
        outputs = [
            f"package: name='{checker.PREFIX}' versionCode='42'\napplication-debuggable\n",
            "V2 Signer: certificate DN: C=US, O=Android, CN=Android Debug\n"
            "V2 Signer: certificate SHA-256 digest: "
            "0c0545cd8b234bddeaa63e69c26ad17f826bbb92cc8812d38d0bdd91714d073b\n"
            "V2 Signer: certificate SHA-1 digest: 330bc0315aeaedd2e4354f0fc6087571b4d06383\n",
        ]
        with patch.object(checker, "output", side_effect=outputs):
            self.assertEqual(checker.details(self.apk, "aapt", "apksigner", "debug"),
                             (checker.PREFIX, 42,
                              "0c0545cd8b234bddeaa63e69c26ad17f826bbb92cc8812d38d0bdd91714d073b"))

    def test_one_identity_may_be_printed_across_multiple_schemes(self):
        output = "\n".join(
            f"{label}: certificate SHA-256 digest: {self.digest}"
            for label in ("V1 Signer", "V2 Signer", "V3.1 Signer")
        )
        self.assertEqual(checker.signing_identity(output), self.digest)
        octets = ":".join(["AB"] * 32)
        self.assertEqual(checker.signing_identity(
            f"Signer #1 certificate SHA-256 digest: {octets}"), self.digest)

    def test_multiple_conflicting_or_malformed_signers_are_rejected(self):
        one = f"Signer #1 certificate SHA-256 digest: {self.digest}\n"
        v2 = f"V2 Signer: certificate SHA-256 digest: {self.digest}\n"
        cases = [
            "", one + one, v2 + v2,
            one + f"Signer #2 certificate SHA-256 digest: {self.digest}",
            v2 + f"V3 Signer: certificate SHA-256 digest: {'cd' * 32}",
            f"Signer #1 certificate SHA-256 digest: :{self.digest}",
            f"Signer #1 certificate SHA-256 digest: {self.digest[:-1]}",
            "Signer #1 certificate SHA-256 digest: not-hex",
            f"Unknown Signer: certificate SHA-256 digest: {self.digest}",
        ]
        for value in cases:
            with self.subTest(output=value), self.assertRaises(RuntimeError):
                checker.signing_identity(value)

    def test_source_stamp_is_not_an_apk_signer(self):
        stamp = f"Source Stamp Signer certificate SHA-256 digest: {'cd' * 32}\n"
        with self.assertRaises(RuntimeError):
            checker.signing_identity(stamp)
        self.assertEqual(checker.signing_identity(
            stamp + f"V2 Signer: certificate SHA-256 digest: {self.digest}"), self.digest)

    def run_suite(self, *, bad_signer=False, omit_last=False, duplicate=False):
        core = self.root / "core.apk"
        core.write_bytes(b"core fixture")
        args = ["check", "--core", str(core), "--build-mode", "debug",
                "--report", str(self.root / "report.json")]
        results = [(checker.PREFIX, 12, self.digest)]
        plugins = list(checker.PLUGINS.items())
        if omit_last:
            plugins.pop()
        if duplicate:
            plugins.append(plugins[0])
        for index, (plugin_id, package) in enumerate(plugins):
            apk = self.root / f"{plugin_id}.apk"
            apk.write_bytes(plugin_id.encode())
            args += ["--plugin", plugin_id, str(apk)]
            signer = "cd" * 32 if bad_signer and index == 0 else self.digest
            results.append((package, index + 1, signer))
        with patch("sys.argv", args), patch.object(checker, "sdk_tool", side_effect=lambda x: x), \
                patch.object(checker, "details", side_effect=results), redirect_stdout(io.StringIO()):
            checker.main()

    def test_complete_suite_writes_real_sizes_and_independent_versions(self):
        self.run_suite()
        report = json.loads((self.root / "report.json").read_text())
        self.assertEqual(report["buildMode"], "debug")
        self.assertEqual(len(report["artifacts"]), 7)
        self.assertEqual(report["artifacts"][1]["versionCode"], 1)
        for record in report["artifacts"]:
            self.assertEqual(record["bytes"], (self.root / record["file"]).stat().st_size)
            self.assertEqual(len(record["sha256"]), 64)
            self.assertEqual(record["signerSha256"], self.digest)

    def test_incomplete_or_incompatible_set_cannot_emit_success_report(self):
        for kwargs, message in (({"bad_signer": True}, "NOT signed"),
                                ({"omit_last": True}, "Expected all"),
                                ({"duplicate": True}, "Duplicate plugin")):
            with self.subTest(kwargs=kwargs), self.assertRaisesRegex(RuntimeError, message):
                self.run_suite(**kwargs)
            self.assertFalse((self.root / "report.json").exists())


if __name__ == "__main__":
    unittest.main()
