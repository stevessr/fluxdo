import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluxdo/config/discourse_instance_runtime.dart';
import 'package:fluxdo/services/discourse_instance_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DiscourseInstanceRuntime.reset();
  });

  tearDown(DiscourseInstanceRuntime.reset);

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

  test('selected instance requires active id and URL to describe same site', () async {
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

    final selected = await DiscourseInstanceManager.instance.selectedInstance();

    expect(selected.id, DiscourseInstanceRuntime.defaultInstanceId);
  });

  test('valid selected instance still restores normally', () async {
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
}
