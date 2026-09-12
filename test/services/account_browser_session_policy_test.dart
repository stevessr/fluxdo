import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/config/discourse_instance_runtime.dart';
import 'package:fluxdo/services/account_browser_session_policy.dart';

void main() {
  setUp(DiscourseInstanceRuntime.reset);
  tearDown(DiscourseInstanceRuntime.reset);

  group('AccountBrowserSessionPolicy', () {
    test('includes AnyRouter in per-account browser snapshots', () {
      expect(
        AccountBrowserSessionPolicy.snapshotOrigins,
        contains('https://anyrouter.top/'),
      );
      expect(
        AccountBrowserSessionPolicy.isExternalAccountOrigin(
          'https://anyrouter.top/login',
        ),
        isTrue,
      );
    });

    test('allows only HTTPS exact-host external restores', () {
      expect(
        AccountBrowserSessionPolicy.isAllowedRestoreOrigin(
          'https://anyrouter.top/account',
        ),
        isTrue,
      );
      expect(
        AccountBrowserSessionPolicy.isAllowedRestoreOrigin(
          'http://anyrouter.top/account',
        ),
        isFalse,
      );
      expect(
        AccountBrowserSessionPolicy.isAllowedRestoreOrigin(
          'https://sub.anyrouter.top/account',
        ),
        isFalse,
      );
      expect(
        AccountBrowserSessionPolicy.isAllowedRestoreOrigin(
          'https://anyrouter.top.evil.example/account',
        ),
        isFalse,
      );
    });

    test('continues to allow app-owned origins', () {
      expect(
        AccountBrowserSessionPolicy.isAllowedRestoreOrigin(
          'https://credit.linux.do/',
        ),
        isTrue,
      );
    });

    test('custom instance snapshots only the active discourse origin', () {
      DiscourseInstanceRuntime.activate(
        instanceId: 'local-discourse',
        baseUrl: 'http://forum.example.test/forum',
      );

      expect(
        AccountBrowserSessionPolicy.snapshotOrigins,
        ['http://forum.example.test/forum/'],
      );
      expect(
        AccountBrowserSessionPolicy.isAllowedRestoreOrigin(
          'http://forum.example.test/forum/session',
        ),
        isTrue,
      );
      expect(
        AccountBrowserSessionPolicy.isAllowedRestoreOrigin(
          'https://forum.example.test/forum/session',
        ),
        isFalse,
      );
      expect(
        AccountBrowserSessionPolicy.isAllowedRestoreOrigin(
          'https://anyrouter.top/account',
        ),
        isFalse,
      );
    });
  });
}
