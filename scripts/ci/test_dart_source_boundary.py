"""Regression cases for real Dart directive syntax and source escapes."""
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from dart_source_boundary import directive_uris, verify_dart_sources


class DartSourceBoundaryTest(unittest.TestCase):
    def setUp(self):
        self.tmp = TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.stage = Path(self.tmp.name) / "stage"
        self.lib = self.stage / "lib"
        self.lib.mkdir(parents=True)
        (self.lib / "stub.dart").write_text("class Stub {}")

    def verify(self, source):
        (self.lib / "main.dart").write_text(source)
        return verify_dart_sources(self.stage, own_package="drawing", allowed_packages={"flutter"})

    def test_all_conditional_directives_are_checked(self):
        for directive in ("import", "export"):
            with self.subTest(directive=directive), self.assertRaisesRegex(RuntimeError, "forbidden package"):
                self.verify(f"{directive} 'stub.dart'\n if (dart.library.io == 'true') 'package:fluxdo/hidden.dart';")

    def test_conditional_export_to_missing_local_source_rejected(self):
        with self.assertRaisesRegex(RuntimeError, "missing source"):
            self.verify("export 'stub.dart' if (dart.library.io) 'absent.dart';")

    def test_comments_and_body_literals_are_not_imports(self):
        source = '''/* import 'missing.dart'; /* nested */ */
// export 'missing.dart';
library drawing;
import /* notes */ 'stub.dart';
@Deprecated("part 'missing.dart';")
class Example { final code = "import 'missing.dart';"; }
'''
        self.assertEqual(self.verify(source), set())

    def test_annotations_before_directives_preserve_the_import_graph(self):
        self.assertEqual(directive_uris('''@pragma('vm:entry-point')
library;
@prefix.Experimental<int>('some metadata')
export r'stub.dart' if (dart.library.html) 'web.dart';
class Example {}
'''), ["stub.dart", "web.dart"])

    def test_part_and_own_package_imports_are_resolved(self):
        (self.lib / "child.dart").write_text("part of 'main.dart';\nclass Child {}")
        self.verify("import 'package:drawing/stub.dart'; part 'child.dart';")
        with self.assertRaisesRegex(RuntimeError, "missing source"):
            self.verify("part 'missing.dart';")

    def test_parent_and_percent_encoded_escape_rejected(self):
        outside = Path(self.tmp.name) / "outside.dart"
        outside.write_text("class Escaped {}")
        for uri in ("../../outside.dart", "%2e%2e/%2e%2e/outside.dart",
                    "package:drawing/../../outside.dart"):
            with self.subTest(uri=uri), self.assertRaisesRegex(RuntimeError, "escapes stage"):
                self.verify(f"import '{uri}';")

    def test_symlink_cannot_import_host_sources(self):
        outside = Path(self.tmp.name) / "host.dart"
        outside.write_text("class Host {}")
        (self.lib / "link.dart").symlink_to(outside)
        with self.assertRaisesRegex(RuntimeError, "escapes stage"):
            self.verify("import 'link.dart';")

    def test_generated_source_exemption_is_exact(self):
        (self.lib / "main.dart").write_text("import 'generated.dart';")
        verify_dart_sources(self.stage, own_package="drawing", pending_generated={self.lib / "generated.dart"})
        with self.assertRaisesRegex(RuntimeError, "missing source"):
            verify_dart_sources(self.stage, own_package="drawing", pending_generated={self.lib / "other.dart"})

    def test_escaped_import_and_remote_uri_fail_closed(self):
        for source in (r"import 'st\u0075b.dart';", "import 'https://example.com/remote.dart';"):
            with self.subTest(source=source), self.assertRaises(RuntimeError):
                self.verify(source)


if __name__ == "__main__":
    unittest.main()
