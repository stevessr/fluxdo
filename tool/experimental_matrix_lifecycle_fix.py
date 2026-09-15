from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, got {count}")
    return text.replace(old, new, 1)


# 1. Thread page: fix initial request deadlock and serialize refresh/pagination.
thread_path = Path('lib/pages/chat/matrix_thread_page.dart')
thread = thread_path.read_text()
thread = replace_once(
    thread,
    "  bool _loading = true;\n  bool _loadingMore = false;\n  bool _sending = false;\n",
    "  bool _loading = true;\n  bool _loadingMore = false;\n  bool _requestInFlight = false;\n  bool _sending = false;\n",
    'thread request flag',
)
thread = replace_once(
    thread,
    "  Future<void> _load({String? from, bool more = false}) async {\n"
    "    if (more ? _loadingMore : _loading) return;\n"
    "    setState(() {\n",
    "  Future<void> _load({String? from, bool more = false}) async {\n"
    "    if (_requestInFlight) return;\n"
    "    _requestInFlight = true;\n"
    "    setState(() {\n",
    'thread load guard',
)
thread = replace_once(
    thread,
    "      setState(() {\n"
    "        _messages = page.messages;\n"
    "        _nextToken = page.nextToken;\n"
    "      });\n",
    "      setState(() {\n"
    "        _messages = page.messages;\n"
    "        final next = page.nextToken;\n"
    "        _nextToken = next == from ? null : next;\n"
    "      });\n",
    'thread repeated token guard',
)
thread = replace_once(
    thread,
    "    } finally {\n"
    "      if (mounted) {\n"
    "        setState(() {\n"
    "          _loading = false;\n"
    "          _loadingMore = false;\n"
    "        });\n"
    "      }\n"
    "    }\n"
    "  }\n",
    "    } finally {\n"
    "      _requestInFlight = false;\n"
    "      if (mounted) {\n"
    "        setState(() {\n"
    "          _loading = false;\n"
    "          _loadingMore = false;\n"
    "        });\n"
    "      }\n"
    "    }\n"
    "  }\n",
    'thread request release',
)
thread = replace_once(
    thread,
    "            onPressed: _loading ? null : () => _load(),\n",
    "            onPressed: _requestInFlight ? null : () => _load(),\n",
    'thread refresh disable',
)
thread = replace_once(
    thread,
    "                            onPressed: _loadingMore\n"
    "                                ? null\n"
    "                                : () => _load(from: _nextToken, more: true),\n",
    "                            onPressed: _requestInFlight\n"
    "                                ? null\n"
    "                                : () => _load(from: _nextToken, more: true),\n",
    'thread pagination disable',
)
thread_path.write_text(thread)

# 2. Room page: release raw relation/timeline cache when the route is disposed.
room_path = Path('lib/pages/chat/matrix_room_page.dart')
room = room_path.read_text()
room = replace_once(
    room,
    "    _composerController.dispose();\n"
    "    _scrollController.dispose();\n"
    "    super.dispose();\n",
    "    widget.client.releaseTimeline(widget.room.roomId);\n"
    "    _composerController.dispose();\n"
    "    _scrollController.dispose();\n"
    "    super.dispose();\n",
    'room timeline release',
)
room_path.write_text(room)

# 3. Cache: add predicate removal for all thread keys belonging to a room.
cache_path = Path('lib/services/messaging/matrix_timeline_event_cache.dart')
cache = cache_path.read_text()
cache = replace_once(
    cache,
    "  void removeRoom(String roomId) => _rooms.remove(roomId);\n\n"
    "  void clear() => _rooms.clear();\n",
    "  void removeRoom(String roomId) => _rooms.remove(roomId);\n\n"
    "  void removeWhere(bool Function(String roomId) test) {\n"
    "    _rooms.removeWhere((roomId, _) => test(roomId));\n"
    "  }\n\n"
    "  void clear() => _rooms.clear();\n",
    'cache predicate removal',
)
cache_path.write_text(cache)

# 4. Client: use the shared recursive thread helper and evict thread caches when a room leaves.
client_path = Path('lib/services/matrix_client_service.dart')
client = client_path.read_text()
client = replace_once(
    client,
    "import 'messaging/matrix_room_metadata.dart';\n"
    "import 'messaging/matrix_timeline_event_cache.dart';\n",
    "import 'messaging/matrix_room_metadata.dart';\n"
    "import 'messaging/matrix_thread_relations.dart';\n"
    "import 'messaging/matrix_timeline_event_cache.dart';\n",
    'thread helper import',
)
client = replace_once(
    client,
    "        _roomCache.remove(roomId);\n"
    "        _timelineEventCache.removeRoom(roomId);\n",
    "        _roomCache.remove(roomId);\n"
    "        _timelineEventCache.removeRoom(roomId);\n"
    "        final threadPrefix = '$roomId\\u0000';\n"
    "        _threadEventCache.removeWhere((key) => key.startsWith(threadPrefix));\n",
    'leave-room thread eviction',
)
client = replace_once(
    client,
    "      final relations = _threadRelationsForRoot(\n",
    "      final relations = filterMatrixThreadRelations(\n",
    'shared thread relation helper',
)
client_path.write_text(client)

print('Matrix lifecycle patch applied successfully')
