/// Chat 用户数据模型
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

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'name': name,
        'avatar_template': avatarTemplate,
      };
}