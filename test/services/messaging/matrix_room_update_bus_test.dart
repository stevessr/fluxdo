import 'dart:async';

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
