/// Chat 数据模型
///
/// 集中导出所有 Chat 相关模型，外部只需导入此文件。
library;

import 'chat_channel.dart';

export 'chat_channel.dart';
export 'chat_message.dart';
export 'chat_user.dart';

/// Chat 频道列表状态
class ChatChannelsState {
  /// 公开频道
  final List<ChatChannel> publicChannels;

  /// 私信频道
  final List<ChatChannel> directMessageChannels;

  /// 频道追踪数据（unread_count, unread_mentions 等）
  final Map<String, Map<String, dynamic>> tracking;

  /// MessageBus 最新 ID 映射
  final Map<String, int>? messageBusLastIds;

  const ChatChannelsState({
    required this.publicChannels,
    required this.directMessageChannels,
    required this.tracking,
    this.messageBusLastIds,
  });

  factory ChatChannelsState.fromJson(Map<String, dynamic> json) {
    return ChatChannelsState(
      publicChannels: _parseChannels(json['public_channels']),
      directMessageChannels: _parseChannels(json['direct_message_channels']),
      tracking: _parseTracking(json['tracking']),
      messageBusLastIds: _parseMessageBusIds(json['message_bus_last_ids']),
    );
  }

  static List<ChatChannel> _parseChannels(dynamic channels) {
    if (channels is! List) return [];
    return channels
        .map((e) => ChatChannel.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  static Map<String, Map<String, dynamic>> _parseTracking(dynamic tracking) {
    if (tracking is! Map) return {};
    return (tracking as Map).map(
      (k, v) => MapEntry(
        k.toString(),
        Map<String, dynamic>.from(v as Map),
      ),
    );
  }

  static Map<String, int>? _parseMessageBusIds(dynamic ids) {
    if (ids is! Map) return null;
    return (ids as Map).map(
      (k, v) => MapEntry(k.toString(), (v as num).toInt()),
    );
  }
}

/// Chat 可搜索用户/群组
class Chatable {
  final int id;
  final String username;
  final String? name;
  final String? avatarTemplate;

  const Chatable({
    required this.id,
    required this.username,
    this.name,
    this.avatarTemplate,
  });

  factory Chatable.fromJson(Map<String, dynamic> json) {
    return Chatable(
      id: (json['id'] as num?)?.toInt() ?? 0,
      username: json['username']?.toString() ?? '',
      name: json['name']?.toString(),
      avatarTemplate: json['avatar_template']?.toString(),
    );
  }
}