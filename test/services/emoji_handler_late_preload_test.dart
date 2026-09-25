import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/emoji.dart';
import 'package:fluxdo/services/emoji_handler.dart';
import 'package:fluxdo/services/preloaded_data_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final preload = PreloadedDataService();
  final handler = EmojiHandler();

  setUp(() => preload.reset());
  tearDown(() => preload.reset());

  test('late preload replaces fallback emoji URLs and updates listeners', () {
    final updates = <String>[];
    void onChange() => updates.add(handler.getEmojiUrl('forum_test'));
    handler.addListener(onChange);
    addTearDown(() => handler.removeListener(onChange));

    expect(
      handler.getEmojiUrl('forum_test'),
      contains('/images/emoji/twitter/forum_test.png'),
    );

    preload.debugSeedCustomEmoji([
      {'name': 'forum_test', 'url': 'https://example.com/forum-test.png'},
    ]);
    expect(
      handler.getEmojiUrl('forum_test'),
      'https://example.com/forum-test.png',
    );
    expect(updates, ['https://example.com/forum-test.png']);

    // Rehydrating the same data should not rebuild every rendered emoji.
    preload.debugSeedCustomEmoji([
      {'name': 'forum_test', 'url': 'https://example.com/forum-test.png'},
    ]);
    expect(updates, hasLength(1));
  });

  test('fallback respects the server emoji set and external emoji URL', () {
    preload.debugSeed(
      siteSettings: {
        'emoji_set': 'apple',
        'external_emoji_url': 'https://emoji.example.com/assets/',
      },
    );

    expect(
      handler.getEmojiUrl('smile'),
      'https://emoji.example.com/assets/apple/smile.png',
    );
    expect(
      handler.getEmojiUrl('wave:t2'),
      'https://emoji.example.com/assets/apple/wave/t2.png',
    );
  });

  test('refresh updates URL and session reset removes stale custom emoji', () {
    preload.debugSeedCustomEmoji([
      {'name': 'forum_test', 'url': 'https://example.com/old.png'},
    ]);
    expect(handler.getEmojiUrl('forum_test'), 'https://example.com/old.png');

    preload.debugSeedCustomEmoji([
      {'name': 'forum_test', 'url': 'https://example.com/new.png'},
    ]);
    expect(handler.getEmojiUrl('forum_test'), 'https://example.com/new.png');

    preload.reset();
    expect(
      handler.getEmojiUrl('forum_test'),
      contains('/images/emoji/twitter/forum_test.png'),
    );
  });

  test(
    'server catalog resolves custom reactions missing from home preload',
    () {
      const name = 'reaction_catalog_fixture';
      expect(
        handler.getEmojiUrl(name),
        contains('/images/emoji/twitter/$name.png'),
      );

      handler.registerCatalog({
        'custom': [
          Emoji(
            name: name,
            url: 'https://cdn.example.com/reactions/real.png',
            group: 'custom',
          ),
          Emoji(name: 'deleted_fixture', url: '', group: 'custom'),
        ],
      });
      expect(
        handler.getEmojiUrl(name),
        'https://cdn.example.com/reactions/real.png',
      );
      expect(
        handler.getEmojiUrl('deleted_fixture'),
        contains('/images/emoji/twitter/deleted_fixture.png'),
      );

      // The exact URL in /emojis.json is also available to the picker when
      // the server catalog has not yet populated a separate image widget.
      expect(
        handler.getEmojiUrl(
          'uncached_picker_fixture',
          serverUrl: 'https://cdn.example.com/emoji/picker.png',
        ),
        'https://cdn.example.com/emoji/picker.png',
      );
    },
  );

  test('session reset drops server catalog URLs from the previous session', () {
    const name = 'stale_reaction_fixture';
    handler.registerCatalog({
      'custom': [
        Emoji(
          name: name,
          url: 'https://cdn.example.com/reactions/stale.png',
          group: 'custom',
        ),
      ],
    });
    expect(
      handler.getEmojiUrl(name),
      'https://cdn.example.com/reactions/stale.png',
    );

    preload.reset();
    expect(
      handler.getEmojiUrl(name),
      contains('/images/emoji/twitter/$name.png'),
    );
  });

  test(
    'current preload beats catalog and clearing preload drops stale URLs',
    () {
      const name = 'reaction_catalog_fixture';
      handler.registerCatalog({
        'custom': [
          Emoji(
            name: name,
            url: 'https://cdn.example.com/reactions/cached.png',
            group: 'custom',
          ),
        ],
      });
      preload.debugSeedCustomEmoji([
        {'name': name, 'url': 'https://cdn.example.com/reactions/current.png'},
      ]);
      expect(
        handler.getEmojiUrl(name),
        'https://cdn.example.com/reactions/current.png',
      );
      // debugSeedCustomEmoji publishes a preload revision while this test
      // intentionally keeps preload in the not-loaded state. That models a
      // session/site boundary, so the old catalog must be discarded as stale.
      preload.debugSeedCustomEmoji(null);
      expect(
        handler.getEmojiUrl(name),
        contains('/images/emoji/twitter/$name.png'),
      );
    },
  );
}
