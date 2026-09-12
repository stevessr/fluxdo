import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluxdo/config/discourse_instance_runtime.dart';
import 'package:fluxdo/services/discourse_instance_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    DiscourseInstanceRuntime.reset();
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    DiscourseInstanceRuntime.reset();
  });

  test('persisted custom id is ignored in favor of URL-derived identity', () {
    final profile = DiscourseInstanceProfile.fromJson({
      'id': 'shared-or-tampered-id',
      'name': 'Forum A',
      'base_url': 'https://forum.example.com/a',
    });

    expect(
      profile.id,
      DiscourseInstanceRuntime.instanceIdForBaseUrl(
        'https://forum.example.com/a',
      ),
    );
    expect(profile.id, isNot('shared-or-tampered-id'));
  });

  test('selected instance fails closed when active URL is corrupted', () async {
    const baseUrl = 'https://forum.example.com/forum';
    final id = DiscourseInstanceRuntime.instanceIdForBaseUrl(baseUrl);
    SharedPreferences.setMockInitialValues({
      DiscourseInstanceRuntime.enabledPrefKey: true,
      DiscourseInstanceRuntime.instancesPrefKey: jsonEncode([
        {'id': id, 'name': 'Forum', 'base_url': baseUrl},
      ]),
      DiscourseInstanceRuntime.activeInstanceIdPrefKey: id,
      DiscourseInstanceRuntime.activeBaseUrlPrefKey: 'ftp://broken.example.com',
    });

    final selected = await DiscourseInstanceManager.instance.selectedInstance();

    expect(selected.id, DiscourseInstanceRuntime.defaultInstanceId);
    expect(selected.baseUrl, DiscourseInstanceRuntime.defaultBaseUrl);
  });

  test('selected instance requires both active identity fields', () async {
    const baseUrl = 'https://forum.example.com/forum';
    final id = DiscourseInstanceRuntime.instanceIdForBaseUrl(baseUrl);
    SharedPreferences.setMockInitialValues({
      DiscourseInstanceRuntime.enabledPrefKey: true,
      DiscourseInstanceRuntime.instancesPrefKey: jsonEncode([
        {'id': id, 'name': 'Forum', 'base_url': baseUrl},
      ]),
      DiscourseInstanceRuntime.activeInstanceIdPrefKey: id,
    });

    final selected = await DiscourseInstanceManager.instance.selectedInstance();

    expect(selected.id, DiscourseInstanceRuntime.defaultInstanceId);
  });

  test(
    'selected instance requires active id and URL to describe same site',
    () async {
      const firstUrl = 'https://forum.example.com/a';
      const secondUrl = 'https://forum.example.com/b';
      final firstId = DiscourseInstanceRuntime.instanceIdForBaseUrl(firstUrl);
      final secondId = DiscourseInstanceRuntime.instanceIdForBaseUrl(secondUrl);
      SharedPreferences.setMockInitialValues({
        DiscourseInstanceRuntime.enabledPrefKey: true,
        DiscourseInstanceRuntime.instancesPrefKey: jsonEncode([
          {'id': firstId, 'name': 'A', 'base_url': firstUrl},
          {'id': secondId, 'name': 'B', 'base_url': secondUrl},
        ]),
        DiscourseInstanceRuntime.activeInstanceIdPrefKey: firstId,
        DiscourseInstanceRuntime.activeBaseUrlPrefKey: secondUrl,
      });

      final selected = await DiscourseInstanceManager.instance
          .selectedInstance();

      expect(selected.id, DiscourseInstanceRuntime.defaultInstanceId);
    },
  );

  test('valid selected HTTP instance still restores on Android', () async {
    const baseUrl = 'http://localhost:3000/forum';
    final id = DiscourseInstanceRuntime.instanceIdForBaseUrl(baseUrl);
    SharedPreferences.setMockInitialValues({
      DiscourseInstanceRuntime.enabledPrefKey: true,
      DiscourseInstanceRuntime.instancesPrefKey: jsonEncode([
        {'id': 'legacy-wrong-id', 'name': 'Local', 'base_url': baseUrl},
      ]),
      DiscourseInstanceRuntime.activeInstanceIdPrefKey: id,
      DiscourseInstanceRuntime.activeBaseUrlPrefKey: baseUrl,
    });

    final selected = await DiscourseInstanceManager.instance.selectedInstance();

    expect(selected.id, id);
    expect(selected.name, 'Local');
    expect(selected.baseUrl, baseUrl);
  });

  test('iOS rejects adding an insecure HTTP instance', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    await expectLater(
      DiscourseInstanceManager.instance.addInstance(
        name: 'Local',
        baseUrl: 'http://localhost:3000/forum',
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('HTTPS'),
        ),
      ),
    );
  });

  test('iOS fails closed for a previously persisted HTTP selection', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    const baseUrl = 'http://forum.example.com/forum';
    final id = DiscourseInstanceRuntime.instanceIdForBaseUrl(baseUrl);
    SharedPreferences.setMockInitialValues({
      DiscourseInstanceRuntime.enabledPrefKey: true,
      DiscourseInstanceRuntime.instancesPrefKey: jsonEncode([
        {'id': id, 'name': 'Old HTTP Forum', 'base_url': baseUrl},
      ]),
      DiscourseInstanceRuntime.activeInstanceIdPrefKey: id,
      DiscourseInstanceRuntime.activeBaseUrlPrefKey: baseUrl,
    });

    final selected = await DiscourseInstanceManager.instance.selectedInstance();

    expect(selected.id, DiscourseInstanceRuntime.defaultInstanceId);
    expect(selected.baseUrl, DiscourseInstanceRuntime.defaultBaseUrl);
  });

  test(
    'removing the selected next-start instance falls back to linux.do',
    () async {
      await DiscourseInstanceManager.instance.setEnabled(true);
      final custom = await DiscourseInstanceManager.instance.addInstance(
        name: 'Forum',
        baseUrl: 'https://forum.example.com/forum',
      );
      await DiscourseInstanceManager.instance.selectInstance(custom.id);

      await DiscourseInstanceManager.instance.removeInstance(custom.id);

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(DiscourseInstanceRuntime.activeInstanceIdPrefKey),
        DiscourseInstanceRuntime.defaultInstanceId,
      );
      expect(
        prefs.getString(DiscourseInstanceRuntime.activeBaseUrlPrefKey),
        DiscourseInstanceRuntime.defaultBaseUrl,
      );
      expect(
        (await DiscourseInstanceManager.instance.selectedInstance()).id,
        DiscourseInstanceRuntime.defaultInstanceId,
      );
    },
  );
}
