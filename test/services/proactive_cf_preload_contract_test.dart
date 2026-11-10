import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String coordinator;
  late String startup;
  late String preferences;
  late String settings;
  late String challenge;

  setUpAll(() {
    coordinator = File('lib/services/browser_trust_coordinator.dart')
        .readAsStringSync();
    startup = File('lib/main.dart').readAsStringSync();
    preferences = File('lib/providers/preferences_provider.dart')
        .readAsStringSync();
    settings = File('lib/settings/definitions/custom_settings_defs.dart')
        .readAsStringSync();
    challenge = File('lib/services/cf_challenge_service.dart')
        .readAsStringSync();
  });

  test('默认关闭的实验策略被持久化并同步至验证服务', () {
    expect(preferences, contains('pref_proactive_cf_before_preload'));
    expect(preferences, contains(
      '_prefs.getBool(proactiveCfBeforePreloadKey) ?? false',
    ));
    expect(preferences, contains(
      'state.copyWith(proactiveCfBeforePreload: enabled)',
    ));
    expect(preferences, contains(
      'CfChallengeService().proactiveVerifyBeforePreloadEnabled = enabled',
    ));
    expect(settings, contains("id: 'proactiveCfBeforePreload'"));
    expect(settings, contains('.setProactiveCfBeforePreload(value)'));
    expect(challenge, contains(
      'bool proactiveVerifyBeforePreloadEnabled = false',
    ));
  });

  test('预加载早于 ProviderScope：启动入口应先读取保存的开关', () {
    final flag = startup.indexOf(
      'prefs.getBool(PreferencesNotifier.proactiveCfBeforePreloadKey)',
    );
    final preload = startup.indexOf(".ensurePreloaded(reason: 'startup')");
    expect(flag, greaterThanOrEqualTo(0));
    expect(preload, greaterThan(flag));
    expect(startup, contains("prefs.getBool('pref_auto_cf_challenge')"));
  });

  test('验证与 Cookie 同步发生在预加载前，且遵循全局开关与冷却期', () {
    final verify = coordinator.indexOf('Future<void> _verifyCfBeforePreload');
    final start = coordinator.indexOf(
      'Future<void> _ensurePreloadedInternal',
    );
    final probe = coordinator.indexOf(
      '_preload.ensureLoaded(suppressCfChallenge: true)',
      start,
    );
    expect(verify, greaterThanOrEqualTo(0));
    expect(start, greaterThan(verify));
    expect(probe, greaterThan(start));
    expect(coordinator.substring(start, probe),
        contains('await _verifyCfBeforePreload(reason: reason)'));

    final body = coordinator.substring(verify, start);
    final result = body.indexOf('await cf.showManualVerify');
    final sync = body.indexOf('await cf.waitForCompletionCookieSync()');
    final teardown = body.indexOf('await cf.waitForManualTeardown()');
    expect(result, greaterThanOrEqualTo(0));
    expect(sync, greaterThan(result));
    expect(teardown, greaterThan(sync));
    expect(body, contains('!cf.proactiveVerifyBeforePreloadEnabled'));
    expect(body, contains('!cf.autoVerifyEnabled'));
    expect(body, contains('cf.isInCooldown'));
    expect(coordinator, contains('final active = _activePreload;'));
  });
}
