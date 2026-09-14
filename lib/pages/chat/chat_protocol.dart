import 'package:flutter/material.dart';

/// Protocol identities exposed by the experimental chat hub.
///
/// Keep this model UI/service agnostic so Matrix can later switch from the
/// lightweight REST adapter to the Extera-backed SDK without changing hub
/// persistence or navigation semantics.
enum ChatProtocol {
  discourse,
  matrix,
  telegram;

  String get label => switch (this) {
    ChatProtocol.discourse => 'Discourse',
    ChatProtocol.matrix => 'Matrix',
    ChatProtocol.telegram => 'Telegram',
  };

  IconData get icon => switch (this) {
    ChatProtocol.discourse => Icons.forum_rounded,
    ChatProtocol.matrix => Icons.hub_rounded,
    ChatProtocol.telegram => Icons.send_rounded,
  };

  bool get experimental => this != ChatProtocol.discourse;

  String get storageValue => name;
}

const List<ChatProtocol> chatProtocolOrder = <ChatProtocol>[
  ChatProtocol.discourse,
  ChatProtocol.matrix,
  ChatProtocol.telegram,
];

ChatProtocol chatProtocolFromStorage(String? value) {
  if (value == null || value.isEmpty) return ChatProtocol.discourse;
  for (final protocol in ChatProtocol.values) {
    if (protocol.storageValue == value) return protocol;
  }
  return ChatProtocol.discourse;
}
