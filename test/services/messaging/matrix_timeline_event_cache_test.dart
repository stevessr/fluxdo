import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/messaging/matrix_timeline_event_cache.dart';

Map<String, dynamic> event(String id, int ts) => <String, dynamic>{
  'event_id': id,
  'origin_server_ts': ts,
  'type': 'm.room.message',
};

void main() {
  group('MatrixTimelineEventCache', () {
    test('deduplicates event ids and caps per-room events', () {
      final cache = MatrixTimelineEventCache(maxRooms: 3, maxEventsPerRoom: 3);

      cache.addAll('!room:a', <Map<String, dynamic>>[
        event(r'$1', 1),
        event(r'$2', 2),
        event(r'$3', 3),
      ]);
      cache.addAll('!room:a', <Map<String, dynamic>>[
        event(r'$2', 20),
        event(r'$4', 4),
      ]);

      expect(cache.eventCount('!room:a'), 3);
      final ids = cache
          .eventsFor('!room:a')
          .map((value) => value['event_id'])
          .toList();
      expect(ids, <String>[r'$3', r'$2', r'$4']);
      expect(
        cache.eventsFor('!room:a').firstWhere(
          (value) => value['event_id'] == r'$2',
        )['origin_server_ts'],
        20,
      );
    });

    test('evicts least recently used room', () {
      final cache = MatrixTimelineEventCache(maxRooms: 2, maxEventsPerRoom: 10);
      cache.addAll('!a:test', <Map<String, dynamic>>[event(r'$a', 1)]);
      cache.addAll('!b:test', <Map<String, dynamic>>[event(r'$b', 2)]);

      // Touch A so B becomes the least-recently-used room.
      expect(cache.eventsFor('!a:test'), isNotEmpty);
      cache.addAll('!c:test', <Map<String, dynamic>>[event(r'$c', 3)]);

      expect(cache.roomCount, 2);
      expect(cache.eventCount('!a:test'), 1);
      expect(cache.eventCount('!b:test'), 0);
      expect(cache.eventCount('!c:test'), 1);
    });

    test('removeWhere evicts matching room-key families only', () {
      final cache = MatrixTimelineEventCache(maxRooms: 4, maxEventsPerRoom: 10);
      final separator = String.fromCharCode(0);
      final aPrefix = '!a:test$separator';
      final aOne = '${aPrefix}thread-one';
      final aTwo = '${aPrefix}thread-two';
      final bOne = '!b:test${separator}thread-one';

      cache.addAll(aOne, <Map<String, dynamic>>[event(r'$a1', 1)]);
      cache.addAll(aTwo, <Map<String, dynamic>>[event(r'$a2', 2)]);
      cache.addAll(bOne, <Map<String, dynamic>>[event(r'$b1', 3)]);

      cache.removeWhere((key) => key.startsWith(aPrefix));

      expect(cache.eventCount(aOne), 0);
      expect(cache.eventCount(aTwo), 0);
      expect(cache.eventCount(bOne), 1);
      expect(cache.roomCount, 1);
    });

    test('removeRoom and clear release retained events', () {
      final cache = MatrixTimelineEventCache(maxRooms: 2, maxEventsPerRoom: 10);
      cache.addAll('!a:test', <Map<String, dynamic>>[event(r'$a', 1)]);
      cache.addAll('!b:test', <Map<String, dynamic>>[event(r'$b', 2)]);

      cache.removeRoom('!a:test');
      expect(cache.eventCount('!a:test'), 0);
      expect(cache.roomCount, 1);

      cache.clear();
      expect(cache.roomCount, 0);
    });
  });
}
