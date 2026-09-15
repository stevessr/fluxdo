from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text()
    if old not in text:
        raise SystemExit(f'anchor not found in {path}: {old[:120]!r}')
    file.write_text(text.replace(old, new, 1))


controller = r'''import 'dart:async';

import 'package:dio/dio.dart';

import '../matrix_client_service.dart';

typedef MatrixRoomSyncPull = Future<List<MatrixRoomSummary>> Function({
  required Duration timeout,
  CancelToken? cancelToken,
});
typedef MatrixRoomsListener = void Function(List<MatrixRoomSummary> rooms);
typedef MatrixRoomSyncErrorListener = void Function(Object error);

/// Drives cancellable Matrix `/sync` long polling without coupling the loop to
/// Flutter widgets. A single controller owns at most one in-flight request.
///
/// The first non-blocking sync stays in [MatrixClientService.loadRooms]; once a
/// `next_batch` token exists this controller can keep asking for deltas with a
/// server-side timeout. [stop] invalidates the generation and cancels the
/// current request, so late responses cannot mutate UI state after logout,
/// backgrounding, or a manual full-sync reset.
class MatrixRoomSyncController {
  MatrixRoomSyncController({
    required MatrixRoomSyncPull pull,
    required MatrixRoomsListener onRooms,
    MatrixRoomSyncErrorListener? onError,
    this.longPollTimeout = const Duration(seconds: 30),
    this.retryDelay = const Duration(seconds: 3),
  }) : _pull = pull,
       _onRooms = onRooms,
       _onError = onError;

  final MatrixRoomSyncPull _pull;
  final MatrixRoomsListener _onRooms;
  final MatrixRoomSyncErrorListener? _onError;
  final Duration longPollTimeout;
  final Duration retryDelay;

  bool _running = false;
  bool _disposed = false;
  int _generation = 0;
  CancelToken? _activeCancelToken;

  bool get isRunning => _running && !_disposed;

  void start() {
    if (_disposed || _running) return;
    _running = true;
    final generation = ++_generation;
    unawaited(_run(generation));
  }

  void stop() {
    if (_disposed && !_running && _activeCancelToken == null) return;
    _running = false;
    _generation++;
    _activeCancelToken?.cancel('Matrix live sync stopped');
    _activeCancelToken = null;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    stop();
  }

  Future<void> _run(int generation) async {
    while (!_disposed && _running && generation == _generation) {
      final cancelToken = CancelToken();
      _activeCancelToken = cancelToken;
      try {
        final rooms = await _pull(
          timeout: longPollTimeout,
          cancelToken: cancelToken,
        );
        if (_disposed || !_running || generation != _generation) return;
        _onRooms(List<MatrixRoomSummary>.unmodifiable(rooms));
      } catch (error) {
        if (cancelToken.isCancelled ||
            _disposed ||
            !_running ||
            generation != _generation) {
          return;
        }
        _onError?.call(error);
        if (retryDelay > Duration.zero) {
          await Future<void>.delayed(retryDelay);
          if (_disposed || !_running || generation != _generation) return;
        }
      } finally {
        if (identical(_activeCancelToken, cancelToken)) {
          _activeCancelToken = null;
        }
      }
    }
  }
}
'''
Path('lib/services/messaging/matrix_room_sync_controller.dart').write_text(controller)

controller_test = r'''import 'dart:async';

import 'package:dio/dio.dart';
import 'package:fluxdo/services/matrix_client_service.dart';
import 'package:fluxdo/services/messaging/matrix_room_sync_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const roomA = MatrixRoomSummary(roomId: '!a:example.org', name: 'A');

  test('long polls repeatedly, publishes rooms and cancels on stop', () async {
    final first = Completer<List<MatrixRoomSummary>>();
    final second = Completer<List<MatrixRoomSummary>>();
    final emissions = <List<MatrixRoomSummary>>[];
    final tokens = <CancelToken>[];
    var calls = 0;

    final controller = MatrixRoomSyncController(
      pull: ({required timeout, cancelToken}) {
        expect(timeout, const Duration(seconds: 30));
        expect(cancelToken, isNotNull);
        tokens.add(cancelToken!);
        calls++;
        return calls == 1 ? first.future : second.future;
      },
      onRooms: emissions.add,
    );

    controller.start();
    controller.start();
    expect(calls, 1, reason: 'start must be idempotent');

    first.complete(const <MatrixRoomSummary>[roomA]);
    await _flushAsync();
    expect(emissions, hasLength(1));
    expect(emissions.single.single.roomId, roomA.roomId);
    expect(calls, 2, reason: 'a completed long poll should immediately continue');

    controller.stop();
    expect(controller.isRunning, isFalse);
    expect(tokens.last.isCancelled, isTrue);

    // A transport that ignores cancellation may still complete later. The
    // generation guard must suppress that stale result.
    second.complete(const <MatrixRoomSummary>[]);
    await _flushAsync();
    expect(emissions, hasLength(1));

    controller.dispose();
  });

  test('reports transport errors and retries without busy-looping', () async {
    final retry = Completer<List<MatrixRoomSummary>>();
    final errors = <Object>[];
    var calls = 0;

    final controller = MatrixRoomSyncController(
      retryDelay: Duration.zero,
      pull: ({required timeout, cancelToken}) {
        calls++;
        if (calls == 1) {
          return Future<List<MatrixRoomSummary>>.error(StateError('offline'));
        }
        return retry.future;
      },
      onRooms: (_) {},
      onError: errors.add,
    );

    controller.start();
    await _flushAsync();
    expect(errors, hasLength(1));
    expect(errors.single, isA<StateError>());
    expect(calls, 2);

    controller.stop();
    retry.complete(const <MatrixRoomSummary>[]);
    await _flushAsync();
    controller.dispose();
  });
}

Future<void> _flushAsync() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}
'''
Path('test/services/messaging/matrix_room_sync_controller_test.dart').write_text(controller_test)

# Matrix client: allow server-side timeout and cancellation.
replace_once(
    'lib/services/matrix_client_service.dart',
    '''  /// Loads joined rooms using Matrix incremental sync.\n  Future<List<MatrixRoomSummary>> loadRooms({bool forceFull = false}) async {\n''',
    '''  /// Loads joined rooms using Matrix incremental sync.\n  ///\n  /// [timeout] is forwarded to the homeserver's `/sync` endpoint. Use zero for\n  /// an immediate/manual refresh and a bounded non-zero duration for long\n  /// polling. [cancelToken] lets page lifecycle and logout abort a blocked sync.\n  Future<List<MatrixRoomSummary>> loadRooms({\n    bool forceFull = false,\n    Duration timeout = Duration.zero,\n    CancelToken? cancelToken,\n  }) async {\n''',
)
replace_once(
    'lib/services/matrix_client_service.dart',
    '''    final queryParameters = <String, dynamic>{\n      'timeout': 0,\n''',
    '''    final timeoutMs = timeout.inMilliseconds.clamp(0, 60000);\n    final queryParameters = <String, dynamic>{\n      'timeout': timeoutMs,\n''',
)
replace_once(
    'lib/services/matrix_client_service.dart',
    '''        queryParameters: queryParameters,\n        options: _authorizedOptions(current),\n      );\n''',
    '''        queryParameters: queryParameters,\n        options: _authorizedOptions(current),\n        cancelToken: cancelToken,\n      );\n''',
)

# Matrix page: lifecycle-aware live sync.
replace_once(
    'lib/pages/chat/matrix_chat_page.dart',
    '''import 'dart:convert';\nimport 'dart:math';\n''',
    '''import 'dart:async';\nimport 'dart:convert';\nimport 'dart:math';\n''',
)
replace_once(
    'lib/pages/chat/matrix_chat_page.dart',
    '''import '../../services/messaging/matrix_homeserver_discovery.dart';\n''',
    '''import '../../services/messaging/matrix_homeserver_discovery.dart';\nimport '../../services/messaging/matrix_room_sync_controller.dart';\n''',
)
replace_once(
    'lib/pages/chat/matrix_chat_page.dart',
    '''class _MatrixChatPageState extends State<MatrixChatPage> {\n''',
    '''class _MatrixChatPageState extends State<MatrixChatPage>\n    with WidgetsBindingObserver {\n''',
)
replace_once(
    'lib/pages/chat/matrix_chat_page.dart',
    '''  final TextEditingController _tokenController = TextEditingController();\n\n  bool _loading = true;\n''',
    '''  final TextEditingController _tokenController = TextEditingController();\n  late final MatrixRoomSyncController _roomSync;\n\n  bool _loading = true;\n  bool _appResumed = true;\n''',
)
replace_once(
    'lib/pages/chat/matrix_chat_page.dart',
    '''  @override\n  void initState() {\n    super.initState();\n    _restore();\n  }\n\n  @override\n  void dispose() {\n    _client.dispose();\n''',
    '''  @override\n  void initState() {\n    super.initState();\n    WidgetsBinding.instance.addObserver(this);\n    final lifecycleState = WidgetsBinding.instance.lifecycleState;\n    _appResumed =\n        lifecycleState == null || lifecycleState == AppLifecycleState.resumed;\n    _roomSync = MatrixRoomSyncController(\n      pull: ({required timeout, cancelToken}) => _client.loadRooms(\n        timeout: timeout,\n        cancelToken: cancelToken,\n      ),\n      onRooms: _handleLiveRooms,\n      onError: _handleLiveSyncError,\n    );\n    unawaited(_restore());\n  }\n\n  @override\n  void didChangeAppLifecycleState(AppLifecycleState state) {\n    _appResumed = state == AppLifecycleState.resumed;\n    if (_appResumed) {\n      _startLiveSync();\n    } else {\n      _roomSync.stop();\n    }\n  }\n\n  @override\n  void dispose() {\n    WidgetsBinding.instance.removeObserver(this);\n    _roomSync.dispose();\n    _client.dispose();\n''',
)
replace_once(
    'lib/pages/chat/matrix_chat_page.dart',
    '''  Future<void> _restore() async {\n''',
    '''  void _handleLiveRooms(List<MatrixRoomSummary> rooms) {\n    if (!mounted || _session == null) return;\n    setState(() {\n      _rooms = rooms;\n      _error = null;\n    });\n  }\n\n  void _handleLiveSyncError(Object error) {\n    if (!mounted || _session == null || !_appResumed) return;\n    setState(() => _error = 'Matrix 实时同步：$error');\n  }\n\n  void _startLiveSync() {\n    if (!mounted || !_appResumed || _session == null) return;\n    _roomSync.start();\n  }\n\n  Future<void> _restore() async {\n''',
)
# _loadRooms always owns the transition between manual immediate sync and live long-poll.
replace_once(
    'lib/pages/chat/matrix_chat_page.dart',
    '''  Future<void> _loadRooms({\n    bool showSpinner = true,\n    bool forceFull = false,\n  }) async {\n    if (_session == null) return;\n''',
    '''  Future<void> _loadRooms({\n    bool showSpinner = true,\n    bool forceFull = false,\n  }) async {\n    if (_session == null) return;\n    _roomSync.stop();\n''',
)
replace_once(
    'lib/pages/chat/matrix_chat_page.dart',
    '''    } finally {\n      if (showSpinner && mounted) setState(() => _loading = false);\n    }\n  }\n\n  Future<void> _logout() async {\n    await _client.logout();\n''',
    '''    } finally {\n      if (showSpinner && mounted) setState(() => _loading = false);\n      _startLiveSync();\n    }\n  }\n\n  Future<void> _logout() async {\n    _roomSync.stop();\n    await _client.logout();\n''',
)
replace_once(
    'lib/pages/chat/matrix_chat_page.dart',
    '''                      '实验性 Matrix：增量 /sync、历史分页、已读、typing、reaction 聚合、edit 与 SSO 已启用；E2EE 仍等待 SDK provider。',\n''',
    '''                      '实验性 Matrix：30 秒可取消长轮询 /sync、历史分页、已读、typing、reaction、edit/redaction 与 SSO 已启用；E2EE 仍等待 SDK provider。',\n''',
)

print('Matrix live sync patch applied successfully')
