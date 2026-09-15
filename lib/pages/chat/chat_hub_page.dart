import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'chat_page.dart';
import 'chat_protocol.dart';
import 'matrix_chat_page.dart';
import 'telegram_chat_page.dart';

/// Experimental multi-protocol chat entry point.
///
/// Existing Discourse chat remains untouched and is simply one child of the
/// hub. Matrix and Telegram can therefore evolve independently or be removed
/// without changing the established Discourse chat implementation.
class ChatHubPage extends StatefulWidget {
  const ChatHubPage({super.key});

  @override
  State<ChatHubPage> createState() => _ChatHubPageState();
}

class _ChatHubPageState extends State<ChatHubPage> {
  static const _selectedProtocolKey = 'experimental_chat_protocol_v1';

  ChatProtocol _selected = ChatProtocol.discourse;
  final Set<ChatProtocol> _activated = <ChatProtocol>{};
  bool _selectionReady = false;
  bool _selectionTouched = false;

  @override
  void initState() {
    super.initState();
    unawaited(_restoreSelection());
  }

  Future<void> _restoreSelection() async {
    ChatProtocol restored = ChatProtocol.discourse;
    try {
      final preferences = await SharedPreferences.getInstance();
      restored = chatProtocolFromStorage(
        preferences.getString(_selectedProtocolKey),
      );
    } catch (_) {
      // Preferences are an optimization. Fall back to Discourse if the
      // platform store is temporarily unavailable.
    }
    if (!mounted) return;
    setState(() {
      if (!_selectionTouched) {
        _selected = restored;
      }
      _activated.add(_selected);
      _selectionReady = true;
    });
  }

  Future<void> _selectProtocol(ChatProtocol protocol) async {
    if (mounted) {
      setState(() {
        _selectionTouched = true;
        _selectionReady = true;
        _selected = protocol;
        _activated.add(protocol);
      });
    }
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        _selectedProtocolKey,
        protocol.storageValue,
      );
    } catch (_) {
      // The visible protocol switch should still succeed if persistence
      // fails; the next launch will simply use the fallback.
    }
  }

  Widget _pageFor(ChatProtocol protocol) {
    if (!_activated.contains(protocol)) {
      if (!_selectionReady && protocol == _selected) {
        return const Center(child: CircularProgressIndicator());
      }
      return const SizedBox.shrink();
    }
    return switch (protocol) {
      ChatProtocol.discourse => const ChatPage(),
      ChatProtocol.matrix => const MatrixChatPage(),
      ChatProtocol.telegram => const TelegramChatPage(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedIndex = chatProtocolOrder.indexOf(_selected);

    return Column(
      children: <Widget>[
        Material(
          color: theme.colorScheme.surface,
          elevation: 1,
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              height: 52,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                itemCount: chatProtocolOrder.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final protocol = chatProtocolOrder[index];
                  return _ProtocolChip(
                    protocol: protocol,
                    selected: _selected == protocol,
                    onSelected: () => unawaited(_selectProtocol(protocol)),
                  );
                },
              ),
            ),
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: selectedIndex < 0 ? 0 : selectedIndex,
            children: chatProtocolOrder
                .map(_pageFor)
                .toList(growable: false),
          ),
        ),
      ],
    );
  }
}

class _ProtocolChip extends StatelessWidget {
  const _ProtocolChip({
    required this.protocol,
    required this.selected,
    required this.onSelected,
  });

  final ChatProtocol protocol;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      selected: selected,
      onSelected: (_) => onSelected(),
      avatar: Icon(protocol.icon, size: 17),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(protocol.label),
          if (protocol.experimental) ...<Widget>[
            const SizedBox(width: 5),
            Text(
              'LAB',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
      visualDensity: VisualDensity.compact,
    );
  }
}
