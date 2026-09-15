from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text()
    if old not in text:
        raise SystemExit(f'anchor not found in {path}: {old[:120]!r}')
    file.write_text(text.replace(old, new, 1))


# 1. Matrix event content builder for m.replace.
replace_once(
    'lib/services/messaging/matrix_message_content.dart',
    '''  return content;\n}\n\n/// Builds an unencrypted Matrix attachment event.\n''',
    '''  return content;\n}\n\n/// Builds the content object for an unencrypted Matrix text edit.\n///\n/// Matrix edits are replacement relations. The top-level body is a legacy\n/// fallback for clients without edit support, while `m.new_content` contains\n/// the canonical replacement body.\nMap<String, dynamic> buildMatrixTextReplacementContent(\n  String body, {\n  required String targetEventId,\n}) {\n  final replacement = body.trim();\n  final target = targetEventId.trim();\n  if (replacement.isEmpty) {\n    throw ArgumentError.value(body, 'body', 'Replacement body cannot be empty');\n  }\n  if (target.isEmpty) {\n    throw ArgumentError.value(\n      targetEventId,\n      'targetEventId',\n      'Replacement target event id cannot be empty',\n    );\n  }\n  return <String, dynamic>{\n    'msgtype': 'm.text',\n    'body': '* $replacement',\n    'm.new_content': <String, dynamic>{\n      'msgtype': 'm.text',\n      'body': replacement,\n    },\n    'm.relates_to': <String, dynamic>{\n      'rel_type': 'm.replace',\n      'event_id': target,\n    },\n  };\n}\n\n/// Builds an unencrypted Matrix attachment event.\n''',
)

# 2. Protocol-neutral optional mutation capability.
replace_once(
    'lib/services/messaging/messaging_provider.dart',
    '''    this.reactions = false,\n    this.edits = false,\n    this.threads = false,\n''',
    '''    this.reactions = false,\n    this.edits = false,\n    this.redactions = false,\n    this.threads = false,\n''',
)
replace_once(
    'lib/services/messaging/messaging_provider.dart',
    '''  final bool reactions;\n  final bool edits;\n  final bool threads;\n''',
    '''  final bool reactions;\n  final bool edits;\n  final bool redactions;\n  final bool threads;\n''',
)
replace_once(
    'lib/services/messaging/messaging_provider.dart',
    '''  Future<void> sendReaction(\n    String conversationId,\n    String messageId,\n    String reaction,\n  );\n}\n''',
    '''  Future<void> sendReaction(\n    String conversationId,\n    String messageId,\n    String reaction,\n  );\n}\n\n/// Optional mutation surface for providers which can modify already-sent\n/// messages. Keeping this separate avoids forcing protocols without equivalent\n/// semantics to advertise fake implementations.\nabstract interface class MessagingMutationProvider {\n  Future<void> editText(\n    String conversationId,\n    String messageId,\n    String body,\n  );\n\n  Future<void> redactMessage(\n    String conversationId,\n    String messageId, {\n    String? reason,\n  });\n}\n''',
)

# 3. Matrix client send-side mutation APIs.
replace_once(
    'lib/services/matrix_client_service.dart',
    '''  Future<void> sendReaction(\n    String roomId,\n    String eventId,\n    String key,\n  ) async {\n''',
    '''  Future<void> editText(\n    String roomId,\n    String eventId,\n    String body,\n  ) async {\n    final current = _requireSession();\n    final targetEventId = eventId.trim();\n    final replacement = body.trim();\n    if (targetEventId.isEmpty) {\n      throw const MatrixClientException('Edit target event id is required.');\n    }\n    if (replacement.isEmpty) return;\n\n    final encodedRoomId = Uri.encodeComponent(roomId);\n    final transactionId = _newTransactionId();\n    try {\n      await _dio.put<void>(\n        '${current.homeserver}/_matrix/client/v3/rooms/'\n        '$encodedRoomId/send/m.room.message/$transactionId',\n        data: buildMatrixTextReplacementContent(\n          replacement,\n          targetEventId: targetEventId,\n        ),\n        options: _authorizedOptions(current),\n      );\n    } on DioException catch (error) {\n      throw MatrixClientException(_matrixErrorMessage(error));\n    }\n  }\n\n  Future<void> redactEvent(\n    String roomId,\n    String eventId, {\n    String? reason,\n  }) async {\n    final current = _requireSession();\n    final targetEventId = eventId.trim();\n    if (targetEventId.isEmpty) {\n      throw const MatrixClientException('Redaction target event id is required.');\n    }\n\n    final encodedRoomId = Uri.encodeComponent(roomId);\n    final encodedEventId = Uri.encodeComponent(targetEventId);\n    final transactionId = _newTransactionId();\n    final normalizedReason = reason?.trim();\n    try {\n      await _dio.put<void>(\n        '${current.homeserver}/_matrix/client/v3/rooms/'\n        '$encodedRoomId/redact/$encodedEventId/$transactionId',\n        data: <String, dynamic>{\n          if (normalizedReason != null && normalizedReason.isNotEmpty)\n            'reason': normalizedReason,\n        },\n        options: _authorizedOptions(current),\n      );\n    } on DioException catch (error) {\n      throw MatrixClientException(_matrixErrorMessage(error));\n    }\n  }\n\n  Future<void> sendReaction(\n    String roomId,\n    String eventId,\n    String key,\n  ) async {\n''',
)

# 4. Expose mutation capability through the protocol-neutral Matrix adapter.
replace_once(
    'lib/services/messaging/matrix_messaging_provider.dart',
    'class MatrixMessagingProvider implements MessagingProvider {\n',
    'class MatrixMessagingProvider implements MessagingProvider, MessagingMutationProvider {\n',
)
replace_once(
    'lib/services/messaging/matrix_messaging_provider.dart',
    '''    reactions: true,\n    // The REST reducer can render remote m.replace events, but the common\n    // provider does not expose an edit-send operation yet. Keep this false so\n    // shared UI does not advertise an unsupported action.\n    edits: false,\n    threads: false,\n''',
    '''    reactions: true,\n    edits: true,\n    redactions: true,\n    threads: false,\n''',
)
replace_once(
    'lib/services/messaging/matrix_messaging_provider.dart',
    '''  Future<void> sendReaction(\n    String conversationId,\n    String messageId,\n    String reaction,\n  ) => client.sendReaction(conversationId, messageId, reaction);\n}\n''',
    '''  Future<void> sendReaction(\n    String conversationId,\n    String messageId,\n    String reaction,\n  ) => client.sendReaction(conversationId, messageId, reaction);\n\n  @override\n  Future<void> editText(\n    String conversationId,\n    String messageId,\n    String body,\n  ) => client.editText(conversationId, messageId, body);\n\n  @override\n  Future<void> redactMessage(\n    String conversationId,\n    String messageId, {\n    String? reason,\n  }) => client.redactEvent(conversationId, messageId, reason: reason);\n}\n''',
)

# 5. Room message actions: own plaintext text can edit; all own events can redact.
replace_once(
    'lib/pages/chat/matrix_room_page.dart',
    'enum _MessageAction { reply, thread, reaction }\n',
    'enum _MessageAction { reply, thread, reaction, edit, redact }\n',
)
replace_once(
    'lib/pages/chat/matrix_room_page.dart',
    '''  Future<void> _showMessageActions(MatrixMessage message) async {\n''',
    '''  bool _canEditMessage(MatrixMessage message) {\n    final currentUserId = widget.client.session?.userId;\n    return !widget.room.encrypted &&\n        !message.encrypted &&\n        !message.redacted &&\n        currentUserId != null &&\n        message.sender == currentUserId &&\n        message.msgType == 'm.text' &&\n        !message.hasMedia;\n  }\n\n  bool _canRedactMessage(MatrixMessage message) {\n    final currentUserId = widget.client.session?.userId;\n    return !widget.room.encrypted &&\n        !message.encrypted &&\n        !message.redacted &&\n        currentUserId != null &&\n        message.sender == currentUserId;\n  }\n\n  Future<void> _editMessage(MatrixMessage message) async {\n    if (!_canEditMessage(message)) return;\n    final controller = TextEditingController(text: message.body);\n    try {\n      final replacement = await showDialog<String>(\n        context: context,\n        builder: (context) => AlertDialog(\n          title: const Text('编辑消息'),\n          content: TextField(\n            controller: controller,\n            autofocus: true,\n            minLines: 1,\n            maxLines: 8,\n            decoration: const InputDecoration(\n              hintText: '新的消息内容',\n              border: OutlineInputBorder(),\n            ),\n          ),\n          actions: <Widget>[\n            TextButton(\n              onPressed: () => Navigator.of(context).pop(),\n              child: const Text('取消'),\n            ),\n            FilledButton(\n              onPressed: () => Navigator.of(context).pop(controller.text.trim()),\n              child: const Text('保存'),\n            ),\n          ],\n        ),\n      );\n      if (!mounted || replacement == null || replacement.isEmpty) return;\n      if (replacement == message.body.trim()) return;\n      await widget.client.editText(\n        widget.room.roomId,\n        message.eventId,\n        replacement,\n      );\n      await _loadLatest(\n        showSpinner: false,\n        scrollToBottom: false,\n        preservePaginationCursor: true,\n      );\n    } catch (error) {\n      if (mounted) setState(() => _error = error.toString());\n    } finally {\n      controller.dispose();\n    }\n  }\n\n  Future<void> _redactMessage(MatrixMessage message) async {\n    if (!_canRedactMessage(message)) return;\n    final confirmed = await showDialog<bool>(\n      context: context,\n      builder: (context) => AlertDialog(\n        title: const Text('撤回消息？'),\n        content: Text(\n          '这会通过 Matrix redaction 撤回该事件，且无法恢复。\\n\\n${message.body}',\n          maxLines: 6,\n          overflow: TextOverflow.ellipsis,\n        ),\n        actions: <Widget>[\n          TextButton(\n            onPressed: () => Navigator.of(context).pop(false),\n            child: const Text('取消'),\n          ),\n          FilledButton(\n            onPressed: () => Navigator.of(context).pop(true),\n            child: const Text('确认撤回'),\n          ),\n        ],\n      ),\n    );\n    if (!mounted || confirmed != true) return;\n    try {\n      await widget.client.redactEvent(widget.room.roomId, message.eventId);\n      await _loadLatest(\n        showSpinner: false,\n        scrollToBottom: false,\n        preservePaginationCursor: true,\n      );\n    } catch (error) {\n      if (mounted) setState(() => _error = error.toString());\n    }\n  }\n\n  Future<void> _showMessageActions(MatrixMessage message) async {\n''',
)
replace_once(
    'lib/pages/chat/matrix_room_page.dart',
    '''    if (widget.room.encrypted || message.encrypted || message.redacted) return;\n    final action = await showModalBottomSheet<_MessageAction>(\n''',
    '''    if (widget.room.encrypted || message.encrypted || message.redacted) return;\n    final canEdit = _canEditMessage(message);\n    final canRedact = _canRedactMessage(message);\n    final action = await showModalBottomSheet<_MessageAction>(\n''',
)
replace_once(
    'lib/pages/chat/matrix_room_page.dart',
    '''            ListTile(\n              leading: const Icon(Icons.add_reaction_outlined),\n              title: const Text('Reaction'),\n              onTap: () => Navigator.of(context).pop(_MessageAction.reaction),\n            ),\n''',
    '''            ListTile(\n              leading: const Icon(Icons.add_reaction_outlined),\n              title: const Text('Reaction'),\n              onTap: () => Navigator.of(context).pop(_MessageAction.reaction),\n            ),\n            if (canEdit)\n              ListTile(\n                leading: const Icon(Icons.edit_outlined),\n                title: const Text('编辑消息'),\n                subtitle: const Text('发送标准 m.replace 关系事件'),\n                onTap: () => Navigator.of(context).pop(_MessageAction.edit),\n              ),\n            if (canRedact)\n              ListTile(\n                leading: const Icon(Icons.delete_outline_rounded),\n                title: const Text('撤回消息'),\n                subtitle: const Text('发送 Matrix redaction；无法恢复'),\n                onTap: () => Navigator.of(context).pop(_MessageAction.redact),\n              ),\n''',
)
replace_once(
    'lib/pages/chat/matrix_room_page.dart',
    '''      case _MessageAction.reaction:\n        await _showReactionPicker(message);\n    }\n''',
    '''      case _MessageAction.reaction:\n        await _showReactionPicker(message);\n      case _MessageAction.edit:\n        await _editMessage(message);\n      case _MessageAction.redact:\n        await _redactMessage(message);\n    }\n''',
)
replace_once(
    'lib/pages/chat/matrix_room_page.dart',
    '''                        '此房间启用了 E2EE；轻量 REST provider 尚未解密。为避免泄漏明文，发送、回复、thread、reaction 与 typing 已禁用。',\n''',
    '''                        '此房间启用了 E2EE；轻量 REST provider 尚未解密。为避免泄漏明文，发送、回复、thread、reaction、编辑/撤回与 typing 已禁用。',\n''',
)

# 6. Thread actions: reaction for every visible plaintext event; edit/redact only own replies.
replace_once(
    'lib/pages/chat/matrix_thread_page.dart',
    '''class MatrixThreadPage extends StatefulWidget {\n''',
    '''enum _ThreadMessageAction { reaction, edit, redact }\n\nclass MatrixThreadPage extends StatefulWidget {\n''',
)
replace_once(
    'lib/pages/chat/matrix_thread_page.dart',
    '''  Future<void> _showReactionPicker(MatrixMessage message) async {\n''',
    '''  bool _canEditMessage(MatrixMessage message) {\n    final currentUserId = widget.client.session?.userId;\n    return !widget.room.encrypted &&\n        !message.encrypted &&\n        !message.redacted &&\n        currentUserId != null &&\n        message.sender == currentUserId &&\n        message.msgType == 'm.text' &&\n        !message.hasMedia;\n  }\n\n  bool _canRedactMessage(MatrixMessage message) {\n    final currentUserId = widget.client.session?.userId;\n    return !widget.room.encrypted &&\n        !message.encrypted &&\n        !message.redacted &&\n        currentUserId != null &&\n        message.sender == currentUserId;\n  }\n\n  Future<void> _showMessageActions(\n    MatrixMessage message, {\n    required bool allowMutation,\n  }) async {\n    if (widget.room.encrypted || message.encrypted || message.redacted) return;\n    final canEdit = allowMutation && _canEditMessage(message);\n    final canRedact = allowMutation && _canRedactMessage(message);\n    final action = await showModalBottomSheet<_ThreadMessageAction>(\n      context: context,\n      showDragHandle: true,\n      builder: (context) => SafeArea(\n        child: Column(\n          mainAxisSize: MainAxisSize.min,\n          children: <Widget>[\n            ListTile(\n              leading: const Icon(Icons.add_reaction_outlined),\n              title: const Text('Reaction'),\n              onTap: () => Navigator.of(context).pop(_ThreadMessageAction.reaction),\n            ),\n            if (canEdit)\n              ListTile(\n                leading: const Icon(Icons.edit_outlined),\n                title: const Text('编辑消息'),\n                onTap: () => Navigator.of(context).pop(_ThreadMessageAction.edit),\n              ),\n            if (canRedact)\n              ListTile(\n                leading: const Icon(Icons.delete_outline_rounded),\n                title: const Text('撤回消息'),\n                onTap: () => Navigator.of(context).pop(_ThreadMessageAction.redact),\n              ),\n          ],\n        ),\n      ),\n    );\n    if (!mounted || action == null) return;\n    switch (action) {\n      case _ThreadMessageAction.reaction:\n        await _showReactionPicker(message);\n      case _ThreadMessageAction.edit:\n        await _editMessage(message);\n      case _ThreadMessageAction.redact:\n        await _redactMessage(message);\n    }\n  }\n\n  Future<void> _editMessage(MatrixMessage message) async {\n    if (!_canEditMessage(message)) return;\n    final controller = TextEditingController(text: message.body);\n    try {\n      final replacement = await showDialog<String>(\n        context: context,\n        builder: (context) => AlertDialog(\n          title: const Text('编辑消息'),\n          content: TextField(\n            controller: controller,\n            autofocus: true,\n            minLines: 1,\n            maxLines: 8,\n            decoration: const InputDecoration(\n              hintText: '新的消息内容',\n              border: OutlineInputBorder(),\n            ),\n          ),\n          actions: <Widget>[\n            TextButton(\n              onPressed: () => Navigator.of(context).pop(),\n              child: const Text('取消'),\n            ),\n            FilledButton(\n              onPressed: () => Navigator.of(context).pop(controller.text.trim()),\n              child: const Text('保存'),\n            ),\n          ],\n        ),\n      );\n      if (!mounted || replacement == null || replacement.isEmpty) return;\n      if (replacement == message.body.trim()) return;\n      await widget.client.editText(\n        widget.room.roomId,\n        message.eventId,\n        replacement,\n      );\n      await _load();\n    } catch (error) {\n      if (mounted) setState(() => _error = error.toString());\n    } finally {\n      controller.dispose();\n    }\n  }\n\n  Future<void> _redactMessage(MatrixMessage message) async {\n    if (!_canRedactMessage(message)) return;\n    final confirmed = await showDialog<bool>(\n      context: context,\n      builder: (context) => AlertDialog(\n        title: const Text('撤回消息？'),\n        content: const Text('这会通过 Matrix redaction 撤回该 Thread 事件，且无法恢复。'),\n        actions: <Widget>[\n          TextButton(\n            onPressed: () => Navigator.of(context).pop(false),\n            child: const Text('取消'),\n          ),\n          FilledButton(\n            onPressed: () => Navigator.of(context).pop(true),\n            child: const Text('确认撤回'),\n          ),\n        ],\n      ),\n    );\n    if (!mounted || confirmed != true) return;\n    try {\n      await widget.client.redactEvent(widget.room.roomId, message.eventId);\n      await _load();\n    } catch (error) {\n      if (mounted) setState(() => _error = error.toString());\n    }\n  }\n\n  Future<void> _showReactionPicker(MatrixMessage message) async {\n''',
)
replace_once(
    'lib/pages/chat/matrix_thread_page.dart',
    '''                            : () => _showReactionPicker(widget.root),\n''',
    '''                            : () => _showMessageActions(\n                                widget.root,\n                                allowMutation: false,\n                              ),\n''',
)
replace_once(
    'lib/pages/chat/matrix_thread_page.dart',
    '''                              : () => _showReactionPicker(message),\n''',
    '''                              : () => _showMessageActions(\n                                  message,\n                                  allowMutation: true,\n                                ),\n''',
)
replace_once(
    'lib/pages/chat/matrix_thread_page.dart',
    '''                        '此 Thread 属于 E2EE 房间；SDK crypto provider 接入前禁止发送明文、reaction 与附件。',\n''',
    '''                        '此 Thread 属于 E2EE 房间；SDK crypto provider 接入前禁止发送明文、reaction、编辑/撤回与附件。',\n''',
)

# 7. Content-builder tests.
replace_once(
    'test/services/messaging/matrix_message_content_test.dart',
    '''  test('image media content keeps metadata and thread relation', () {\n''',
    '''  test('text edit uses m.replace with canonical m.new_content', () {\n    final content = buildMatrixTextReplacementContent(\n      '  corrected text  ',\n      targetEventId: r'$target',\n    );\n\n    expect(content, <String, dynamic>{\n      'msgtype': 'm.text',\n      'body': '* corrected text',\n      'm.new_content': <String, dynamic>{\n        'msgtype': 'm.text',\n        'body': 'corrected text',\n      },\n      'm.relates_to': <String, dynamic>{\n        'rel_type': 'm.replace',\n        'event_id': r'$target',\n      },\n    });\n  });\n\n  test('text edit rejects empty replacement targets and bodies', () {\n    expect(\n      () => buildMatrixTextReplacementContent(' ', targetEventId: r'$target'),\n      throwsArgumentError,\n    );\n    expect(\n      () => buildMatrixTextReplacementContent('hello', targetEventId: ' '),\n      throwsArgumentError,\n    );\n  });\n\n  test('image media content keeps metadata and thread relation', () {\n''',
)

# 8. Provider capability/delegation tests.
replace_once(
    'test/services/messaging/matrix_messaging_provider_test.dart',
    '''      expect(provider.capabilities.reactions, isTrue);\n      expect(provider.capabilities.e2ee, isFalse);\n''',
    '''      expect(provider.capabilities.reactions, isTrue);\n      expect(provider.capabilities.edits, isTrue);\n      expect(provider.capabilities.redactions, isTrue);\n      expect(provider, isA<MessagingMutationProvider>());\n      expect(provider.capabilities.e2ee, isFalse);\n''',
)
replace_once(
    'test/services/messaging/matrix_messaging_provider_test.dart',
    '''      await provider.sendReaction('!room:example.org', r'$event', '👍');\n\n      expect(client.sentText, ('!room:example.org', 'hi'));\n''',
    '''      await provider.sendReaction('!room:example.org', r'$event', '👍');\n      await provider.editText('!room:example.org', r'$event', 'edited');\n      await provider.redactMessage(\n        '!room:example.org',\n        r'$event',\n        reason: 'cleanup',\n      );\n\n      expect(client.sentText, ('!room:example.org', 'hi'));\n''',
)
replace_once(
    'test/services/messaging/matrix_messaging_provider_test.dart',
    '''      expect(client.reaction, ('!room:example.org', r'$event', '👍'));\n''',
    '''      expect(client.reaction, ('!room:example.org', r'$event', '👍'));\n      expect(client.edit, ('!room:example.org', r'$event', 'edited'));\n      expect(client.redaction, ('!room:example.org', r'$event', 'cleanup'));\n''',
)
replace_once(
    'test/services/messaging/matrix_messaging_provider_test.dart',
    '''  (String, String, String)? reaction;\n''',
    '''  (String, String, String)? reaction;\n  (String, String, String)? edit;\n  (String, String, String?)? redaction;\n''',
)
replace_once(
    'test/services/messaging/matrix_messaging_provider_test.dart',
    '''  Future<void> sendReaction(\n    String roomId,\n    String eventId,\n    String key,\n  ) async {\n    reaction = (roomId, eventId, key);\n  }\n}\n''',
    '''  Future<void> sendReaction(\n    String roomId,\n    String eventId,\n    String key,\n  ) async {\n    reaction = (roomId, eventId, key);\n  }\n\n  @override\n  Future<void> editText(String roomId, String eventId, String body) async {\n    edit = (roomId, eventId, body);\n  }\n\n  @override\n  Future<void> redactEvent(\n    String roomId,\n    String eventId, {\n    String? reason,\n  }) async {\n    redaction = (roomId, eventId, reason);\n  }\n}\n''',
)

# 9. Room widget mutation regression.
replace_once(
    'test/pages/chat/matrix_room_page_test.dart',
    '''  testWidgets('pauses room polling while a thread route is visible', (\n''',
    '''  testWidgets('edits and redacts own plaintext text messages', (tester) async {\n    final client = _FakeMatrixClient(withOwnMessage: true);\n\n    await tester.pumpWidget(\n      MaterialApp(home: MatrixRoomPage(client: client, room: room)),\n    );\n    await tester.pump();\n\n    await tester.longPress(find.text('my message'));\n    await tester.pumpAndSettle();\n    expect(find.text('编辑消息'), findsOneWidget);\n    expect(find.text('撤回消息'), findsOneWidget);\n    await tester.tap(find.text('编辑消息'));\n    await tester.pumpAndSettle();\n    final editDialog = find.byType(AlertDialog);\n    final editField = find.descendant(\n      of: editDialog,\n      matching: find.byType(TextField),\n    );\n    await tester.enterText(editField, 'updated message');\n    await tester.tap(find.text('保存'));\n    await tester.pumpAndSettle();\n    expect(client.edits, <String>[r'$mine|updated message']);\n\n    await tester.longPress(find.text('my message'));\n    await tester.pumpAndSettle();\n    await tester.tap(find.text('撤回消息'));\n    await tester.pumpAndSettle();\n    await tester.tap(find.text('确认撤回'));\n    await tester.pumpAndSettle();\n    expect(client.redactions, <String>[r'$mine']);\n\n    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));\n    await tester.pump();\n  });\n\n  testWidgets('pauses room polling while a thread route is visible', (\n''',
)
replace_once(
    'test/pages/chat/matrix_room_page_test.dart',
    '''  _FakeMatrixClient({this.withThread = false});\n\n  final bool withThread;\n''',
    '''  _FakeMatrixClient({this.withThread = false, this.withOwnMessage = false});\n\n  final bool withThread;\n  final bool withOwnMessage;\n''',
)
replace_once(
    'test/pages/chat/matrix_room_page_test.dart',
    '''  String? releasedRoomId;\n''',
    '''  String? releasedRoomId;\n  final List<String> edits = <String>[];\n  final List<String> redactions = <String>[];\n''',
)
replace_once(
    'test/pages/chat/matrix_room_page_test.dart',
    '''    loadPageCalls++;\n    if (!withThread) {\n''',
    '''    loadPageCalls++;\n    if (withOwnMessage) {\n      return matrix.MatrixMessagePage(\n        messages: <matrix.MatrixMessage>[\n          matrix.MatrixMessage(\n            eventId: r'$mine',\n            sender: '@me:example.org',\n            body: 'my message',\n            timestamp: DateTime.fromMillisecondsSinceEpoch(100),\n            msgType: 'm.text',\n          ),\n        ],\n      );\n    }\n    if (!withThread) {\n''',
)
replace_once(
    'test/pages/chat/matrix_room_page_test.dart',
    '''  Future<void> setTyping(\n    String roomId, {\n    required bool typing,\n    int timeoutMs = 30000,\n  }) async {}\n}\n''',
    '''  Future<void> setTyping(\n    String roomId, {\n    required bool typing,\n    int timeoutMs = 30000,\n  }) async {}\n\n  @override\n  Future<void> editText(String roomId, String eventId, String body) async {\n    edits.add('$eventId|$body');\n  }\n\n  @override\n  Future<void> redactEvent(\n    String roomId,\n    String eventId, {\n    String? reason,\n  }) async {\n    redactions.add(eventId);\n  }\n}\n''',
)

# 10. Thread widget mutation regression and reaction menu adjustment.
replace_once(
    'test/pages/chat/matrix_thread_page_test.dart',
    '''    await tester.longPress(find.text('loaded thread reply'));\n    await tester.pumpAndSettle();\n    expect(find.text('👍'), findsOneWidget);\n    await tester.tap(find.text('👍'));\n''',
    '''    await tester.longPress(find.text('loaded thread reply'));\n    await tester.pumpAndSettle();\n    await tester.tap(find.text('Reaction'));\n    await tester.pumpAndSettle();\n    expect(find.text('👍'), findsOneWidget);\n    await tester.tap(find.text('👍'));\n''',
)
replace_once(
    'test/pages/chat/matrix_thread_page_test.dart',
    '''  testWidgets('sends text as a thread relation with a reply fallback', (\n''',
    '''  testWidgets('edits and redacts own thread replies', (tester) async {\n    final client = _FakeMatrixClient(ownReply: true);\n    final media = MatrixMediaService(session: client.session!);\n\n    await tester.pumpWidget(\n      MaterialApp(\n        home: MatrixThreadPage(\n          client: client,\n          room: room,\n          root: root,\n          mediaService: media,\n        ),\n      ),\n    );\n    await tester.pump();\n\n    await tester.longPress(find.text('loaded thread reply'));\n    await tester.pumpAndSettle();\n    expect(find.text('编辑消息'), findsOneWidget);\n    expect(find.text('撤回消息'), findsOneWidget);\n    await tester.tap(find.text('编辑消息'));\n    await tester.pumpAndSettle();\n    final editDialog = find.byType(AlertDialog);\n    final editField = find.descendant(\n      of: editDialog,\n      matching: find.byType(TextField),\n    );\n    await tester.enterText(editField, 'updated thread reply');\n    await tester.tap(find.text('保存'));\n    await tester.pumpAndSettle();\n    expect(client.edits, <String>[r'$reply|updated thread reply']);\n\n    await tester.longPress(find.text('loaded thread reply'));\n    await tester.pumpAndSettle();\n    await tester.tap(find.text('撤回消息'));\n    await tester.pumpAndSettle();\n    await tester.tap(find.text('确认撤回'));\n    await tester.pumpAndSettle();\n    expect(client.redactions, <String>[r'$reply']);\n\n    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));\n    await tester.pump();\n    media.dispose();\n  });\n\n  testWidgets('sends text as a thread relation with a reply fallback', (\n''',
)
replace_once(
    'test/pages/chat/matrix_thread_page_test.dart',
    '''  _FakeMatrixClient({this.repeatPaginationToken = false});\n\n  final bool repeatPaginationToken;\n''',
    '''  _FakeMatrixClient({\n    this.repeatPaginationToken = false,\n    this.ownReply = false,\n  });\n\n  final bool repeatPaginationToken;\n  final bool ownReply;\n''',
)
replace_once(
    'test/pages/chat/matrix_thread_page_test.dart',
    '''  final List<String> sentTexts = <String>[];\n''',
    '''  final List<String> sentTexts = <String>[];\n  final List<String> edits = <String>[];\n  final List<String> redactions = <String>[];\n''',
)
replace_once(
    'test/pages/chat/matrix_thread_page_test.dart',
    '''          sender: '@bob:example.org',\n          body: 'loaded thread reply',\n          timestamp: DateTime.fromMillisecondsSinceEpoch(200),\n          threadRootEventId: threadRootEventId,\n''',
    '''          sender: ownReply ? '@me:example.org' : '@bob:example.org',\n          body: 'loaded thread reply',\n          timestamp: DateTime.fromMillisecondsSinceEpoch(200),\n          msgType: 'm.text',\n          threadRootEventId: threadRootEventId,\n''',
)
replace_once(
    'test/pages/chat/matrix_thread_page_test.dart',
    '''  Future<void> sendText(\n    String roomId,\n    String body, {\n    String? replyToEventId,\n    String? threadRootEventId,\n    bool threadFallback = false,\n  }) async {\n    sentTexts.add('$body|$threadRootEventId|$replyToEventId|$threadFallback');\n  }\n}\n''',
    '''  Future<void> sendText(\n    String roomId,\n    String body, {\n    String? replyToEventId,\n    String? threadRootEventId,\n    bool threadFallback = false,\n  }) async {\n    sentTexts.add('$body|$threadRootEventId|$replyToEventId|$threadFallback');\n  }\n\n  @override\n  Future<void> editText(String roomId, String eventId, String body) async {\n    edits.add('$eventId|$body');\n  }\n\n  @override\n  Future<void> redactEvent(\n    String roomId,\n    String eventId, {\n    String? reason,\n  }) async {\n    redactions.add(eventId);\n  }\n}\n''',
)

print('Matrix edit/redaction patch applied successfully')
