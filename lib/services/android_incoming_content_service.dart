import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../pages/create_topic_page.dart';
import '../pages/search_page.dart';
import '../widgets/post/reply_sheet.dart';
import 'incoming_content.dart';

/// The initial ACTION_SEND may arrive before Flutter has a navigator.
class AndroidIncomingContentService {
  AndroidIncomingContentService._();
  static final instance = AndroidIncomingContentService._();

  static const channel = MethodChannel('com.github.lingyan000.fluxdo/incoming_content');
  BuildContext? _context;
  bool _draining = false;
  bool _drainAgain = false;

  void initialize(BuildContext context) {
    if (!Platform.isAndroid) return;
    _context = context;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'newIntent') unawaited(_drain());
    });
    unawaited(_drain());
  }

  void dispose() {
    _context = null;
    if (Platform.isAndroid) channel.setMethodCallHandler(null);
  }

  Future<void> _drain() async {
    if (_draining) {
      _drainAgain = true;
      return;
    }
    _draining = true;
    try {
      do {
        _drainAgain = false;
        while (true) {
          final payload = await channel.invokeMapMethod<String, dynamic>('consume');
          if (payload == null) break;
          final incoming = IncomingContent.fromMap(payload);
          if (incoming != null) await _open(incoming);
        }
      } while (_drainAgain);
    } on PlatformException catch (error) {
      debugPrint('[IncomingContent] Failed to import share: $error');
    } finally {
      _draining = false;
    }
  }

  Future<void> _open(IncomingContent content) async {
    final ctx = _context;
    if (ctx == null || !ctx.mounted) return;
    final navigator = Navigator.of(ctx, rootNavigator: true);
    switch (content.action) {
      case 'share':
      case 'topic':
        final title = content.title.length <= 250
            ? content.title
            : content.title.substring(0, 250);
        await navigator.push(MaterialPageRoute<void>(
          builder: (_) => CreateTopicPage(
            initialTitle: title.isEmpty ? null : title,
            initialContent: content.text.isEmpty ? null : content.text,
            incomingAttachments: content.attachments,
          ),
        ));
        return;
      case 'message':
        await showReplySheet(context: ctx, composePrivateMessage: true);
        return;
      case 'search':
        await navigator.push(MaterialPageRoute<void>(builder: (_) => const SearchPage()));
        return;
    }
  }
}
