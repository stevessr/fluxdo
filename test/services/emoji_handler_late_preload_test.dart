import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/emoji_handler.dart';
import 'package:fluxdo/services/preloaded_data_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final preload = PreloadedDataService();
  final handler = EmojiHandler();

  setUp(() => preload.debugSeedCustomEmoji(null));
  tearDown(() => preload.debugSeedCustomEmoji(null));

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
}
