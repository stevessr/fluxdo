import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/preloaded_data_decoder.dart';

void main() {
  group('PreloadedDataDecoder', () {
    test('decodes eager keys and keeps heavy payloads lazy', () {
      final raw = jsonEncode({
        'currentUser': jsonEncode({'id': 42, 'username': 'fish'}),
        'siteSettings': jsonEncode({'chat_enabled': true}),
        'site': jsonEncode({
          'categories': [
            {'id': 1, 'name': 'General'},
          ],
        }),
        'topicTrackingStateMeta': jsonEncode({'/latest': 123}),
        'customEmoji': jsonEncode([
          {'name': 'blobcat', 'url': '/emoji/blobcat.png'},
        ]),
        'topicTrackingStates': jsonEncode([
          {'topic_id': 1, 'last_read_post_number': 2},
        ]),
        'topicList': jsonEncode({
          'topic_list': {
            'topics': [
              {'id': 99, 'title': 'Hello'},
            ],
          },
        }),
        'unusedLargePayload': 'x' * 20000,
      });

      final decoded = PreloadedDataDecoder.decode(
        raw,
        htmlEntityEncoded: false,
      );

      expect(decoded, isNotNull);
      expect(decoded!['currentUser'], {'id': 42, 'username': 'fish'});
      expect(decoded['siteSettings'], {'chat_enabled': true});
      expect(decoded['site'], isA<Map<String, dynamic>>());
      expect(decoded['topicTrackingStateMeta'], {'/latest': 123});
      expect(decoded['customEmoji'], isA<List<dynamic>>());
      expect(decoded['topicTrackingStates'], isA<String>());
      expect(decoded['topicList'], isA<String>());
      expect(decoded, isNot(contains('unusedLargePayload')));
    });

    test('handles braces, commas and escapes inside skipped strings', () {
      final raw = jsonEncode({
        'ignored': r'noise { [ ] }, \\ " still string',
        'currentUser': jsonEncode({'id': 7, 'name': 'A { tricky }, value'}),
        'siteSettings': jsonEncode({'min_post_length': 8}),
        'site': jsonEncode({'categories': <Object>[]}),
      });

      final decoded = PreloadedDataDecoder.decode(
        raw,
        htmlEntityEncoded: false,
      );

      expect(decoded!['currentUser']['id'], 7);
      expect(decoded['currentUser']['name'], 'A { tricky }, value');
      expect(decoded, isNot(contains('ignored')));
    });

    test('supports already-decoded eager values', () {
      final raw = jsonEncode({
        'currentUser': {'id': 3},
        'siteSettings': {'chat_enabled': false},
        'site': {'categories': <Object>[]},
      });

      final decoded = PreloadedDataDecoder.decode(
        raw,
        htmlEntityEncoded: false,
      );

      expect(decoded!['currentUser'], {'id': 3});
      expect(decoded['siteSettings'], {'chat_enabled': false});
    });

    test('supports legacy HTML-entity encoded payloads', () {
      final raw = jsonEncode({
        'currentUser': jsonEncode({'id': 5}),
        'siteSettings': jsonEncode({'title': 'A&B'}),
        'site': jsonEncode({'categories': <Object>[]}),
      }).replaceAll('&', '&amp;').replaceAll('"', '&quot;');

      final decoded = PreloadedDataDecoder.decode(raw, htmlEntityEncoded: true);

      expect(decoded!['currentUser'], {'id': 5});
      expect(decoded['siteSettings'], {'title': 'A&B'});
    });

    test('returns null for non-object top-level JSON', () {
      expect(
        PreloadedDataDecoder.decode('[]', htmlEntityEncoded: false),
        isNull,
      );
    });
  });
}
