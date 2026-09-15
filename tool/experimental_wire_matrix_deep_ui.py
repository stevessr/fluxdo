from pathlib import Path

path = Path('lib/pages/chat/matrix_room_page.dart')
text = path.read_text()


def replace_once(old: str, new: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'expected exactly one match, got {count}: {old[:100]!r}')
    text = text.replace(old, new, 1)


replace_once(
    "import '../../services/messaging/matrix_media_service.dart';\n",
    "import '../../services/messaging/matrix_media_service.dart';\n"
    "import 'matrix_message_media_view.dart';\n"
    "import 'matrix_thread_page.dart';\n",
)

replace_once(
    '  bool _uploadingMedia = false;\n',
    '  bool _uploadingMedia = false;\n  double? _uploadProgress;\n',
)

start = text.index('  Future<void> _pickAndSendMedia() async {')
end = text.index('  static String _formatBytes(int bytes) {', start)
new_media = '''  Future<void> _pickAndSendMedia() async {
    if (_sendingDisabled) return;
    final session = widget.client.session;
    if (session == null) {
      setState(() => _error = 'Matrix 会话已失效，请重新登录。');
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: false,
    );
    if (result == null || result.files.isEmpty || !mounted) return;
    final file = result.files.single;

    setState(() {
      _uploadingMedia = true;
      _uploadProgress = 0;
      _error = null;
    });
    try {
      final media = MatrixMediaService(session: session);
      int? serverMaxBytes;
      try {
        serverMaxBytes = await media.maxUploadBytes();
      } on MatrixMediaException {
        // Legacy homeservers may omit media/config. Streaming avoids heap OOM,
        // but keep a generous network-safety ceiling for the LAB provider.
      }

      const fallbackUploadLimit = 512 * 1024 * 1024;
      final effectiveMax = serverMaxBytes ?? fallbackUploadLimit;
      if (file.size > effectiveMax) {
        throw MatrixMediaException(
          '附件 ${file.name} 为 ${_formatBytes(file.size)}；当前允许上限为 '
          '${_formatBytes(effectiveMax)}。',
        );
      }

      final contentType = lookupMimeType(file.name) ?? 'application/octet-stream';
      var lastRenderedProgress = -1.0;
      final uploaded = await media.uploadStream(
        stream: file.xFile.openRead(),
        length: file.size,
        filename: file.name,
        contentType: contentType,
        onSendProgress: (sent, total) {
          if (!mounted || total <= 0) return;
          final progress = (sent / total).clamp(0.0, 1.0);
          if (progress < 1 && progress - lastRenderedProgress < 0.01) return;
          lastRenderedProgress = progress;
          setState(() => _uploadProgress = progress);
        },
      );
      await media.sendUpload(
        widget.room.roomId,
        uploaded,
        replyToEventId: _replyTarget?.eventId,
        threadRootEventId: _composerThreadRootEventId,
        threadFallback: _composerThreadFallback,
      );
      if (!mounted) return;
      setState(_clearComposerRelation);
      await _loadLatest(
        showSpinner: false,
        preservePaginationCursor: true,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _uploadingMedia = false;
          _uploadProgress = null;
        });
      }
    }
  }

'''
text = text[:start] + new_media + text[end:]

replace_once(
    '''  void _scrollToBottom() {
''',
    '''  Future<void> _openThread(MatrixMessage root) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => MatrixThreadPage(
          client: widget.client,
          room: widget.room,
          root: root,
        ),
      ),
    );
    if (mounted) {
      await _loadLatest(
        showSpinner: false,
        scrollToBottom: false,
        preservePaginationCursor: true,
      );
    }
  }

  void _scrollToBottom() {
''',
)

replace_once(
    '''                        return _MatrixMessageBubble(
                          message: message,
                          own: own,
                          replyTarget: replyTarget,
''',
    '''                        return _MatrixMessageBubble(
                          message: message,
                          own: own,
                          session: widget.client.session,
                          replyTarget: replyTarget,
                          onOpenThread: message.threadCount > 0
                              ? () => _openThread(message)
                              : null,
''',
)

replace_once(
    '''                        icon: _uploadingMedia
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.attach_file_rounded),
''',
    '''                        icon: _uploadingMedia
                            ? SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  value: _uploadProgress,
                                ),
                              )
                            : const Icon(Icons.attach_file_rounded),
''',
)

replace_once(
    '''  const _MatrixMessageBubble({
    required this.message,
    required this.own,
    this.replyTarget,
    this.onLongPress,
  });

  final MatrixMessage message;
  final bool own;
  final MatrixMessage? replyTarget;
  final VoidCallback? onLongPress;
''',
    '''  const _MatrixMessageBubble({
    required this.message,
    required this.own,
    this.session,
    this.replyTarget,
    this.onLongPress,
    this.onOpenThread,
  });

  final MatrixMessage message;
  final bool own;
  final MatrixSession? session;
  final MatrixMessage? replyTarget;
  final VoidCallback? onLongPress;
  final VoidCallback? onOpenThread;
''',
)

replace_once(
    '''                  Flexible(child: Text(message.body)),
                ],
              ),
              if (message.isThreadReply || message.threadCount > 0) ...<Widget>[
''',
    '''                  Flexible(child: Text(message.body)),
                ],
              ),
              if (message.hasMedia && session != null)
                MatrixMessageMediaView(message: message, session: session!),
              if (message.threadCount > 0) ...<Widget>[
''',
)

replace_once(
    '''                  children: <Widget>[
                    if (message.isThreadReply)
                      _RelationChip(
                        icon: Icons.forum_outlined,
                        label: 'Thread',
                      ),
                    if (message.threadCount > 0)
                      _RelationChip(
                        icon: Icons.forum_rounded,
                        label: '${message.threadCount} 条线程回复',
                      ),
                  ],
''',
    '''                  children: <Widget>[
                    _RelationChip(
                      icon: Icons.forum_rounded,
                      label: '${message.threadCount} 条线程回复',
                      onTap: onOpenThread,
                    ),
                  ],
''',
)

replace_once(
    '''class _RelationChip extends StatelessWidget {
  const _RelationChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: colors.secondaryContainer.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 13),
          const SizedBox(width: 4),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}
''',
    '''class _RelationChip extends StatelessWidget {
  const _RelationChip({
    required this.icon,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.secondaryContainer.withValues(alpha: 0.75),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 13),
              const SizedBox(width: 4),
              Text(label, style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
        ),
      ),
    );
  }
}
''',
)

path.write_text(text)
