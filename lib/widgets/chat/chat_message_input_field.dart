import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef ChatInsertedImageCallback =
    void Function(Uint8List bytes, String extension);

/// Android 输入法可向聊天输入框提交的图片类型。
///
/// 必须显式配置这些 MIME；否则 Flutter 会向 Android 声明不接受媒体，
/// 用户从 Gboard 等输入法的剪贴板粘贴图片时系统就会显示「不支持」。
const chatImageInsertionMimeTypes = <String>[
  'image/png',
  'image/bmp',
  'image/jpg',
  'image/tiff',
  'image/gif',
  'image/jpeg',
  'image/webp',
];

/// 将 Android 传入的 MIME 类型转为上传文件扩展名。
String? chatImageExtensionForMimeType(String rawMimeType) {
  final mimeType = rawMimeType.split(';').first.trim().toLowerCase();
  return switch (mimeType) {
    'image/png' => 'png',
    'image/bmp' => 'bmp',
    'image/jpg' || 'image/jpeg' => 'jpg',
    'image/tiff' => 'tif',
    'image/gif' => 'gif',
    'image/webp' => 'webp',
    _ => null,
  };
}

/// Chat 消息输入框。
///
/// 除常规文本输入外，通过 [ContentInsertionConfiguration] 接收 Android
/// 输入法提交的剪贴板图片，再交给宿主走 Chat 附件上传流程。
class ChatMessageInputField extends StatelessWidget {
  const ChatMessageInputField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.hintText,
    required this.onTap,
    required this.onSubmitted,
    required this.onImageInserted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;
  final VoidCallback onTap;
  final ValueChanged<String> onSubmitted;
  final ChatInsertedImageCallback onImageInserted;

  void _handleContentInserted(KeyboardInsertedContent content) {
    final bytes = content.data;
    if (bytes == null || bytes.isEmpty) return;

    final extension = chatImageExtensionForMimeType(content.mimeType);
    if (extension == null) return;
    onImageInserted(bytes, extension);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextField(
      key: const ValueKey('chat-message-input'),
      controller: controller,
      focusNode: focusNode,
      textInputAction: TextInputAction.send,
      maxLines: 5,
      minLines: 1,
      onTap: onTap,
      onSubmitted: onSubmitted,
      contentInsertionConfiguration: ContentInsertionConfiguration(
        allowedMimeTypes: chatImageInsertionMimeTypes,
        onContentInserted: _handleContentInserted,
      ),
      decoration: InputDecoration(
        hintText: hintText,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
        filled: true,
        fillColor: theme.colorScheme.surfaceContainerHighest,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 10,
        ),
        isDense: true,
      ),
    );
  }
}
