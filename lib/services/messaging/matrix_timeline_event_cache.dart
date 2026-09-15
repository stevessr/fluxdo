import 'dart:collection';

/// Bounded in-memory cache for raw Matrix timeline events.
///
/// Relation reduction needs raw edits/reactions to stay available while their
/// target messages are loaded across pagination boundaries, but keeping every
/// visited room forever can grow without bound. This cache keeps only a small
/// LRU set of rooms and caps the number of raw events retained per room.
class MatrixTimelineEventCache {
  MatrixTimelineEventCache({
    this.maxRooms = 6,
    this.maxEventsPerRoom = 1200,
  }) : assert(maxRooms > 0),
       assert(maxEventsPerRoom > 0);

  final int maxRooms;
  final int maxEventsPerRoom;

  final LinkedHashMap<String, LinkedHashMap<String, Map<String, dynamic>>>
  _rooms = LinkedHashMap<String, LinkedHashMap<String, Map<String, dynamic>>>();

  /// Adds or replaces raw events for [roomId] and marks the room as recently
  /// used. Events without a usable `event_id` are ignored.
  void addAll(String roomId, Iterable<dynamic> rawEvents) {
    final room = _touchRoom(roomId);
    for (final raw in rawEvents) {
      final event = _asMap(raw);
      final eventId = event['event_id'];
      if (eventId is! String || eventId.isEmpty) continue;

      // Re-inserting an existing key moves it to the newest edge, which makes
      // duplicate pages harmless while keeping recently observed relations.
      room.remove(eventId);
      room[eventId] = event;
    }
    _trimRoom(room);
  }

  Iterable<Map<String, dynamic>> eventsFor(String roomId) {
    final room = _rooms.remove(roomId);
    if (room == null) return const <Map<String, dynamic>>[];
    _rooms[roomId] = room;
    return List<Map<String, dynamic>>.unmodifiable(room.values);
  }

  void removeRoom(String roomId) => _rooms.remove(roomId);

  void removeWhere(bool Function(String roomId) test) {
    _rooms.removeWhere((roomId, _) => test(roomId));
  }

  void clear() => _rooms.clear();

  int eventCount(String roomId) => _rooms[roomId]?.length ?? 0;

  int get roomCount => _rooms.length;

  LinkedHashMap<String, Map<String, dynamic>> _touchRoom(String roomId) {
    final existing = _rooms.remove(roomId);
    final room = existing ?? LinkedHashMap<String, Map<String, dynamic>>();
    _rooms[roomId] = room;

    while (_rooms.length > maxRooms) {
      _rooms.remove(_rooms.keys.first);
    }
    return room;
  }

  void _trimRoom(LinkedHashMap<String, Map<String, dynamic>> room) {
    while (room.length > maxEventsPerRoom) {
      room.remove(room.keys.first);
    }
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }
}
