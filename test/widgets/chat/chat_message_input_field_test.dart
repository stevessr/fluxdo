import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/widgets/chat/chat_message_input_field.dart';

void main() {
  group('chatImageExtensionForMimeType', () {
    test('支持聊天输入框声明的全部图片类型', () {
      expect(chatImageExtensionForMimeType('image/png'), 'png');
      expect(chatImageExtensionForMimeType('image/bmp'), 'bmp');
      expect(chatImageExtensionForMimeType('image/jpg'), 'jpg');
      expect(chatImageExtensionForMimeType('image/jpeg'), 'jpg');
      expect(chatImageExtensionForMimeType('image/tiff'), 'tif');
      expect(chatImageExtensionForMimeType('image/gif'), 'gif');
      expect(chatImageExtensionForMimeType('image/webp'), 'webp');
    });

    test('规范化大小写和 MIME 参数，并拒绝非图片内容', () {
      expect(
        chatImageExtensionForMimeType(' IMAGE/JPEG; charset=binary '),
        'jpg',
      );
      expect(chatImageExtensionForMimeType('text/plain'), isNull);
    });
  });

  testWidgets('向 Android 声明图片 MIME 并接收输入法提交的图片', (tester) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    Uint8List? insertedBytes;
    String? insertedExtension;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatMessageInputField(
            controller: controller,
            focusNode: focusNode,
            hintText: '输入消息',
            onTap: () {},
            onSubmitted: (_) {},
            onImageInserted: (bytes, extension) {
              insertedBytes = bytes;
              insertedExtension = extension;
            },
          ),
        ),
      ),
    );

    final fieldFinder = find.byKey(const ValueKey('chat-message-input'));
    final textField = tester.widget<TextField>(fieldFinder);
    expect(textField.contentInsertionConfiguration, isNotNull);
    expect(
      textField.contentInsertionConfiguration!.allowedMimeTypes,
      chatImageInsertionMimeTypes,
    );

    await tester.tap(fieldFinder);
    await tester.pump();

    final messageBytes = const JSONMessageCodec().encodeMessage(
      <String, dynamic>{
        'args': <dynamic>[
          -1,
          'TextInputAction.commitContent',
          <String, dynamic>{
            'mimeType': 'image/png',
            'data': <int>[137, 80, 78, 71],
            'uri': 'content://input-method/clipboard.png',
          },
        ],
        'method': 'TextInputClient.performAction',
      },
    );
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/textinput',
      messageBytes,
      (ByteData? _) {},
    );

    expect(insertedBytes, Uint8List.fromList(<int>[137, 80, 78, 71]));
    expect(insertedExtension, 'png');
  });

  testWidgets('忽略空数据和未支持的内容类型', (tester) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    var callbackCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatMessageInputField(
            controller: controller,
            focusNode: focusNode,
            hintText: '输入消息',
            onTap: () {},
            onSubmitted: (_) {},
            onImageInserted: (_, _) => callbackCount++,
          ),
        ),
      ),
    );

    final textField = tester.widget<TextField>(
      find.byKey(const ValueKey('chat-message-input')),
    );
    final handler = textField.contentInsertionConfiguration!.onContentInserted;
    handler(
      const KeyboardInsertedContent(
        mimeType: 'image/png',
        uri: 'content://input-method/empty.png',
      ),
    );
    handler(
      KeyboardInsertedContent(
        mimeType: 'text/plain',
        uri: 'content://input-method/plain.txt',
        data: Uint8List.fromList(<int>[1]),
      ),
    );

    expect(callbackCount, 0);
  });
}
