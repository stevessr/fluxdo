import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/mini_app.dart';

void main() {
  final site = Uri.parse('https://linux.do');

  test('parses paginated mini-app directory responses', () {
    final result = MiniAppDirectory.parse(
      {
        'apps': [
          {
            'id': '01a19674-905b-7246-99ff-2f5e270a3f8f',
            'name': 'Example app',
            'description': 'A hosted application',
            'age_rating': 4,
          },
        ],
        'total': 25,
        'page': 0,
        'per_page': 24,
      },
      site: site,
      requestedPage: 0,
    );
    expect(result.apps, hasLength(1));
    expect(
      result.apps.first.url.toString(),
      'https://linux.do/apps/01a19674-905b-7246-99ff-2f5e270a3f8f',
    );
    expect(result.apps.first.ageRating, 4);
    expect(result.hasNext, isTrue);
    expect(result.page, 0);
  });

  test('accepts legacy array format', () {
    final result = MiniAppDirectory.parse(
      [
        {'slug': 'example-app', 'title': 'Example'},
      ],
      site: site,
      requestedPage: 0,
    );
    expect(result.apps.single.name, 'Example');
    expect(result.hasNext, isFalse);
  });

  test('ignores arbitrary and misleading mini app destinations', () {
    final result = MiniAppDirectory.parse(
      {
        'apps': [
          {'id': 'bad', 'url': 'https://evil.example/apps/bad'},
          {'id': 'bad2', 'url': '/t/topic/123'},
          {'id': '../escape'},
          {'id': 'safe', 'url': '/apps/safe?from=directory'},
        ],
        'total': 4,
        'page': 0,
        'per_page': 24,
      },
      site: site,
      requestedPage: 0,
    );
    expect(result.apps.map((app) => app.id), ['safe']);
    expect(result.apps.single.url.queryParameters['from'], 'directory');
  });


  test('uses raw page size before filtering, and honors explicit pagination', () {
    final result = MiniAppDirectory.parse(
      {
        'data': {
          'apps': [
            {'id': 'safe', 'name': 'Safe'},
            {'id': 'safe', 'name': 'Duplicate'},
            {'id': 'unsafe', 'url': 'https://elsewhere.test/apps/unsafe'},
          ],
          'pagination': {'has_next': true, 'next_page': 4},
        },
      },
      site: site,
      requestedPage: 3,
    );
    expect(result.apps.map((app) => app.name), ['Safe']);
    expect(result.rawCount, 3);
    expect(result.nextPage, 4);
    expect(result.hasNext, isTrue);
  });

  test('keeps pagination metadata from the outer data wrapper', () {
    final result = MiniAppDirectory.parse(
      {
        'total': 25,
        'page': 0,
        'per_page': 24,
        'data': {
          'apps': [
            {'id': 'wrapped'},
          ],
        },
      },
      site: site,
      requestedPage: 0,
    );
    expect(result.apps.single.id, 'wrapped');
    expect(result.hasNext, isTrue);
    expect(result.nextPage, 1);
  });

  test('honors explicit end even with a full page', () {
    final result = MiniAppDirectory.parse(
      {
        'apps': List.generate(24, (i) => {'id': 'app-$i'}),
        'has_next': false,
      },
      site: site,
      requestedPage: 0,
    );
    expect(result.apps, hasLength(24));
    expect(result.hasNext, isFalse);
  });

  test('prevents endless loading on an empty response', () {
    final result = MiniAppDirectory.parse(
      {'apps': [], 'has_next': true, 'total': 1000},
      site: site,
      requestedPage: 0,
    );
    expect(result.hasNext, isFalse);
    expect(result.rawCount, 0);
  });

  test('does not accept insecure icon URLs or malformed map keys', () {
    final result = MiniAppDirectory.parse(
      {
        'apps': [
          {'id': 'safe', 'icon_url': 'http://example.test/icon.png'},
          {123: 'strange', 'slug': 'other'},
        ],
      },
      site: site,
      requestedPage: 0,
    );
    expect(result.apps, hasLength(2));
    expect(result.apps.first.iconUrl, isNull);
  });

  test('skips malformed destinations without losing neighboring apps', () {
    final result = MiniAppDirectory.parse(
      {
        'apps': [
          {'id': 'broken', 'url': 'https://%invalid/apps/broken'},
          {'id': 'valid', 'icon_url': 'https://%invalid/icon.png'},
        ],
      },
      site: site,
      requestedPage: 0,
    );
    expect(result.apps.map((app) => app.id), ['valid']);
    expect(result.apps.single.iconUrl, isNull);
  });

  test('rejects unknown response formats', () {
    expect(
      () =>
          MiniAppDirectory.parse({'topics': []}, site: site, requestedPage: 0),
      throwsFormatException,
    );
  });
}
