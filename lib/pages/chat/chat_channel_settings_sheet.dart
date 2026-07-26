import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/s.dart';
import '../../models/chat/chat_models.dart';
import '../../models/emoji.dart';
import '../../models/user.dart';
import '../../providers/chat_providers.dart';
import '../../providers/core_providers.dart';
import '../../services/preloaded_data_service.dart';
import '../../widgets/common/emoji_text.dart';
import '../../widgets/markdown_editor/emoji_sticker_panel.dart';
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
  /// 本地乐观覆盖的通知级别（避免 invalidate 前 UI 不刷新）
  String? _localNotificationLevel;
  bool? _localMuted;

  Future<void> _updateMute(ChatChannel channel, bool newMuted) async {
    setState(() {
      _isSaving = true;
      _localMuted = newMuted;
    });
    try {
      final service = ref.read(discourseServiceProvider);
      await service.updateChannelNotificationsSettings(
        widget.channelId,
        muted: newMuted,
      );
      ref.invalidate(chatChannelsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(newMuted ? '已开启免打扰' : '已关闭免打扰')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _localMuted = channel.muted);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('设置失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// 通知级别：never / mention / always
  Future<void> _updateNotificationLevel(
    ChatChannel channel,
    String level,
  ) async {
    setState(() {
      _isSaving = true;
      _localNotificationLevel = level;
    });
    try {
      final service = ref.read(discourseServiceProvider);
      final membership = await service.updateChannelNotificationsSettings(
        widget.channelId,
        notificationLevel: level,
      );
      // 若服务端回写了 membership，再对齐一次本地值
      if (membership != null) {
        final serverLevel = membership['notification_level'];
        if (serverLevel is String) {
          _localNotificationLevel = serverLevel;
        } else if (serverLevel is num) {
          _localNotificationLevel = switch (serverLevel.toInt()) {
            0 => 'never',
            1 => 'mention',
            2 => 'always',
            _ => level,
          };
        }
      }
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
        setState(() => _localNotificationLevel = channel.notificationLevel);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('设置失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showNotificationLevelPicker(ChatChannel channel) {
    final current =
        _localNotificationLevel ?? channel.notificationLevel ?? 'mention';
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
              for (final entry in const [
                ('never', '从不', '不接收该频道推送'),
                ('mention', '仅提及', '仅在被 @ 时通知'),
                ('always', '全部消息', '该频道每条新消息都通知'),
              ])
                ListTile(
                  leading: Icon(
                    current == entry.$1
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: current == entry.$1
                        ? Theme.of(ctx).colorScheme.primary
                        : null,
                  ),
                  title: Text(entry.$2),
                  subtitle: Text(entry.$3),
                  onTap: () {
                    Navigator.pop(ctx);
                    _updateNotificationLevel(channel, entry.$1);
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
      await service.updateChannel(
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
    var selectedEmoji = ChatChannel.normalizeEmojiShortcode(channel?.emoji);

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            void openEmojiPicker() {
              showModalBottomSheet<void>(
                context: ctx,
                isScrollControlled: true,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                builder: (sheetCtx) => SizedBox(
                  height: MediaQuery.of(sheetCtx).size.height * 0.45,
                  child: EmojiStickerPanel(
                    onEmojiSelected: (Emoji emoji) {
                      Navigator.pop(sheetCtx);
                      setDialogState(() {
                        selectedEmoji =
                            ChatChannel.normalizeEmojiShortcode(emoji.name);
                      });
                    },
                    onStickerSelected: (_) {},
                    onBackspace: null,
                  ),
                ),
              );
            }

            final previewCode = ChatChannel.toEmojiTextCode(selectedEmoji);

            return AlertDialog(
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
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '频道表情图标',
                        style: Theme.of(ctx).textTheme.labelLarge,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Material(
                          color: Theme.of(ctx).colorScheme.primaryContainer,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: openEmojiPicker,
                            child: SizedBox(
                              width: 56,
                              height: 56,
                              child: Center(
                                child: previewCode != null
                                    ? EmojiText(
                                        previewCode,
                                        style: const TextStyle(fontSize: 26),
                                      )
                                    : Icon(
                                        Icons.add_reaction_outlined,
                                        color: Theme.of(ctx)
                                            .colorScheme
                                            .onPrimaryContainer,
                                      ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        if (selectedEmoji != null)
                          IconButton(
                            tooltip: '清除表情',
                            onPressed: () {
                              setDialogState(() => selectedEmoji = null);
                            },
                            icon: Icon(
                              Icons.close_rounded,
                              color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        const Spacer(),
                        IconButton.filledTonal(
                          tooltip: selectedEmoji == null ? '选择表情' : '更换表情',
                          onPressed: openEmojiPicker,
                          icon: const Icon(Icons.emoji_emotions_outlined),
                        ),
                      ],
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
                      final emojiToSave = selectedEmoji ?? '';
                      await service.updateChannel(
                        widget.channelId,
                        name: titleController.text.trim(),
                        slug: slugController.text.trim(),
                        emoji: emojiToSave,
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
            );
          },
        );
      },
    );
  }

  String _channelTypeLabel(ChatChannel? channel) {
    if (channel == null) return '未知';
    if (channel.isDirectMessage) {
      return channel.isGroupDm ? '群组私信' : '私信';
    }
    if (channel.isCategoryChannel) return '公开频道';
    return channel.chatableType ?? '频道';
  }

  String _statusLabel(ChatChannel? channel) {
    if (channel == null) return '';
    if (channel.isArchived) return '已归档';
    if (channel.isClosed) return '已关闭';
    if (channel.isReadOnly) return '只读';
    return '开放';
  }

  /// 群组私信人数上限（站点设置 chat_max_direct_message_users）
  int? _dmMemberLimit() {
    final settings = PreloadedDataService().siteSettingsSync;
    final raw = settings?['chat_max_direct_message_users'];
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isFavorite =
        ref.watch(chatFavoritesProvider).contains(widget.channelId);
    final currentUser = ref.watch(currentUserProvider).value;
    final isStaff = currentUser is User ? currentUser.isStaff : false;

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
    final canEdit = channel?.canEditChannel(isStaff: isStaff) ?? isStaff;
    final mutedValue = _localMuted ?? channel?.muted ?? false;
    final notifLevel =
        _localNotificationLevel ?? channel?.notificationLevel ?? 'mention';
    final dmLimit = channel?.isDirectMessage == true ? _dmMemberLimit() : null;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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

              // 频道标题与类型图标/表情（无权限时不显示编辑按钮）
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: () {
                    final code = channel?.emojiShortcode;
                    if (code != null && code.isNotEmpty) {
                      return EmojiText(
                        code,
                        style: const TextStyle(fontSize: 20),
                      );
                    }
                    return Icon(
                      channel?.isDirectMessage == true
                          ? Icons.alternate_email_rounded
                          : Icons.tag_rounded,
                      color: theme.colorScheme.onPrimaryContainer,
                      size: 22,
                    );
                  }(),
                ),
                title: Text(
                  channel?.title ?? widget.channelTitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Text(
                  [
                    if (channel?.description != null &&
                        channel!.description!.isNotEmpty)
                      channel.description!
                    else
                      null,
                    '类型: ${_channelTypeLabel(channel)}',
                    if (_statusLabel(channel).isNotEmpty)
                      '状态: ${_statusLabel(channel)}',
                    'ID: ${widget.channelId}',
                  ].whereType<String>().join(' · '),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                trailing: canEdit
                    ? IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: '编辑频道信息',
                        onPressed: _isSaving
                            ? null
                            : () => _showEditChannelDialog(channel),
                      )
                    : null,
              ),

              const Divider(height: 1),

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

              SwitchListTile(
                secondary: Icon(
                  mutedValue
                      ? Icons.notifications_off_rounded
                      : Icons.notifications_none_rounded,
                  color: mutedValue ? theme.colorScheme.error : null,
                ),
                title: const Text('免打扰'),
                subtitle: const Text('开启后静音该频道的提醒推送'),
                value: mutedValue,
                onChanged: _isSaving || channel == null
                    ? null
                    : (val) => _updateMute(channel!, val),
              ),

              ListTile(
                leading: const Icon(Icons.notifications_active_outlined),
                title: const Text('通知级别'),
                subtitle: Text(
                  switch (notifLevel) {
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

              // 消息串仅对有编辑权限的用户可改；无权限只展示状态
              if (canEdit)
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
                )
              else
                ListTile(
                  leading: const Icon(Icons.forum_outlined),
                  title: const Text('消息串 (Thread)'),
                  trailing: Text(
                    (channel?.threadingEnabled ?? false) ? '已开启' : '已关闭',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),

              const Divider(height: 1),

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

              // 仅有编辑权限时显示「编辑频道属性」入口
              if (canEdit)
                ListTile(
                  leading: const Icon(Icons.tune_rounded),
                  title: const Text('编辑频道属性'),
                  subtitle: const Text('修改频道名称、缩略名及自定义图标'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap:
                      _isSaving ? null : () => _showEditChannelDialog(channel),
                )
              else
                ListTile(
                  leading: const Icon(Icons.info_outline_rounded),
                  title: const Text('频道信息'),
                  subtitle: Text(
                    [
                      '类型: ${_channelTypeLabel(channel)}',
                      '状态: ${_statusLabel(channel)}',
                      if (channel?.slug != null && channel!.slug!.isNotEmpty)
                        '缩略名: ${channel.slug}',
                    ].join(' · '),
                  ),
                ),

              ListTile(
                leading: const Icon(Icons.group_outlined),
                title: Text(context.l10n.chat_channel_members),
                subtitle: Text(
                  () {
                    final count = channel?.membersCount;
                    final limit = dmLimit;
                    if (count != null && limit != null && limit > 0) {
                      return '$count / $limit 位成员（上限 $limit）';
                    }
                    if (count != null) return '$count 位成员';
                    if (limit != null && limit > 0) {
                      return '人数上限 $limit';
                    }
                    return '查看并管理频道成员';
                  }(),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  Navigator.pop(context);
                  ChatChannelMembersSheet.show(
                    context,
                    widget.channelId,
                    widget.channelTitle,
                    canAddMembers: canAddMembers,
                    membersCountHint: channel?.membersCount,
                    membersLimit: dmLimit,
                  );
                },
              ),

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
                  subtitle: dmLimit != null && dmLimit > 0
                      ? Text('群组私信最多 $dmLimit 人')
                      : null,
                  onTap: () {
                    Navigator.pop(context);
                    ChatChannelMembersSheet.show(
                      context,
                      widget.channelId,
                      widget.channelTitle,
                      canAddMembers: true,
                      membersCountHint: channel?.membersCount,
                      membersLimit: dmLimit,
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
