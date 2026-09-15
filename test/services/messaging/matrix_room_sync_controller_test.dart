import 'dart:async';

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
    expect(
      calls,
      2,
      reason: 'a completed long poll should immediately continue',
    );

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

  test('restart creates a new generation and ignores the old late result', () async {
    final first = Completer<List<MatrixRoomSummary>>();
    final restarted = Completer<List<MatrixRoomSummary>>();
    final steady = Completer<List<MatrixRoomSummary>>();
    final emissions = <List<MatrixRoomSummary>>[];
    var calls = 0;

    final controller = MatrixRoomSyncController(
      pull: ({required timeout, cancelToken}) {
        calls++;
        return switch (calls) {
          1 => first.future,
          2 => restarted.future,
          _ => steady.future,
        };
      },
      onRooms: emissions.add,
    );

    controller.start();
    expect(calls, 1);
    controller.stop();
    controller.start();
    expect(calls, 2);
    expect(controller.isRunning, isTrue);

    restarted.complete(const <MatrixRoomSummary>[roomA]);
    await _flushAsync();
    expect(emissions, hasLength(1));
    expect(emissions.single.single.roomId, roomA.roomId);
    expect(calls, 3, reason: 'the restarted generation should keep long polling');

    first.complete(const <MatrixRoomSummary>[]);
    await _flushAsync();
    expect(
      emissions,
      hasLength(1),
      reason: 'the previous generation must never overwrite restarted sync',
    );

    controller.stop();
    steady.complete(const <MatrixRoomSummary>[]);
    await _flushAsync();
    controller.dispose();
  });
}

Future<void> _flushAsync() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}
