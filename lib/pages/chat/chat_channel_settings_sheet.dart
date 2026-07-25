import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/s.dart';
import '../../models/chat/chat_models.dart';
import '../../providers/chat_providers.dart';
import '../../providers/core_providers.dart';
import '../../services/preloaded_data_service.dart';
import '../../widgets/common/emoji_text.dart';
import 'chat_channel_members_sheet.dart';

/// 聊天频道设置 Sheet 弹窗
class ChatChannelSettingsSheet extends ConsumerStatefulWidget {
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
  ConsumerState<ChatChannelSettingsSheet> createState() =>
      _ChatChannelSettingsSheetState();
}

class _ChatChannelSettingsSheetState
    extends ConsumerState<ChatChannelSettingsSheet> {
  bool _isSaving = false;

  Future<void> _updateMute(ChatChannel channel, bool newMuted) async {
    setState(() => _isSaving = true);
    try {
      final service = ref.read(discourseServiceProvider);
      await service.updateChannelSettings(widget.channelId, muted: newMuted);
      ref.invalidate(chatChannelsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(newMuted ? '已开启免打扰' : '已关闭免打扰')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('设置失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// 通知级别：never / mention / always（对齐 Discourse membership.notification_level）
  Future<void> _updateNotificationLevel(
    ChatChannel channel,
    String level,
  ) async {
    setState(() => _isSaving = true);
    try {
      final service = ref.read(discourseServiceProvider);
      await service.updateChannelNotificationsSettings(
        widget.channelId,
        notificationLevel: level,
      );
      ref.invalidate(chatChannelsProvider);
      if (mounted) {
        final label = switch (level) {
          'never' => '从不',
          'always' => '全部消息',
          _ => '仅提及',
        };
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('通知级别已设为「$label」')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('设置失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showNotificationLevelPicker(ChatChannel channel) {
    final current = channel.notificationLevel ?? 'mention';
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                title: Text(
                  '通知级别',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              RadioListTile<String>(
                value: 'never',
                groupValue: current,
                title: const Text('从不'),
                subtitle: const Text('不接收该频道推送'),
                onChanged: (v) {
                  Navigator.pop(ctx);
                  if (v != null) _updateNotificationLevel(channel, v);
                },
              ),
              RadioListTile<String>(
                value: 'mention',
                groupValue: current,
                title: const Text('仅提及'),
                subtitle: const Text('仅在被 @ 时通知'),
                onChanged: (v) {
                  Navigator.pop(ctx);
                  if (v != null) _updateNotificationLevel(channel, v);
                },
              ),
              RadioListTile<String>(
                value: 'always',
                groupValue: current,
                title: const Text('全部消息'),
                subtitle: const Text('该频道每条新消息都通知'),
                onChanged: (v) {
                  Navigator.pop(ctx);
                  if (v != null) _updateNotificationLevel(channel, v);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _updateThreading(ChatChannel channel, bool newThreading) async {
    setState(() => _isSaving = true);
    try {
      final service = ref.read(discourseServiceProvider);
      await service.updateChannelSettings(
        widget.channelId,
        threadingEnabled: newThreading,
      );
      ref.invalidate(chatChannelsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(newThreading ? '已开启消息串' : '已关闭消息串')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('设置失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showEditChannelDialog(ChatChannel? channel) {
    final titleController =
        TextEditingController(text: channel?.title ?? widget.channelTitle);
    final slugController = TextEditingController(text: channel?.slug ?? '');
    final emojiController = TextEditingController(text: channel?.emoji ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑频道信息'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(
                  labelText: '频道名称',
                  hintText: '请输入频道名称',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: slugController,
                decoration: const InputDecoration(
                  labelText: '频道缩略名 (Slug)',
                  hintText: '例如: general',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emojiController,
                decoration: const InputDecoration(
                  labelText: '频道表情符号',
                  hintText: '例如: :speech_balloon: 或 😀',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() => _isSaving = true);
              try {
                final service = ref.read(discourseServiceProvider);
                await service.updateChannelSettings(
                  widget.channelId,
                  name: titleController.text.trim(),
                  slug: slugController.text.trim(),
                  emoji: emojiController.text.trim(),
                );
                ref.invalidate(chatChannelsProvider);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('频道信息已成功更新')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('更新失败: $e')),
                  );
                }
              } finally {
                if (mounted) setState(() => _isSaving = false);
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isFavorite =
        ref.watch(chatFavoritesProvider).contains(widget.channelId);

    // 从频道列表中获取当前频道的详细 Model 信息
    final channelsAsync = ref.watch(chatChannelsProvider);
    ChatChannel? channel;
    if (channelsAsync.value != null) {
      final all = [
        ...channelsAsync.value!.publicChannels,
        ...channelsAsync.value!.directMessageChannels,
      ];
      try {
        channel = all.firstWhere((c) => c.id == widget.channelId);
      } catch (_) {}
    }

    final canAddMembers = channel?.canAddMembers ?? false;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: SingleChildScrollView(
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
                    color: theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // 频道标题与类型图标/表情
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: channel?.emoji != null && channel!.emoji!.isNotEmpty
                      ? EmojiText(
                          channel.emoji!.startsWith(':')
                              ? channel.emoji!
                              : ':${channel.emoji}:',
                          style: const TextStyle(fontSize: 20),
                        )
                      : Icon(
                          channel?.chatableType == 'DirectMessage'
                              ? Icons.alternate_email_rounded
                              : Icons.tag_rounded,
                          color: theme.colorScheme.onPrimaryContainer,
                          size: 22,
                        ),
                ),
                title: Text(
                  channel?.title ?? widget.channelTitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Text(
                  channel?.description != null &&
                          channel!.description!.isNotEmpty
                      ? channel.description!
                      : '频道 ID: ${widget.channelId} (${channel?.chatableType ?? "Channel"})',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: '编辑频道信息',
                  onPressed: _isSaving
                      ? null
                      : () => _showEditChannelDialog(channel),
                ),
              ),

              const Divider(height: 1),

              // 1. 收藏频道 (云端同步)
              SwitchListTile(
                secondary: Icon(
                  isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: isFavorite ? Colors.amber : null,
                ),
                title: const Text('收藏频道'),
                subtitle: const Text('与云端收藏实时同步，置顶在频道列表'),
                value: isFavorite,
                onChanged: _isSaving
                    ? null
                    : (_) {
                        ref
                            .read(chatFavoritesProvider.notifier)
                            .toggleFavorite(widget.channelId);
                      },
              ),

              // 2. 免打扰设置 (Mute)
              SwitchListTile(
                secondary: Icon(
                  channel?.muted == true
                      ? Icons.notifications_off_rounded
                      : Icons.notifications_none_rounded,
                  color:
                      channel?.muted == true ? theme.colorScheme.error : null,
                ),
                title: const Text('免打扰'),
                subtitle: const Text('开启后静音该频道的提醒推送'),
                value: channel?.muted ?? false,
                onChanged: _isSaving || channel == null
                    ? null
                    : (val) => _updateMute(channel!, val),
              ),

              // 2.1 通知级别
              ListTile(
                leading: const Icon(Icons.notifications_active_outlined),
                title: const Text('通知级别'),
                subtitle: Text(
                  switch (channel?.notificationLevel) {
                    'never' => '从不',
                    'always' => '全部消息',
                    'mention' => '仅提及',
                    _ => '仅提及（默认）',
                  },
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _isSaving || channel == null
                    ? null
                    : () => _showNotificationLevelPicker(channel!),
              ),

              // 3. 消息串 (Threading) 开关
              SwitchListTile(
                secondary: Icon(
                  Icons.forum_outlined,
                  color: channel?.threadingEnabled == true
                      ? theme.colorScheme.primary
                      : null,
                ),
                title: const Text('消息串 (Thread)'),
                subtitle: const Text('允许针对单条消息开启独立讨论子串'),
                value: channel?.threadingEnabled ?? false,
                onChanged: _isSaving || channel == null
                    ? null
                    : (val) => _updateThreading(channel!, val),
              ),

              const Divider(height: 1),

              // 4. 历史记录保留时长（来自站点设置，非频道字段）
              Builder(
                builder: (context) {
                  final settings =
                      PreloadedDataService().siteSettingsSync ?? const {};
                  final channelDays =
                      (settings['chat_channel_retention_days'] as num?)
                          ?.toInt();
                  final dmDays =
                      (settings['chat_dm_retention_days'] as num?)?.toInt();
                  final text = channel?.retentionDisplay(
                        channelRetentionDays: channelDays,
                        dmRetentionDays: dmDays,
                      ) ??
                      '永久保留';
                  return ListTile(
                    leading: const Icon(Icons.history_toggle_off_rounded),
                    title: const Text('历史消息保留时长'),
                    subtitle: const Text('由站点设置控制，超过周期的历史消息将被清理'),
                    trailing: Text(
                      text,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  );
                },
              ),

              // 5. 编辑频道名称 / 缩略名 / 表情
              ListTile(
                leading: const Icon(Icons.tune_rounded),
                title: const Text('编辑频道属性'),
                subtitle: const Text('修改频道名称、缩略名及自定义图标'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap:
                    _isSaving ? null : () => _showEditChannelDialog(channel),
              ),

              // 6. 查看/管理成员
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
                    widget.channelId,
                    widget.channelTitle,
                    canAddMembers: canAddMembers,
                  );
                },
              ),

              // 7. 添加成员（权限受控）
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
                      widget.channelId,
                      widget.channelTitle,
                      canAddMembers: true,
                    );
                  },
                ),

              if (_isSaving)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Center(child: CircularProgressIndicator()),
                ),

              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
