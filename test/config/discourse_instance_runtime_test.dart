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

    test('normalizes scheme and host casing without changing path case', () {
      expect(
        DiscourseInstanceRuntime.normalizeBaseUrl(
          'HTTPS://Forum.Example.COM/Forum/',
        ),
        'https://forum.example.com/Forum',
      );
    });

    test('removes explicit default ports but preserves custom ports', () {
      expect(
        DiscourseInstanceRuntime.normalizeBaseUrl(
          'https://forum.example.com:443/forum',
        ),
        'https://forum.example.com/forum',
      );
      expect(
        DiscourseInstanceRuntime.normalizeBaseUrl(
          'http://forum.example.com:80/forum',
        ),
        'http://forum.example.com/forum',
      );
      expect(
        DiscourseInstanceRuntime.normalizeBaseUrl(
          'https://forum.example.com:8443/forum',
        ),
        'https://forum.example.com:8443/forum',
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

    test('derives custom namespace from base URL, not persisted id', () {
      const baseUrl = 'https://forum.example.com';
      final canonicalId = DiscourseInstanceRuntime.instanceIdForBaseUrl(
        baseUrl,
      );

      DiscourseInstanceRuntime.activate(
        instanceId: 'tampered-shared-id',
        baseUrl: baseUrl,
      );

      expect(DiscourseInstanceRuntime.instanceId, canonicalId);
      expect(
        DiscourseInstanceRuntime.scopedStorageKey('linux_do_username'),
        'linux_do_username::discourse_instance::${Uri.encodeComponent(canonicalId)}',
      );
    });

    test('keeps case-sensitive relative roots in distinct namespaces', () {
      final upper = DiscourseInstanceRuntime.instanceIdForBaseUrl(
        'https://forum.example.com/Forum',
      );
      final lower = DiscourseInstanceRuntime.instanceIdForBaseUrl(
        'https://forum.example.com/forum',
      );

      expect(upper, isNot(lower));
    });

    test('default-port aliases share one instance identity', () {
      final implicit = DiscourseInstanceRuntime.instanceIdForBaseUrl(
        'https://forum.example.com/forum',
      );
      final explicit = DiscourseInstanceRuntime.instanceIdForBaseUrl(
        'https://forum.example.com:443/forum',
      );

      expect(explicit, implicit);
    });

    test('default URL always restores legacy default identity', () {
      DiscourseInstanceRuntime.activate(
        instanceId: 'tampered-custom-id',
        baseUrl: 'https://LINUX.DO/',
      );

      expect(
        DiscourseInstanceRuntime.instanceId,
        DiscourseInstanceRuntime.defaultInstanceId,
      );
      expect(DiscourseInstanceRuntime.isDefaultInstance, isTrue);
    });
  });

  group('active instance uri boundary', () {
    test('custom relative-url-root rejects sibling paths and subdomains', () {
      DiscourseInstanceRuntime.activate(
        instanceId: 'site-test',
        baseUrl: 'https://forum.example.com:8443/forum',
      );

      expect(
        DiscourseInstanceRuntime.containsUri(
          Uri.parse('https://forum.example.com:8443/forum/t/1'),
        ),
        isTrue,
      );
      expect(
        DiscourseInstanceRuntime.pathWithinInstance(
          Uri.parse('https://forum.example.com:8443/forum/t/1'),
        ),
        '/t/1',
      );
      expect(
        DiscourseInstanceRuntime.containsUri(
          Uri.parse('https://forum.example.com:8443/other/t/1'),
        ),
        isFalse,
      );
      expect(
        DiscourseInstanceRuntime.containsUri(
          Uri.parse('https://cdn.forum.example.com:8443/forum/t/1'),
        ),
        isFalse,
      );
      expect(
        DiscourseInstanceRuntime.containsUri(
          Uri.parse('https://forum.example.com/forum/t/1'),
        ),
        isFalse,
      );
    });

    test('relative-url-root path matching remains case-sensitive', () {
      DiscourseInstanceRuntime.activate(
        instanceId: 'site-test',
        baseUrl: 'https://forum.example.com/Forum',
      );

      expect(
        DiscourseInstanceRuntime.containsUri(
          Uri.parse('https://forum.example.com/Forum/t/1'),
        ),
        isTrue,
      );
      expect(
        DiscourseInstanceRuntime.containsUri(
          Uri.parse('https://forum.example.com/forum/t/1'),
        ),
        isFalse,
      );
    });

    test('default linux.do keeps existing subdomain handling', () {
      expect(
        DiscourseInstanceRuntime.containsUri(
          Uri.parse('https://meta.linux.do/latest'),
        ),
        isTrue,
      );
      expect(
        DiscourseInstanceRuntime.pathWithinInstance(
          Uri.parse('https://meta.linux.do/t/1'),
        ),
        isNull,
      );
    });
  });
}
