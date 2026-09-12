import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'package:fluxdo/config/discourse_instance_runtime.dart';
import 'package:fluxdo/services/network/cookie/cookie_jar_service.dart';

void main() {
  setUp(DiscourseInstanceRuntime.reset);
  tearDown(DiscourseInstanceRuntime.reset);

  group('CookieJarService multi-instance isolation', () {
    test('default linux.do keeps legacy cookie directory', () {
      final cookiePath = CookieJarService.debugCookieStoragePath('/documents');

      expect(cookiePath, path.join('/documents', '.cookies'));
    });

    test('custom instances receive separate persistent stores', () {
      DiscourseInstanceRuntime.activate(
        instanceId: 'forum-a',
        baseUrl: 'https://example.com/forum-a',
      );
      final first = CookieJarService.debugCookieStoragePath('/documents');

      DiscourseInstanceRuntime.activate(
        instanceId: 'forum-b',
        baseUrl: 'https://example.com/forum-b',
      );
      final second = CookieJarService.debugCookieStoragePath('/documents');

      expect(first, isNot(second));
      expect(path.basename(path.dirname(first)), '.cookies_instances');
      expect(path.basename(path.dirname(second)), '.cookies_instances');
    });

    test('custom instance does not inherit linux.do private critical cookie', () {
      expect(
        CookieJarService.criticalCookieNames,
        contains('linux_do_credit_session_id'),
      );

      DiscourseInstanceRuntime.activate(
        instanceId: 'generic',
        baseUrl: 'https://forum.example.com',
      );

      expect(
        CookieJarService.criticalCookieNames,
        isNot(contains('linux_do_credit_session_id')),
      );
      expect(CookieJarService.criticalCookieNames, contains('_t'));
      expect(CookieJarService.criticalCookieNames, contains('cf_clearance'));
    });

    test('custom host matching is exact while linux.do keeps subdomains', () {
      expect(CookieJarService.matchesAppHost('meta.linux.do'), isTrue);

      DiscourseInstanceRuntime.activate(
        instanceId: 'generic',
        baseUrl: 'https://forum.example.com/forum',
      );

      expect(CookieJarService.matchesAppHost('forum.example.com'), isTrue);
      expect(CookieJarService.matchesAppHost('.forum.example.com'), isTrue);
      expect(CookieJarService.matchesAppHost('cdn.forum.example.com'), isFalse);
    });
  });
}
