import 'package:flutter/material.dart';

import 'chat_page.dart';
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
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: <Widget>[
        Material(
          color: theme.colorScheme.surface,
          elevation: 1,
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                children: <Widget>[
                  _ProtocolChip(
                    icon: Icons.forum_rounded,
                    label: 'Discourse',
                    selected: _selected == 0,
                    onSelected: () => setState(() => _selected = 0),
                  ),
                  const SizedBox(width: 8),
                  _ProtocolChip(
                    icon: Icons.hub_rounded,
                    label: 'Matrix',
                    experimental: true,
                    selected: _selected == 1,
                    onSelected: () => setState(() => _selected = 1),
                  ),
                  const SizedBox(width: 8),
                  _ProtocolChip(
                    icon: Icons.send_rounded,
                    label: 'Telegram',
                    experimental: true,
                    selected: _selected == 2,
                    onSelected: () => setState(() => _selected = 2),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _selected,
            children: const <Widget>[
              ChatPage(),
              MatrixChatPage(),
              TelegramChatPage(),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProtocolChip extends StatelessWidget {
  const _ProtocolChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.experimental = false,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool experimental;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      selected: selected,
      onSelected: (_) => onSelected(),
      avatar: Icon(icon, size: 17),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(label),
          if (experimental) ...<Widget>[
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
