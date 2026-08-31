import 'package:flutter/material.dart';

/// Chat/私信输入区的键盘视口。
///
/// Scaffold 默认的 resizeToAvoidBottomInset 会让整棵消息树在 IME
/// 上浮/收赵的每一帧都接收到变化中的 MediaQuery。这里改成：
/// 1. 只有底部极小 spacer 逐帧读取 viewInsets；
/// 2. 消息列表与输入组件看到稳定的 viewInsets/padding；
/// 3. 仍通过 Flex 约束逐帧缩放可视区，因此不会遮住最新消息。
class ChatKeyboardViewport extends StatelessWidget {
  const ChatKeyboardViewport({
    super.key,
    required this.children,
  });

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: _StableKeyboardMediaQuery(
            child: Column(children: children),
          ),
        ),
        const _KeyboardInsetSpacer(),
      ],
    );
  }
}

/// 隔离 IME 动画中的 MediaQuery 抖动。
///
/// 本 widget 自己仍会随系统 metrics 每帧重建，但输出给 child 的数据在
/// 键盘可见期间保持不变，所以复杂消息树不会跟着每帧 rebuild。
class _StableKeyboardMediaQuery extends StatelessWidget {
  const _StableKeyboardMediaQuery({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboardVisible = media.viewInsets.bottom > 0;
    final stable = media.copyWith(
      viewInsets: media.viewInsets.copyWith(bottom: 0),
      // 键盘出现后底部 SafeArea 已由 IME 覆盖；只做一次 0/安全区切换，
      // 不让 padding 在动画过程中跟着 viewInsets 逐像素变化。
      padding: media.padding.copyWith(
        bottom: keyboardVisible ? 0 : media.viewPadding.bottom,
      ),
    );
    return MediaQuery(data: stable, child: child);
  }
}

/// 唯一逐帧订阅系统 IME inset 的小组件。
class _KeyboardInsetSpacer extends StatelessWidget {
  const _KeyboardInsetSpacer();

  @override
  Widget build(BuildContext context) {
    return SizedBox(height: MediaQuery.viewInsetsOf(context).bottom);
  }
}
