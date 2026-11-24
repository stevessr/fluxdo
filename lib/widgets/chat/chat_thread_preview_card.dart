import 'package:material_ui/material_ui.dart';
import 'package:common_ui/common_ui.dart';
import 'package:html/parser.dart' as html;
import 'package:html/dom.dart' as dom;

import '../../models/chat/chat_models.dart';
import '../../utils/time_utils.dart';
import '../common/emoji_text.dart';
import '../common/smart_avatar.dart';

/// Discourse excerpts may contain cooked emoji images rather than shortcodes.
String chatThreadPreviewText(String value) {
  if (!RegExp(r'<(?:/?[a-zA-Z][a-zA-Z0-9]*\b|!--)').hasMatch(value) &&
      !RegExp(r'&(?:#\d+|#x[0-9a-fA-F]+|[a-zA-Z]+);').hasMatch(value)) {
    return value.trim();
  }
  final fragment = html.parseFragment(value);
  for (final image in fragment.querySelectorAll('img')) {
    final alt = (image.attributes['alt']?.isNotEmpty ?? false)
        ? image.attributes['alt']!
        : image.attributes['title'] ?? '';
    final isEmoji = image.classes.contains('emoji') ||
        image.classes.contains('emoji-custom') ||
        (image.attributes['src'] ?? '').contains('/emoji/');
    final text = isEmoji && RegExp(r'^[a-zA-Z0-9_+\-]+(?::t[2-6])?$').hasMatch(alt)
        ? ':$alt:'
        : alt;
    image.replaceWith(dom.Text(text));
  }
  return (fragment.text ?? '').trim();
}

Widget _avatar(ChatUser? user, double radius) => SmartAvatar(
  imageUrl: user?.getAvatarUrl(size: 48),
  radius: radius,
  fallbackText: user?.username,
);

class ChatThreadListItem extends StatelessWidget {
  const ChatThreadListItem({
    super.key,
    required this.thread,
    this.channel,
    required this.onTap,
  });

  final ChatThread thread;
  final ChatChannel? channel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final original = thread.originalMessage;
    final title = thread.title?.trim();
    final excerpt = chatThreadPreviewText(original?.excerpt ?? '');
    final cooked = excerpt.isEmpty
        ? chatThreadPreviewText(original?.cooked ?? '')
        : '';
    final root = title != null && title.isNotEmpty
        ? title
        : excerpt.isNotEmpty
            ? excerpt
            : cooked.isNotEmpty
                ? cooked
                : original?.message.trim() ?? '';
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (channel != null) ...[
              Row(
                children: [
                  if (channel!.emojiShortcode != null)
                    EmojiText(channel!.emojiShortcode!, useRenderStyle: false)
                  else
                    Icon(Icons.tag, size: 17, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                    child: EmojiText(
                      channel!.title ?? '#${channel!.id}',
                      useRenderStyle: false,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
            ],
            EmojiText(
              root.isEmpty ? '消息串 #${thread.id}' : root,
              inline: true,
              useRenderStyle: false,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 10),
            ChatThreadReplyCard(thread: thread),
          ],
        ),
      ),
    );
  }
}

class ChatThreadReplyCard extends StatelessWidget {
  const ChatThreadReplyCard({super.key, required this.thread, this.onTap});
  final ChatThread thread;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = thread.preview;
    final count = preview?.replyCount ?? thread.replyCount;
    final last = preview?.lastReplyUser;
    final user = last ?? thread.originalMessage?.user;
    final name = user?.username;
    final time = thread.lastActivityAt;
    final dateLabel = time == null
        ? null
        : DateUtils.isSameDay(time, DateTime.now())
            ? MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(time))
            : TimeUtils.formatSmartDate(time);
    final excerpt = chatThreadPreviewText(preview?.lastReplyExcerpt ?? '');
    final participants = <int, ChatUser>{};
    for (final participant in [...?preview?.participantUsers, ?last]) {
      if (participant.id > 0) participants[participant.id] = participant;
    }
    final avatars = participants.values.take(3).toList();
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: context.shapes.borderRadius(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: context.shapes.borderRadius(12),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (user != null) ...[
                          _avatar(user, 13),
                          const SizedBox(width: 6),
                        ],
                        if (name != null)
                          Flexible(
                            child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              )),
                          ),
                        if (dateLabel != null) ...[
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(dateLabel,
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              )),
                          ),
                        ],
                      ],
                    ),
                    if (excerpt.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      EmojiText(excerpt, inline: true, useRenderStyle: false,
                        maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (avatars.isNotEmpty) ...[
                    SizedBox(
                      height: 26,
                      width: 26 + (avatars.length - 1) * 17.0,
                      child: Stack(
                        children: [
                          for (var i = 0; i < avatars.length; i++)
                            Positioned(left: i * 17.0, child: _avatar(avatars[i], 13)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 5),
                  ],
                  Text('$count 个回复', style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  )),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
