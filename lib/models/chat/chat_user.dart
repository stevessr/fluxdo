import 'package:fluxdo/utils/avatar_url.dart';
import '../../utils/url_helper.dart';

/// Chat 消息/频道成员的轻量用户模型
class ChatUser {
  final int id;
  final String username;
  final String? name;
  final String? avatarTemplate;

  const ChatUser({
    required this.id,
    required this.username,
    this.name,
    this.avatarTemplate,
  });

  factory ChatUser.fromJson(Map<String, dynamic> json) {
    return ChatUser(
      id: (json['id'] as num?)?.toInt() ?? 0,
      username: json['username']?.toString() ?? '',
      name: json['name']?.toString(),
      avatarTemplate: json['avatar_template']?.toString(),
    );
  }

  /// 判断是否为系统用户（Discourse 的 system 用户 id=-1, username="system"）。
  /// 群聊标题渲染时应过滤掉系统用户，对齐 Discourse
  /// DirectMessage#chat_channel_title_for_user 中 `.reject { |u| u.is_system_user? }`。
  bool get isSystemUser => id == -1 || username.toLowerCase() == 'system';

  /// 判断是否为已删除用户（id=0 或 username 为空）。
  /// 已删除用户不应显示在成员列表中。
  bool get isDeleted => id <= 0 || username.isEmpty;

  String getAvatarUrl({int size = 96}) {
    if (avatarTemplate == null) return '';
    final template = AvatarUrl.resolve(avatarTemplate!, size: size);
    return UrlHelper.resolveUrlWithCdn(template);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'name': name,
    'avatar_template': avatarTemplate,
  };
}
