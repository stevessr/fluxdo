import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'package:fluxdo/config/discourse_instance_runtime.dart';
import 'package:fluxdo/services/network/cookie/app_cookie_manager.dart';
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

    test('subpath forum cookies are not sent to same-host sibling app', () async {
      DiscourseInstanceRuntime.activate(
        instanceId: 'generic',
        baseUrl: 'https://forum.example.com/forum',
      );
      final jar = CookieJar();
      final manager = AppCookieManager(jar);
      await jar.saveFromResponse(
        Uri.parse('https://forum.example.com/forum/session'),
        [Cookie('_t', 'forum-secret')..path = '/'],
      );

      expect(
        await manager.loadCookies(
          RequestOptions(path: 'https://forum.example.com/forum/posts.json'),
        ),
        contains('_t=forum-secret'),
      );
      expect(
        await manager.loadCookies(
          RequestOptions(path: 'https://forum.example.com/other/login'),
        ),
        isEmpty,
      );
      expect(
        AppCookieManager.isOutsideActiveInstanceRoot(
          Uri.parse('https://forum.example.com/forum-other'),
        ),
        isTrue,
      );
      expect(
        AppCookieManager.isOutsideActiveInstanceRoot(
          Uri.parse('https://forum.example.com:443/forum/posts.json'),
        ),
        isFalse,
      );
    });

    test('sibling Set-Cookie cannot overwrite a subpath forum session', () async {
      DiscourseInstanceRuntime.activate(
        instanceId: 'generic',
        baseUrl: 'https://forum.example.com/forum',
      );
      final jar = CookieJar();
      final manager = AppCookieManager(jar);
      await jar.saveFromResponse(
        Uri.parse('https://forum.example.com/forum/session'),
        [Cookie('_t', 'forum-secret')..path = '/'],
      );
      await manager.saveCookies(
        Response<dynamic>(
          requestOptions: RequestOptions(
            path: 'https://forum.example.com/other/login',
          ),
          statusCode: 200,
          headers: Headers.fromMap({
            'set-cookie': ['_t=sibling-secret; Path=/; HttpOnly'],
          }),
        ),
      );

      final cookies = await jar.loadForRequest(
        Uri.parse('https://forum.example.com/forum/posts.json'),
      );
      expect(
        cookies.where((cookie) => cookie.name == '_t').single.value,
        'forum-secret',
      );
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
