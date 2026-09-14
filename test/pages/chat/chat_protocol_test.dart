import 'package:fluxdo/pages/chat/chat_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatProtocol persistence', () {
    test('keeps a stable protocol order', () {
      expect(
        chatProtocolOrder,
        <ChatProtocol>[
          ChatProtocol.discourse,
          ChatProtocol.matrix,
          ChatProtocol.telegram,
        ],
      );
    });

    test('round-trips every storage value', () {
      for (final protocol in ChatProtocol.values) {
        expect(chatProtocolFromStorage(protocol.storageValue), protocol);
      }
    });

    test('falls back to Discourse for missing or unknown values', () {
      expect(chatProtocolFromStorage(null), ChatProtocol.discourse);
      expect(chatProtocolFromStorage(''), ChatProtocol.discourse);
      expect(chatProtocolFromStorage('future-provider'), ChatProtocol.discourse);
    });
  });
}
