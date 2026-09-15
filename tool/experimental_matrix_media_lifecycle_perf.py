from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly one match, got {count}')
    return text.replace(old, new, 1)

# Media view consumes a shared transport instead of creating one per bubble.
media_path = Path('lib/pages/chat/matrix_message_media_view.dart')
media = media_path.read_text()
media = replace_once(
    media,
    "    required this.message,\n    required this.session,\n",
    "    required this.message,\n    required this.mediaService,\n",
    'media view constructor',
)
media = replace_once(
    media,
    "  final MatrixMessage message;\n  final MatrixSession session;\n",
    "  final MatrixMessage message;\n  final MatrixMediaService mediaService;\n",
    'media view field',
)
media = replace_once(
    media,
    "    if (oldWidget.session.accessToken != widget.session.accessToken ||\n"
    "        oldWidget.session.homeserver != widget.session.homeserver ||\n"
    "        oldWidget.message.mediaUri != widget.message.mediaUri ||\n",
    "    if (!identical(oldWidget.mediaService, widget.mediaService) ||\n"
    "        oldWidget.message.mediaUri != widget.message.mediaUri ||\n",
    'media view update identity',
)
media = replace_once(
    media,
    "    _media = MatrixMediaService(session: widget.session);\n",
    "    _media = widget.mediaService;\n",
    'media view shared service',
)
media = replace_once(
    media,
    "      return _media.downloadBytes(\n"
    "        thumbnail,\n"
    "        maxBytes: MatrixMediaService.defaultThumbnailLimitBytes,\n"
    "      );\n",
    "      return _media.downloadPreviewBytes(\n"
    "        thumbnail,\n"
    "        maxBytes: MatrixMediaService.defaultThumbnailLimitBytes,\n"
    "      );\n",
    'media view preview cache',
)
media_path.write_text(media)

# Thread page receives the room-owned transport and passes it to every card.
thread_path = Path('lib/pages/chat/matrix_thread_page.dart')
thread = thread_path.read_text()
thread = replace_once(
    thread,
    "import '../../services/matrix_client_service.dart';\n",
    "import '../../services/matrix_client_service.dart';\n"
    "import '../../services/messaging/matrix_media_service.dart';\n",
    'thread media import',
)
thread = replace_once(
    thread,
    "    required this.client,\n    required this.room,\n    required this.root,\n",
    "    required this.client,\n    required this.room,\n    required this.root,\n    required this.mediaService,\n",
    'thread constructor media service',
)
thread = replace_once(
    thread,
    "  final MatrixClientService client;\n  final MatrixRoomSummary room;\n  final MatrixMessage root;\n",
    "  final MatrixClientService client;\n"
    "  final MatrixRoomSummary room;\n"
    "  final MatrixMessage root;\n"
    "  final MatrixMediaService mediaService;\n",
    'thread media field',
)
thread = thread.replace('                        session: session,\n', '                        mediaService: widget.mediaService,\n')
if '                        session: session,\n' in thread:
    raise SystemExit('thread root session wiring still present')
thread = replace_once(
    thread,
    "    required this.own,\n    required this.session,\n",
    "    required this.own,\n    required this.mediaService,\n",
    'thread card constructor',
)
thread = replace_once(
    thread,
    "  final bool own;\n  final MatrixSession? session;\n",
    "  final bool own;\n  final MatrixMediaService mediaService;\n",
    'thread card media field',
)
thread = replace_once(
    thread,
    "            if (message.hasMedia && session != null)\n"
    "              MatrixMessageMediaView(message: message, session: session!),\n",
    "            if (message.hasMedia)\n"
    "              MatrixMessageMediaView(\n"
    "                message: message,\n"
    "                mediaService: mediaService,\n"
    "              ),\n",
    'thread card media view',
)
thread_path.write_text(thread)

# Room page owns one transport, reuses it for uploads/bubbles/threads, and
# disposes it with the route.
room_path = Path('lib/pages/chat/matrix_room_page.dart')
room = room_path.read_text()
room = replace_once(
    room,
    "  Timer? _typingStopTimer;\n  Timer? _refreshTimer;\n",
    "  Timer? _typingStopTimer;\n  Timer? _refreshTimer;\n  MatrixMediaService? _mediaService;\n",
    'room media service state',
)
room = replace_once(
    room,
    "    widget.client.releaseTimeline(widget.room.roomId);\n"
    "    _composerController.dispose();\n",
    "    widget.client.releaseTimeline(widget.room.roomId);\n"
    "    _mediaService?.dispose();\n"
    "    _mediaService = null;\n"
    "    _composerController.dispose();\n",
    'room media service dispose',
)
room = replace_once(
    room,
    "  Future<void> _pickAndSendMedia() async {\n",
    "  MatrixMediaService _mediaFor(MatrixSession session) {\n"
    "    final current = _mediaService;\n"
    "    if (current != null &&\n"
    "        current.session.homeserver == session.homeserver &&\n"
    "        current.session.accessToken == session.accessToken) {\n"
    "      return current;\n"
    "    }\n"
    "    current?.dispose();\n"
    "    return _mediaService = MatrixMediaService(session: session);\n"
    "  }\n\n"
    "  Future<void> _pickAndSendMedia() async {\n",
    'room media service factory',
)
room = replace_once(
    room,
    "      final media = MatrixMediaService(session: session);\n",
    "      final media = _mediaFor(session);\n",
    'room upload shared service',
)
room = replace_once(
    room,
    "  Future<void> _openThread(MatrixMessage root) async {\n"
    "    await Navigator.of(context).push<void>(\n",
    "  Future<void> _openThread(MatrixMessage root) async {\n"
    "    final session = widget.client.session;\n"
    "    if (session == null) {\n"
    "      if (mounted) setState(() => _error = 'Matrix 会话已失效，请重新登录。');\n"
    "      return;\n"
    "    }\n"
    "    final mediaService = _mediaFor(session);\n"
    "    await Navigator.of(context).push<void>(\n",
    'room thread media setup',
)
room = replace_once(
    room,
    "          room: widget.room,\n          root: root,\n",
    "          room: widget.room,\n          root: root,\n          mediaService: mediaService,\n",
    'room thread media argument',
)
room = replace_once(
    room,
    "  Widget build(BuildContext context) {\n"
    "    final currentUserId = widget.client.session?.userId;\n",
    "  Widget build(BuildContext context) {\n"
    "    final session = widget.client.session;\n"
    "    final currentUserId = session?.userId;\n"
    "    final mediaService = session == null ? null : _mediaFor(session);\n",
    'room build media service',
)
room = replace_once(
    room,
    "                          session: widget.client.session,\n",
    "                          mediaService: mediaService,\n",
    'room bubble media service',
)
room = replace_once(
    room,
    "    this.session,\n    this.replyTarget,\n",
    "    this.mediaService,\n    this.replyTarget,\n",
    'room bubble constructor media',
)
room = replace_once(
    room,
    "  final bool own;\n  final MatrixSession? session;\n",
    "  final bool own;\n  final MatrixMediaService? mediaService;\n",
    'room bubble media field',
)
room = replace_once(
    room,
    "              if (message.hasMedia && session != null)\n"
    "                MatrixMessageMediaView(message: message, session: session!),\n",
    "              if (message.hasMedia && mediaService != null)\n"
    "                MatrixMessageMediaView(\n"
    "                  message: message,\n"
    "                  mediaService: mediaService!,\n"
    "                ),\n",
    'room bubble media view',
)
room_path.write_text(room)

print('Shared Matrix media transport wiring applied successfully')
