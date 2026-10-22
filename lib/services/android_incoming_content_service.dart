import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../pages/create_topic_page.dart';
import '../pages/search_page.dart';
import '../widgets/post/reply_sheet.dart';
import 'incoming_content.dart';
import 'toast_service.dart';

/// The initial ACTION_SEND may arrive before Flutter has a navigator.
class AndroidIncomingContentService {
  AndroidIncomingContentService._();
  static final instance = AndroidIncomingContentService._();

  static const channel = MethodChannel('com.github.lingyan000.fluxdo/incoming_content');
  BuildContext? _context;
  bool _draining = false;
  bool _drainAgain = false;
  bool _presenting = false;
  final Queue<IncomingContent> _queued = Queue<IncomingContent>();

  void initialize(BuildContext context) {
    if (!Platform.isAndroid) return;
    _context = context;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'newIntent') unawaited(_drain());
    });
    unawaited(_drain());
    unawaited(_presentQueued());
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
          if (incoming != null) {
            _queued.add(incoming);
            unawaited(_presentQueued());
          }
        }
      } while (_drainAgain);
    } on PlatformException catch (error) {
      debugPrint('[IncomingContent] Failed to import share: $error');
      ToastService.showError('分享文件读取失败，请重新分享');
    } finally {
      _draining = false;
    }
  }

  /// Copy the next Android share immediately, even when a previous editor is
  /// still open; show editors sequentially to avoid nesting multiple composers.
  Future<void> _presentQueued() async {
    if (_presenting) return;
    _presenting = true;
    try {
      while (_queued.isNotEmpty) {
        final context = _context;
        if (context == null || !context.mounted) return;
        final item = _queued.removeFirst();
        try {
          await _open(item);
        } catch (error, stack) {
          debugPrint('[IncomingContent] Cannot open shared content: $error\\n$stack');
          ToastService.showError('无法打开分享内容，请重试');
        }
      }
    } finally {
      _presenting = false;
    }
  }

  Future<void> _open(IncomingContent content) async {
    final ctx = _context;
    if (ctx == null || !ctx.mounted) return;
    final navigator = Navigator.of(ctx, rootNavigator: true);
    if (content.skippedFiles > 0) {
      ToastService.showError('有 ${content.skippedFiles} 个附件无法读取或超过分享数量限制');
    }
    switch (content.action) {
      case 'share':
      case 'topic':
        if (content.action == 'share' &&
            content.title.isEmpty &&
            content.text.isEmpty &&
            content.attachments.isEmpty) {
          if (content.skippedFiles == 0) {
            ToastService.showError('分享内容为空，请重新选择');
          }
          return;
        }
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
