import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/chat/chat_models.dart';
import 'package:fluxdo/widgets/chat/chat_thread_preview_card.dart';

void main() {
  test('new reply lifts an old thread above recently created thread', () {
    final old = ChatThread.fromJson({
      'id': 1, 'channel_id': 1,
      'original_message': {'id': 5, 'created_at': '2026-07-31T00:00:00Z'},
      'preview': {'last_reply_created_at': '2026-11-24T00:00:00Z', 'last_reply_id': 99},
    });
    final newer = ChatThread.fromJson({
      'id': 2, 'channel_id': 1,
      'original_message': {'id': 50, 'created_at': '2026-11-23T00:00:00Z'},
    });
    final items = [newer, old]..sort(ChatThread.compareRecentActivity);
    expect(items.map((item) => item.id), [1, 2]);
  });

  test('missing timestamps sort last, same times use message id', () {
    final time = DateTime.utc(2026, 11, 24);
    final items = [
      const ChatThread(id: 9, channelId: 1),
      ChatThread(id: 2, channelId: 1, preview: ChatThreadPreview(lastReplyCreatedAt: time, lastReplyId: 20)),
      ChatThread(id: 1, channelId: 1, preview: ChatThreadPreview(lastReplyCreatedAt: time, lastReplyId: 30)),
    ]..sort(ChatThread.compareRecentActivity);
    expect(items.map((item) => item.id), [1, 2, 9]);
  });

  test('cooked emoji previews retain shortcode and decode entities', () {
    expect(chatThreadPreviewText('<p>hi &amp; <img class="emoji" alt=":heart:" src="/emoji/heart.png"></p>'), 'hi & :heart:');
    expect(chatThreadPreviewText('<img class="emoji emoji-custom" alt="custom_sticker">'), ':custom_sticker:');
    expect(chatThreadPreviewText('你好 :smile: 😀'), '你好 :smile: 😀');
  });
}
