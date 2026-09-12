import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/config/discourse_instance_runtime.dart';

void main() {
  tearDown(DiscourseInstanceRuntime.reset);

  group('DiscourseInstanceRuntime.normalizeBaseUrl', () {
    test('adds https and removes trailing slash', () {
      expect(
        DiscourseInstanceRuntime.normalizeBaseUrl('meta.discourse.org/'),
        'https://meta.discourse.org',
      );
    });

    test('preserves relative-url-root and strips query/fragment', () {
      expect(
        DiscourseInstanceRuntime.normalizeBaseUrl(
          'https://example.com/forum/?foo=1#bar',
        ),
        'https://example.com/forum',
      );
    });

    test('rejects non-http schemes and credentials', () {
      expect(
        () => DiscourseInstanceRuntime.normalizeBaseUrl('ftp://example.com'),
        throwsFormatException,
      );
      expect(
        () => DiscourseInstanceRuntime.normalizeBaseUrl(
          'https://user:pass@example.com',
        ),
        throwsFormatException,
      );
    });
  });

  group('instance scoped storage', () {
    test('keeps legacy key for linux.do', () {
      expect(
        DiscourseInstanceRuntime.scopedStorageKey('linux_do_username'),
        'linux_do_username',
      );
    });

    test('namespaces custom instance keys', () {
      DiscourseInstanceRuntime.activate(
        instanceId: 'site-test',
        baseUrl: 'https://forum.example.com',
      );
      expect(
        DiscourseInstanceRuntime.scopedStorageKey('linux_do_username'),
        'linux_do_username::discourse_instance::site-test',
      );
    });
  });
}
