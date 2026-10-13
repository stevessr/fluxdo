import 'package:flutter/material.dart';

import '../../../services/android_optional_plugin_service.dart';

/// Android core only retains the public post/reward entrypoint. No payment
/// credentials or transfer API code are bundled into the host APK.
class RewardTargetInfo {
  const RewardTargetInfo({
    required this.userId,
    required this.username,
    this.name,
    required this.avatarUrl,
    required this.topicId,
    required this.postId,
  });

  final int userId;
  final String username;
  final String? name;
  final String avatarUrl;
  final int topicId;
  final int postId;
}

void showLdcRewardSheet(BuildContext context, RewardTargetInfo target) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('LDC 打赏'),
      content: Text(
        '对 ${target.username} 的打赏操作由独立 LDC 插件提供。'
        '当前插件版本尚未开放打赏交易接口；请在 LDC 官方站点确认。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () async {
            try {
              await AndroidOptionalPluginService.instance.launch('ldc');
              if (context.mounted) Navigator.of(context).pop();
            } catch (error) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(error.toString())),
              );
            }
          },
          child: const Text('打开 LDC 插件'),
        ),
      ],
    ),
  );
}
