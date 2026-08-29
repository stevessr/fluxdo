import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../common/smart_avatar.dart';
import '../../providers/chat_providers.dart';

/// 带在线状态指示的头像组件
///
/// 包裹 SmartAvatar，根据用户 ID 和全局在线状态显示环绕头像的绿色细环。
class OnlineStatusAvatar extends ConsumerWidget {
  final int? userId;
  final String? imageUrl;
  final double radius;
  final String? fallbackText;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final BoxBorder? border;

  const OnlineStatusAvatar({
    super.key,
    this.userId,
    this.imageUrl,
    required this.radius,
    this.fallbackText,
    this.backgroundColor,
    this.foregroundColor,
    this.border,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channelsState = ref.watch(chatChannelsProvider).value;
    final isOnline =
        userId != null &&
        channelsState != null &&
        channelsState.onlineUserIds.contains(userId);
    final ringWidth = (radius * 0.09).clamp(1.5, 2.5).toDouble();
    final isSquare = isSquareAvatarUrl(imageUrl);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        SmartAvatar(
          imageUrl: imageUrl,
          radius: radius,
          fallbackText: fallbackText,
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          border: border,
        ),
        if (isOnline)
          Positioned(
            left: -ringWidth,
            top: -ringWidth,
            right: -ringWidth,
            bottom: -ringWidth,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: isSquare ? BoxShape.rectangle : BoxShape.circle,
                  borderRadius: isSquare
                      ? BorderRadius.circular((radius + ringWidth) * 0.2)
                      : null,
                  border: Border.all(
                    color: const Color(0xFF10B981), // emerald-500
                    width: ringWidth,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
