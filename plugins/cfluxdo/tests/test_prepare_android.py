"""Regression tests for independent CFluxDo Android plugin packaging."""

from __future__ import annotations

import tempfile
from pathlib import Path
import sys
import unittest
import xml.etree.ElementTree as ET

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from prepare_android import (  # noqa: E402
    ACTION,
    ANDROID,
    API_META,
    AUTH_HOST,
    AUTH_SCHEME,
    CATEGORY_META,
    PLUGINS,
    patch,
    verify,
)

FIXTURE_MANIFEST = """<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.CAMERA"/>
    <uses-permission android:name="android.permission.QUERY_ALL_PACKAGES"/>
    <uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES"/>
    <application android:label="CFluxDo">
        <activity android:name=".MainActivity" android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
            <intent-filter>
                <action android:name="android.intent.action.VIEW"/>
                <category android:name="android.intent.category.DEFAULT"/>
                <category android:name="android.intent.category.BROWSABLE"/>
                <data android:scheme="https" android:host="linux.do"/>
            </intent-filter>
            <intent-filter>
                <action android:name="android.intent.action.VIEW"/>
                <category android:name="android.intent.category.BROWSABLE"/>
                <data android:scheme="discourse"/>
            </intent-filter>
        </activity>
        <activity-alias android:name=".DefaultIcon" android:targetActivity=".MainActivity">
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity-alias>
    </application>
</manifest>"""


class PrepareAndroidTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.manifest = self.root / "android/app/src/main/AndroidManifest.xml"
        self.gradle = self.root / "android/app/build.gradle.kts"
        self.manifest.parent.mkdir(parents=True)
        self.manifest.write_text(FIXTURE_MANIFEST, encoding="utf-8")
        self.gradle.write_text(
            'applicationId = "com.github.molchuan.cfluxdo"\n',
            encoding="utf-8",
        )
        auth_service = self.root / "lib/services/user_api_key_service.dart"
        auth_service.parent.mkdir(parents=True)
        auth_service.write_text(
            "static const String applicationName = 'CFluxDo';\n",
            encoding="utf-8",
        )

    def _main(self) -> ET.Element:
        app = ET.parse(self.manifest).getroot().find("application")
        assert app is not None
        main = next(
            element for element in app.findall("activity")
            if element.get(ANDROID + "name") == ".MainActivity"
        )
        return main

    def test_both_apps_keep_only_plugin_and_narrow_oauth_entrypoints(self) -> None:
        for kind in PLUGINS:
            with self.subTest(kind=kind):
                self.setUp()
                patch(self.root, kind)
                verify(self.root, kind)
                main = self._main()
                filters = main.findall("intent-filter")
                self.assertEqual(len(filters), 2)
                by_action = {
                    action.get(ANDROID + "name"): item
                    for item in filters
                    for action in item.findall("action")
                }
                self.assertEqual(
                    set(by_action), {ACTION, "android.intent.action.VIEW"},
                )
                callback = by_action["android.intent.action.VIEW"]
                self.assertEqual(len(callback.findall("data")), 1)
                self.assertEqual(callback.find("data").get(ANDROID + "scheme"), AUTH_SCHEME)
                self.assertEqual(callback.find("data").get(ANDROID + "host"), AUTH_HOST)
                categories = {
                    item.get(ANDROID + "name")
                    for item in callback.findall("category")
                }
                self.assertEqual(categories, {
                    "android.intent.category.DEFAULT",
                    "android.intent.category.BROWSABLE",
                })
                metadata = {
                    item.get(ANDROID + "name"): item.get(ANDROID + "value")
                    for item in main.findall("meta-data")
                }
                self.assertEqual(metadata[API_META], "1")
                self.assertEqual(metadata[CATEGORY_META], "app")
                auth_service = (
                    self.root / "lib/services/user_api_key_service.dart"
                ).read_text(encoding="utf-8")
                self.assertIn(
                    "static const String applicationName = '"
                    + PLUGINS[kind]["auth_name"] + "';",
                    auth_service,
                )
                all_permissions = {
                    element.get(ANDROID + "name")
                    for element in ET.parse(self.manifest).getroot().findall(
                        "uses-permission"
                    )
                }
                self.assertIn("android.permission.CAMERA", all_permissions)
                self.assertNotIn("android.permission.QUERY_ALL_PACKAGES", all_permissions)
                self.assertNotIn("android.permission.REQUEST_INSTALL_PACKAGES", all_permissions)

    def test_rejects_broader_auth_callback(self) -> None:
        patch(self.root, "cdk")
        tree = ET.parse(self.manifest)
        data = tree.getroot().find(
            "./application/activity/intent-filter/data"
        )
        assert data is not None
        data.set(ANDROID + "host", "other_host")
        tree.write(self.manifest, encoding="unicode")
        with self.assertRaises(AssertionError):
            verify(self.root, "cdk")

    def test_rejects_undeclared_extra_web_deep_link(self) -> None:
        patch(self.root, "ldshop")
        tree = ET.parse(self.manifest)
        main = tree.getroot().find("./application/activity")
        assert main is not None
        extra = ET.SubElement(main, "intent-filter")
        action = ET.SubElement(extra, "action")
        action.set(ANDROID + "name", "android.intent.action.VIEW")
        data = ET.SubElement(extra, "data")
        data.set(ANDROID + "scheme", "https")
        data.set(ANDROID + "host", "linux.do")
        tree.write(self.manifest, encoding="unicode")
        with self.assertRaises(AssertionError):
            verify(self.root, "ldshop")

    def test_rejects_missing_oauth_entry(self) -> None:
        patch(self.root, "cdk")
        tree = ET.parse(self.manifest)
        main = tree.getroot().find("./application/activity")
        assert main is not None
        for entry in list(main.findall("intent-filter")):
            if any(a.get(ANDROID + "name") == "android.intent.action.VIEW"
                   for a in entry.findall("action")):
                main.remove(entry)
        tree.write(self.manifest, encoding="unicode")
        with self.assertRaises(AssertionError):
            verify(self.root, "cdk")


if __name__ == "__main__":
    unittest.main()
