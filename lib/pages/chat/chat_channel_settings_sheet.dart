import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/s.dart';
import '../../models/chat/chat_models.dart';
import '../../providers/chat_providers.dart';
import 'chat_channel_members_sheet.dart';

/// 聊天频道设置 Sheet 弹窗
class ChatChannelSettingsSheet extends ConsumerWidget {
  final int channelId;
  final String channelTitle;

  const ChatChannelSettingsSheet({
    super.key,
    required this.channelId,
    required this.channelTitle,
  });

  static void show(BuildContext context, int channelId, String channelTitle) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => ChatChannelSettingsSheet(
        channelId: channelId,
        channelTitle: channelTitle,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isFavorite = ref.watch(chatFavoritesProvider).contains(channelId);

    // 从频道列表中获取当前频道的详细 Model 信息
    final channelsAsync = ref.watch(chatChannelsProvider);
    ChatChannel? channel;
    if (channelsAsync.value != null) {
      final all = [
        ...channelsAsync.value!.publicChannels,
        ...channelsAsync.value!.directMessageChannels,
      ];
      try {
        channel = all.firstWhere((c) => c.id == channelId);
      } catch (_) {}
    }

    final canAddMembers = channel?.canAddMembers ?? false;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 顶部抓手
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(top: 4, bottom: 12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // 频道标题与类型图标
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  channel?.chatableType == 'DirectMessage'
                      ? Icons.alternate_email_rounded
                      : Icons.tag_rounded,
                  color: theme.colorScheme.onPrimaryContainer,
                  size: 22,
                ),
              ),
              title: Text(
                channelTitle,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                channel?.description != null && channel!.description!.isNotEmpty
                    ? channel.description!
                    : '频道 ID: $channelId (${channel?.chatableType ?? "Channel"})',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),

            const Divider(height: 1),

            // 1. 收藏频道
            SwitchListTile(
              secondary: Icon(
                isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
                color: isFavorite ? Colors.amber : null,
              ),
              title: const Text('收藏频道'),
              subtitle: const Text('置顶在频道列表收藏区'),
              value: isFavorite,
              onChanged: (_) {
                ref.read(chatFavoritesProvider.notifier).toggleFavorite(channelId);
              },
            ),

            // 2. 查看频道成员
            ListTile(
              leading: const Icon(Icons.group_outlined),
              title: Text(context.l10n.chat_channel_members),
              subtitle: Text(
                channel?.membersCount != null
                    ? '${channel!.membersCount} 位成员'
                    : '查看并管理频道成员',
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {
                Navigator.pop(context);
                ChatChannelMembersSheet.show(
                  context,
                  channelId,
                  channelTitle,
                  canAddMembers: canAddMembers,
                );
              },
            ),

            // 3. 添加成员（仅当有权限时显示）
            if (canAddMembers)
              ListTile(
                leading: Icon(
                  Icons.person_add_outlined,
                  color: theme.colorScheme.primary,
                ),
                title: Text(
                  context.l10n.chat_add_member,
                  style: TextStyle(color: theme.colorScheme.primary),
                ),
                onTap: () {
                  Navigator.pop(context);
                  ChatChannelMembersSheet.show(
                    context,
                    channelId,
                    channelTitle,
                    canAddMembers: true,
                  );
                },
              ),

            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
