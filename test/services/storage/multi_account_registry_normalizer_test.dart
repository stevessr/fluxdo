import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/storage/multi_account_registry_normalizer.dart';

void main() {
  group('MultiAccountRegistryNormalizer', () {
    test('collapses exact duplicate usernames and keeps newest metadata', () {
      final raw = jsonEncode([
        {
          'username': 'stevessr',
          'avatar_template': '/old/{size}.png',
          'saved_at': '2026-09-10T10:00:00.000Z',
        },
        {
          'username': 'stevessr',
          'avatar_template': '/new/{size}.png',
          'saved_at': '2026-09-11T10:00:00.000Z',
        },
      ]);

      final normalized =
          jsonDecode(MultiAccountRegistryNormalizer.normalize(raw))
              as List<dynamic>;

      expect(normalized, hasLength(1));
      expect(normalized.single['username'], 'stevessr');
      expect(normalized.single['avatar_template'], '/new/{size}.png');
    });

    test('treats case and surrounding whitespace as the same account', () {
      final raw = jsonEncode([
        {'username': 'SteveSSR', 'saved_at': '2026-09-10T10:00:00.000Z'},
        {'username': '  stevessr  ', 'saved_at': '2026-09-11T10:00:00.000Z'},
      ]);

      final normalized =
          jsonDecode(MultiAccountRegistryNormalizer.normalize(raw))
              as List<dynamic>;

      expect(normalized, hasLength(1));
      expect(normalized.single['username'], 'stevessr');
      expect(normalized.single['saved_at'], '2026-09-11T10:00:00.000Z');
    });

    test('preserves distinct accounts and their order', () {
      final raw = jsonEncode([
        {'username': 'alice', 'saved_at': '2026-09-11T10:00:00.000Z'},
        {'username': 'bob', 'saved_at': '2026-09-11T09:00:00.000Z'},
      ]);

      expect(MultiAccountRegistryNormalizer.normalize(raw), raw);
    });

    test('leaves malformed payloads untouched for existing recovery logic', () {
      const malformed = '[{"username": 123}]';
      expect(MultiAccountRegistryNormalizer.normalize(malformed), malformed);
    });

    test('normalization is idempotent', () {
      final raw = jsonEncode([
        {'username': 'Alice', 'saved_at': '2026-09-10T10:00:00.000Z'},
        {'username': 'alice', 'saved_at': '2026-09-11T10:00:00.000Z'},
      ]);
      final once = MultiAccountRegistryNormalizer.normalize(raw);
      final twice = MultiAccountRegistryNormalizer.normalize(once);

      expect(twice, once);
    });
  });
}
