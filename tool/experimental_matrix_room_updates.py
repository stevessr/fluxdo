from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text()
    if old not in text:
        raise SystemExit(f'anchor not found in {path}: {old[:160]!r}')
    file.write_text(text.replace(old, new, 1))


bus = r'''import 'dart:async';

/// Lightweight broadcast signal for Matrix rooms whose `/sync` timeline has
/// changed.
///
/// The bus deliberately carries only room IDs. Raw `/sync` timeline events stay
/// out of the paged history LRU, while active room UIs can request a fresh
/// `/messages` page only when their room actually received a timeline delta.
class MatrixRoomUpdateBus {
  final StreamController<String> _controller =
      StreamController<String>.broadcast();

  bool _disposed = false;

  Stream<String> watch(String roomId) {
    if (roomId.isEmpty) return const Stream<String>.empty();
    return _controller.stream.where((changedRoomId) => changedRoomId == roomId);
  }

  void publish(String roomId) {
    if (_disposed || roomId.isEmpty) return;
    _controller.add(roomId);
  }

  void publishAll(Iterable<String> roomIds) {
    if (_disposed) return;
    for (final roomId in roomIds) {
      publish(roomId);
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_controller.close());
  }
}
'''
Path('lib/services/messaging/matrix_room_update_bus.dart').write_text(bus)

bus_test = r'''import 'dart:async';

import 'package:fluxdo/services/messaging/matrix_room_update_bus.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('watch filters updates by exact room id', () async {
    final bus = MatrixRoomUpdateBus();
    final roomA = <String>[];
    final roomB = <String>[];
    final subA = bus.watch('!a:example.org').listen(roomA.add);
    final subB = bus.watch('!b:example.org').listen(roomB.add);

    bus.publish('!b:example.org');
    bus.publishAll(const <String>[
      '!a:example.org',
      '!a:example.org',
      '',
      '!b:example.org',
    ]);
    await _flushAsync();

    expect(roomA, <String>['!a:example.org', '!a:example.org']);
    expect(roomB, <String>['!b:example.org', '!b:example.org']);

    await subA.cancel();
    await subB.cancel();
    bus.dispose();
  });

  test('empty watch stays silent', () async {
    final bus = MatrixRoomUpdateBus();
    final values = <String>[];
    final sub = bus.watch('').listen(values.add);

    bus.publish('!a:example.org');
    await _flushAsync();
    expect(values, isEmpty);

    await sub.cancel();
    bus.dispose();
  });
}

Future<void> _flushAsync() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}
'''
Path('test/services/messaging/matrix_room_update_bus_test.dart').write_text(bus_test)

# Matrix client: publish room IDs only after a successful /sync response has
# been processed. Do not feed sync timeline chunks into the paged history LRU.
replace_once(
    'lib/services/matrix_client_service.dart',
    "import 'messaging/matrix_room_metadata.dart';\n",
    "import 'messaging/matrix_room_metadata.dart';\nimport 'messaging/matrix_room_update_bus.dart';\n",
)
replace_once(
    'lib/services/matrix_client_service.dart',
    '''  final Map<String, MatrixRoomSummary> _roomCache =\n      <String, MatrixRoomSummary>{};\n\n''',
    '''  final Map<String, MatrixRoomSummary> _roomCache =\n      <String, MatrixRoomSummary>{};\n\n  /// Broadcasts room IDs whose `/sync` timeline contained at least one event.\n  /// Consumers use this as an invalidation signal and fetch history through\n  /// `/messages`; raw sync events intentionally never enter the history LRU.\n  final MatrixRoomUpdateBus roomUpdates = MatrixRoomUpdateBus();\n\n''',
)
replace_once(
    'lib/services/matrix_client_service.dart',
    '''      final joined = _asMap(rooms['join']);\n      final left = _asMap(rooms['leave']);\n\n      for (final entry in joined.entries) {\n''',
    '''      final joined = _asMap(rooms['join']);\n      final left = _asMap(rooms['leave']);\n      final timelineChangedRooms = <String>{};\n\n      for (final entry in joined.entries) {\n''',
)
replace_once(
    'lib/services/matrix_client_service.dart',
    '''        final timelineEvents = _asList(timeline['events']);\n        final unread = _asMap(roomData['unread_notifications']);\n\n''',
    '''        final timelineEvents = _asList(timeline['events']);\n        if (timelineEvents.isNotEmpty) {\n          timelineChangedRooms.add(roomId);\n        }\n        final unread = _asMap(roomData['unread_notifications']);\n\n''',
)
replace_once(
    'lib/services/matrix_client_service.dart',
    '''      if (nextBatch is String && nextBatch.isNotEmpty) {\n        _syncToken = nextBatch;\n      }\n\n      final result = _roomCache.values.toList(growable: false)\n''',
    '''      if (nextBatch is String && nextBatch.isNotEmpty) {\n        _syncToken = nextBatch;\n      }\n      roomUpdates.publishAll(timelineChangedRooms);\n\n      final result = _roomCache.values.toList(growable: false)\n''',
)
replace_once(
    'lib/services/matrix_client_service.dart',
    '''  void dispose() {\n    _session = null;\n    _resetSyncState();\n    if (_ownsDio) {\n''',
    '''  void dispose() {\n    _session = null;\n    _resetSyncState();\n    roomUpdates.dispose();\n    if (_ownsDio) {\n''',
)

# Room UI: remove the fixed 20-second /messages poll. `/sync` invalidations are
# coalesced while loading/sending/backgrounded/threaded and drained once safe.
replace_once(
    'lib/pages/chat/matrix_room_page.dart',
    '''  static const Duration _typingIdleDelay = Duration(seconds: 5);\n  static const Duration _foregroundRefreshInterval = Duration(seconds: 20);\n''',
    '''  static const Duration _typingIdleDelay = Duration(seconds: 5);\n''',
)
replace_once(
    'lib/pages/chat/matrix_room_page.dart',
    '''  Timer? _typingStopTimer;\n  Timer? _refreshTimer;\n  MatrixMediaService? _mediaService;\n  bool _threadRouteActive = false;\n''',
    '''  Timer? _typingStopTimer;\n  StreamSubscription<String>? _roomUpdateSubscription;\n  MatrixMediaService? _mediaService;\n  bool _threadRouteActive = false;\n  bool _appResumed = true;\n  bool _pendingTimelineRefresh = false;\n''',
)
replace_once(
    'lib/pages/chat/matrix_room_page.dart',
    '''  void initState() {\n    super.initState();\n    WidgetsBinding.instance.addObserver(this);\n    _startForegroundRefresh();\n    unawaited(_loadLatest());\n  }\n\n  @override\n  void didChangeAppLifecycleState(AppLifecycleState state) {\n    if (state == AppLifecycleState.resumed) {\n      if (!_threadRouteActive) {\n        _startForegroundRefresh();\n        unawaited(_refreshLatestSilently());\n      }\n    } else {\n      _stopForegroundRefresh();\n    }\n  }\n\n  @override\n  void dispose() {\n    WidgetsBinding.instance.removeObserver(this);\n    _stopForegroundRefresh();\n    _typingStopTimer?.cancel();\n''',
    '''  void initState() {\n    super.initState();\n    WidgetsBinding.instance.addObserver(this);\n    final lifecycleState = WidgetsBinding.instance.lifecycleState;\n    _appResumed =\n        lifecycleState == null || lifecycleState == AppLifecycleState.resumed;\n    _roomUpdateSubscription = widget.client.roomUpdates\n        .watch(widget.room.roomId)\n        .listen(_handleRoomTimelineUpdate);\n    unawaited(_loadLatest());\n  }\n\n  @override\n  void didChangeAppLifecycleState(AppLifecycleState state) {\n    _appResumed = state == AppLifecycleState.resumed;\n    if (_appResumed && !_threadRouteActive) {\n      _resumePendingTimelineRefresh();\n    }\n  }\n\n  @override\n  void dispose() {\n    WidgetsBinding.instance.removeObserver(this);\n    final roomUpdateSubscription = _roomUpdateSubscription;\n    _roomUpdateSubscription = null;\n    if (roomUpdateSubscription != null) {\n      unawaited(roomUpdateSubscription.cancel());\n    }\n    _typingStopTimer?.cancel();\n''',
)
replace_once(
    'lib/pages/chat/matrix_room_page.dart',
    '''  void _startForegroundRefresh() {\n    if (_threadRouteActive) return;\n    _refreshTimer?.cancel();\n    _refreshTimer = Timer.periodic(\n      _foregroundRefreshInterval,\n      (_) => unawaited(_refreshLatestSilently()),\n    );\n  }\n\n  void _stopForegroundRefresh() {\n    _refreshTimer?.cancel();\n    _refreshTimer = null;\n  }\n\n  Future<void> _refreshLatestSilently() async {\n    if (!mounted ||\n        _threadRouteActive ||\n        _loading ||\n        _loadingOlder ||\n        _sending ||\n        _uploadingMedia ||\n        _refreshingLatest) {\n      return;\n    }\n    await _loadLatest(\n      showSpinner: false,\n      scrollToBottom: false,\n      preservePaginationCursor: true,\n      surfaceErrors: false,\n    );\n  }\n\n''',
    '''  void _handleRoomTimelineUpdate(String roomId) {\n    if (!mounted || roomId != widget.room.roomId) return;\n    _pendingTimelineRefresh = true;\n    _resumePendingTimelineRefresh();\n  }\n\n  bool get _canDrainTimelineRefresh =>\n      mounted &&\n      _appResumed &&\n      !_threadRouteActive &&\n      !_loading &&\n      !_loadingOlder &&\n      !_sending &&\n      !_uploadingMedia &&\n      !_refreshingLatest;\n\n  void _resumePendingTimelineRefresh() {\n    if (!_pendingTimelineRefresh || !_canDrainTimelineRefresh) return;\n    unawaited(_drainPendingTimelineRefresh());\n  }\n\n  Future<void> _drainPendingTimelineRefresh() async {\n    if (!_pendingTimelineRefresh || !_canDrainTimelineRefresh) return;\n    _pendingTimelineRefresh = false;\n    await _loadLatest(\n      showSpinner: false,\n      scrollToBottom: false,\n      preservePaginationCursor: true,\n      surfaceErrors: false,\n    );\n  }\n\n''',
)
replace_once(
    'lib/pages/chat/matrix_room_page.dart',
    '''    } finally {\n      _refreshingLatest = false;\n      if (showSpinner && mounted) setState(() => _loading = false);\n    }\n  }\n\n  Future<void> _loadOlder() async {\n''',
    '''    } finally {\n      _refreshingLatest = false;\n      if (showSpinner && mounted) setState(() => _loading = false);\n      _resumePendingTimelineRefresh();\n    }\n  }\n\n  Future<void> _loadOlder() async {\n''',
)
replace_once(
    'lib/pages/chat/matrix_room_page.dart',
    '''    } finally {\n      if (mounted) setState(() => _loadingOlder = false);\n    }\n  }\n\n  Future<void> _markRead(String eventId) async {\n''',
    '''    } finally {\n      if (mounted) setState(() => _loadingOlder = false);\n      _resumePendingTimelineRefresh();\n    }\n  }\n\n  Future<void> _markRead(String eventId) async {\n''',
)
replace_once(
    'lib/pages/chat/matrix_room_page.dart',
    '''    } finally {\n      if (mounted) setState(() => _sending = false);\n    }\n  }\n\n  MatrixMediaService _mediaFor(MatrixSession session) {\n''',
    '''    } finally {\n      if (mounted) setState(() => _sending = false);\n      _resumePendingTimelineRefresh();\n    }\n  }\n\n  MatrixMediaService _mediaFor(MatrixSession session) {\n''',
)
replace_once(
    'lib/pages/chat/matrix_room_page.dart',
    '''    } finally {\n      if (mounted) {\n        setState(() {\n          _uploadingMedia = false;\n          _uploadProgress = null;\n        });\n      }\n    }\n  }\n\n  static String _formatBytes(int bytes) {\n''',
    '''    } finally {\n      if (mounted) {\n        setState(() {\n          _uploadingMedia = false;\n          _uploadProgress = null;\n        });\n      }\n      _resumePendingTimelineRefresh();\n    }\n  }\n\n  static String _formatBytes(int bytes) {\n''',
)
replace_once(
    'lib/pages/chat/matrix_room_page.dart',
    '''    final mediaService = _mediaFor(session);\n    _threadRouteActive = true;\n    _stopForegroundRefresh();\n    try {\n''',
    '''    final mediaService = _mediaFor(session);\n    _threadRouteActive = true;\n    try {\n''',
)
replace_once(
    'lib/pages/chat/matrix_room_page.dart',
    '''    } finally {\n      _threadRouteActive = false;\n      if (mounted &&\n          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {\n        _startForegroundRefresh();\n        await _loadLatest(\n          showSpinner: false,\n          scrollToBottom: false,\n          preservePaginationCursor: true,\n        );\n      }\n    }\n  }\n''',
    '''    } finally {\n      _threadRouteActive = false;\n      _appResumed =\n          WidgetsBinding.instance.lifecycleState == null ||\n          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;\n      _resumePendingTimelineRefresh();\n    }\n  }\n''',
)

# Replace the old timer-centric widget test with event-driven invalidation tests.
replace_once(
    'test/pages/chat/matrix_room_page_test.dart',
    '''  testWidgets('pauses room polling while a thread route is visible', (\n    tester,\n  ) async {\n    final client = _FakeMatrixClient(withThread: true);\n\n    await tester.pumpWidget(\n      MaterialApp(\n        home: MatrixRoomPage(client: client, room: room),\n      ),\n    );\n    await tester.pump();\n    expect(client.loadPageCalls, 1);\n\n    await tester.tap(find.text('1 条线程回复'));\n    await tester.pumpAndSettle();\n    expect(find.textContaining('Thread ·'), findsOneWidget);\n\n    // The underlying room stays mounted while the Thread route is on top.\n    // Follow Flutter's real lifecycle transition graph so AppLifecycleListener\n    // observers see a valid background -> foreground sequence.\n    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);\n    await tester.pump();\n    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);\n    await tester.pump();\n    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);\n    await tester.pump();\n    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);\n    await tester.pump();\n    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);\n    await tester.pump();\n    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);\n    await tester.pump();\n\n    // The room refresh interval is 20 seconds. Advancing beyond it while the\n    // thread route is visible must not issue another room /messages request.\n    await tester.pump(const Duration(seconds: 21));\n    expect(client.loadPageCalls, 1);\n\n    final navigator = tester.state<NavigatorState>(find.byType(Navigator));\n    navigator.pop();\n    await tester.pumpAndSettle();\n\n    // Returning performs one immediate latest refresh and restarts the timer.\n    expect(client.loadPageCalls, 2);\n\n    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));\n    await tester.pump();\n  });\n''',
    '''  testWidgets('refreshes only for the current room sync invalidation', (\n    tester,\n  ) async {\n    final client = _FakeMatrixClient();\n\n    await tester.pumpWidget(\n      MaterialApp(\n        home: MatrixRoomPage(client: client, room: room),\n      ),\n    );\n    await tester.pump();\n    expect(client.loadPageCalls, 1);\n\n    client.roomUpdates.publish('!other:example.org');\n    await tester.pump();\n    await tester.pump();\n    expect(client.loadPageCalls, 1);\n\n    client.roomUpdates.publish(room.roomId);\n    await tester.pump();\n    await tester.pump();\n    expect(client.loadPageCalls, 2);\n\n    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));\n    await tester.pump();\n  });\n\n  testWidgets('coalesces room invalidations while a thread route is visible', (\n    tester,\n  ) async {\n    final client = _FakeMatrixClient(withThread: true);\n\n    await tester.pumpWidget(\n      MaterialApp(\n        home: MatrixRoomPage(client: client, room: room),\n      ),\n    );\n    await tester.pump();\n    expect(client.loadPageCalls, 1);\n\n    await tester.tap(find.text('1 条线程回复'));\n    await tester.pumpAndSettle();\n    expect(find.textContaining('Thread ·'), findsOneWidget);\n\n    client.roomUpdates.publish(room.roomId);\n    client.roomUpdates.publish(room.roomId);\n    await tester.pump();\n    await tester.pump();\n    expect(client.loadPageCalls, 1);\n\n    final navigator = tester.state<NavigatorState>(find.byType(Navigator));\n    navigator.pop();\n    await tester.pumpAndSettle();\n\n    // Multiple deltas while the thread was open collapse into one refresh.\n    expect(client.loadPageCalls, 2);\n\n    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));\n    await tester.pump();\n  });\n''',
)

print('Matrix event-driven room refresh patch applied successfully')
