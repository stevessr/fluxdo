from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly one match, got {count}')
    return text.replace(old, new, 1)

path = Path('lib/pages/chat/matrix_room_page.dart')
text = path.read_text()

text = replace_once(
    text,
    "  MatrixMediaService? _mediaService;\n  bool _typingSent = false;\n",
    "  MatrixMediaService? _mediaService;\n  bool _threadRouteActive = false;\n  bool _typingSent = false;\n",
    'thread route state',
)
text = replace_once(
    text,
    "  void didChangeAppLifecycleState(AppLifecycleState state) {\n"
    "    if (state == AppLifecycleState.resumed) {\n"
    "      _startForegroundRefresh();\n"
    "      unawaited(_refreshLatestSilently());\n"
    "    } else {\n"
    "      _stopForegroundRefresh();\n"
    "    }\n"
    "  }\n",
    "  void didChangeAppLifecycleState(AppLifecycleState state) {\n"
    "    if (state == AppLifecycleState.resumed) {\n"
    "      if (!_threadRouteActive) {\n"
    "        _startForegroundRefresh();\n"
    "        unawaited(_refreshLatestSilently());\n"
    "      }\n"
    "    } else {\n"
    "      _stopForegroundRefresh();\n"
    "    }\n"
    "  }\n",
    'lifecycle thread guard',
)
text = replace_once(
    text,
    "  void _startForegroundRefresh() {\n"
    "    _refreshTimer?.cancel();\n",
    "  void _startForegroundRefresh() {\n"
    "    if (_threadRouteActive) return;\n"
    "    _refreshTimer?.cancel();\n",
    'timer thread guard',
)
text = replace_once(
    text,
    "  Future<void> _refreshLatestSilently() async {\n"
    "    if (!mounted ||\n",
    "  Future<void> _refreshLatestSilently() async {\n"
    "    if (!mounted ||\n"
    "        _threadRouteActive ||\n",
    'silent refresh thread guard',
)
text = replace_once(
    text,
    "    final mediaService = _mediaFor(session);\n"
    "    _stopForegroundRefresh();\n",
    "    final mediaService = _mediaFor(session);\n"
    "    _threadRouteActive = true;\n"
    "    _stopForegroundRefresh();\n",
    'thread route activate',
)
text = replace_once(
    text,
    "    } finally {\n"
    "      if (mounted) {\n"
    "        _startForegroundRefresh();\n"
    "        await _loadLatest(\n"
    "          showSpinner: false,\n"
    "          scrollToBottom: false,\n"
    "          preservePaginationCursor: true,\n"
    "        );\n"
    "      }\n"
    "    }\n",
    "    } finally {\n"
    "      _threadRouteActive = false;\n"
    "      if (mounted &&\n"
    "          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {\n"
    "        _startForegroundRefresh();\n"
    "        await _loadLatest(\n"
    "          showSpinner: false,\n"
    "          scrollToBottom: false,\n"
    "          preservePaginationCursor: true,\n"
    "        );\n"
    "      }\n"
    "    }\n",
    'thread route deactivate',
)

path.write_text(text)
print('Thread route polling guard staged successfully')
