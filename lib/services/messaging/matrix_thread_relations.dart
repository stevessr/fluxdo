/// Returns the recursive relation closure which belongs to a Matrix thread.
///
/// The Matrix spec explicitly warns against querying the relations endpoint
/// with `rel_type=m.thread` when reconstructing a thread because edits,
/// reactions and redactions attached to threaded messages would be filtered
/// out. Callers should request recursive relations without a rel_type filter,
/// then use this helper to keep direct `m.thread` children of [rootEventId] and
/// every relation which descends from those children.
List<Map<String, dynamic>> filterMatrixThreadRelations(
  String rootEventId,
  Iterable<dynamic> rawEvents,
) {
  if (rootEventId.isEmpty) return const <Map<String, dynamic>>[];

  final events = rawEvents
      .map(_asMap)
      .where((event) => event.isNotEmpty)
      .toList(growable: false);
  final includedIds = <String>{};
  final included = <Map<String, dynamic>>[];

  for (final event in events) {
    final content = _asMap(event['content']);
    final relation = _asMap(content['m.relates_to']);
    if (relation['rel_type'] != 'm.thread' ||
        relation['event_id'] != rootEventId) {
      continue;
    }
    included.add(event);
    final eventId = _eventId(event);
    if (eventId != null) includedIds.add(eventId);
  }

  // Relation chains can be more than one level deep (for example a redaction
  // of a reaction to a threaded message), so grow the closure until stable.
  var changed = true;
  while (changed) {
    changed = false;
    for (final event in events) {
      final eventId = _eventId(event);
      if (eventId != null && includedIds.contains(eventId)) continue;
      final targetId = _relationTarget(event);
      if (targetId == null || !includedIds.contains(targetId)) continue;
      included.add(event);
      if (eventId != null) includedIds.add(eventId);
      changed = true;
    }
  }

  return included;
}

String? _relationTarget(Map<String, dynamic> event) {
  if (event['type'] == 'm.room.redaction') {
    final content = _asMap(event['content']);
    final target = event['redacts'] ?? content['redacts'];
    return target is String && target.isNotEmpty ? target : null;
  }
  final relation = _asMap(_asMap(event['content'])['m.relates_to']);
  final target = relation['event_id'];
  return target is String && target.isNotEmpty ? target : null;
}

String? _eventId(Map<String, dynamic> event) {
  final value = event['event_id'];
  return value is String && value.isNotEmpty ? value : null;
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return <String, dynamic>{};
}
