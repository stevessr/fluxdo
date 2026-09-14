/// Pure Matrix timeline relation reducer used by the experimental messaging
/// adapters.
///
/// It deliberately does not depend on Dio, Flutter, or matrix-dart-sdk so the
/// same semantics can be exercised by the lightweight REST adapter and by a
/// future Extera-backed provider.
class MatrixReducedMessage {
  const MatrixReducedMessage({
    required this.eventId,
    required this.senderId,
    required this.body,
    required this.timestamp,
    this.msgType,
    this.encrypted = false,
    this.edited = false,
    this.redacted = false,
    this.reactions = const <String, int>{},
  });

  final String eventId;
  final String senderId;
  final String body;
  final DateTime timestamp;
  final String? msgType;
  final bool encrypted;
  final bool edited;
  final bool redacted;
  final Map<String, int> reactions;

  MatrixReducedMessage copyWith({
    String? body,
    String? msgType,
    bool? edited,
    bool? redacted,
    Map<String, int>? reactions,
  }) {
    return MatrixReducedMessage(
      eventId: eventId,
      senderId: senderId,
      body: body ?? this.body,
      timestamp: timestamp,
      msgType: msgType ?? this.msgType,
      encrypted: encrypted,
      edited: edited ?? this.edited,
      redacted: redacted ?? this.redacted,
      reactions: reactions ?? this.reactions,
    );
  }
}

class MatrixTimelineReducer {
  const MatrixTimelineReducer();

  List<MatrixReducedMessage> reduce(Iterable<dynamic> rawEvents) {
    final events = rawEvents
        .map(_asMap)
        .where((event) => event.isNotEmpty)
        .toList(growable: false);

    final redactedEventIds = <String>{};
    for (final event in events) {
      if (event['type'] != 'm.room.redaction') continue;
      final content = _asMap(event['content']);
      final redacts = event['redacts'] ?? content['redacts'];
      if (redacts is String && redacts.isNotEmpty) {
        redactedEventIds.add(redacts);
      }
    }

    final messages = <String, MatrixReducedMessage>{};
    final replacements = <String, _Replacement>{};
    final reactions = <String, Map<String, Set<String>>>{};

    // First collect original messages. Relation events are handled separately
    // so an edit or reaction never becomes a fake timeline message/room preview.
    for (final event in events) {
      final eventId = _eventId(event);
      if (eventId.isEmpty) continue;
      final type = event['type'];
      if (type == 'm.room.encrypted') {
        if (redactedEventIds.contains(eventId)) continue;
        messages[eventId] = MatrixReducedMessage(
          eventId: eventId,
          senderId: _sender(event),
          body: 'Encrypted message (E2EE is not enabled in this experiment yet)',
          timestamp: _timestamp(event),
          encrypted: true,
        );
        continue;
      }
      if (type != 'm.room.message') continue;

      final content = _asMap(event['content']);
      final relation = _asMap(content['m.relates_to']);
      if (relation['rel_type'] == 'm.replace') continue;

      final body = content['body'];
      if (body is! String || body.isEmpty) continue;
      final msgType = content['msgtype'] as String?;
      messages[eventId] = MatrixReducedMessage(
        eventId: eventId,
        senderId: _sender(event),
        body: msgType == 'm.emote' ? '* $body' : body,
        timestamp: _timestamp(event),
        msgType: msgType,
      );
    }

    // Redact original messages without dropping their timeline position.
    for (final eventId in redactedEventIds) {
      final original = messages[eventId];
      if (original == null) continue;
      messages[eventId] = original.copyWith(
        body: 'Message redacted',
        redacted: true,
        reactions: const <String, int>{},
      );
    }

    // Collect replacements. Matrix edits are valid only when sent by the same
    // sender as the target message. If multiple valid edits exist, the latest
    // origin_server_ts wins; event id is the deterministic tie breaker.
    for (final event in events) {
      if (event['type'] != 'm.room.message') continue;
      final eventId = _eventId(event);
      if (eventId.isEmpty || redactedEventIds.contains(eventId)) continue;
      final content = _asMap(event['content']);
      final relation = _asMap(content['m.relates_to']);
      if (relation['rel_type'] != 'm.replace') continue;
      final targetId = relation['event_id'];
      if (targetId is! String || targetId.isEmpty) continue;
      final original = messages[targetId];
      if (original == null || original.redacted) continue;
      if (_sender(event) != original.senderId) continue;

      final newContent = _asMap(content['m.new_content']);
      final replacementBody = newContent['body'];
      if (replacementBody is! String || replacementBody.isEmpty) continue;
      final replacement = _Replacement(
        eventId: eventId,
        body: replacementBody,
        msgType: newContent['msgtype'] as String?,
        timestampMs: _timestampMs(event),
      );
      final current = replacements[targetId];
      if (current == null || replacement.isLaterThan(current)) {
        replacements[targetId] = replacement;
      }
    }

    // Some homeservers bundle the latest replacement in unsigned relations even
    // when that edit event is outside the current /messages chunk. Consume it
    // as a fallback while still validating the sender against the original.
    for (final event in events) {
      final targetId = _eventId(event);
      final original = messages[targetId];
      if (original == null || original.redacted) continue;
      final unsigned = _asMap(event['unsigned']);
      final relationBundle = _asMap(unsigned['m.relations']);
      final bundled = _asMap(relationBundle['m.replace']);
      if (bundled.isEmpty) continue;
      final bundledId = _eventId(bundled);
      if (bundledId.isEmpty || redactedEventIds.contains(bundledId)) continue;
      if (_sender(bundled) != original.senderId) continue;
      final content = _asMap(bundled['content']);
      final newContent = _asMap(content['m.new_content']);
      final replacementBody = newContent['body'];
      if (replacementBody is! String || replacementBody.isEmpty) continue;
      final replacement = _Replacement(
        eventId: bundledId,
        body: replacementBody,
        msgType: newContent['msgtype'] as String?,
        timestampMs: _timestampMs(bundled),
      );
      final current = replacements[targetId];
      if (current == null || replacement.isLaterThan(current)) {
        replacements[targetId] = replacement;
      }
    }

    for (final entry in replacements.entries) {
      final original = messages[entry.key];
      if (original == null) continue;
      final replacement = entry.value;
      final renderedBody = replacement.msgType == 'm.emote'
          ? '* ${replacement.body}'
          : replacement.body;
      messages[entry.key] = original.copyWith(
        body: renderedBody,
        msgType: replacement.msgType,
        edited: true,
      );
    }

    // m.annotation is not assumed to be server-aggregated. Count visible
    // reaction events locally and deduplicate identical sender/key pairs.
    for (final event in events) {
      if (event['type'] != 'm.reaction') continue;
      final reactionEventId = _eventId(event);
      if (reactionEventId.isEmpty || redactedEventIds.contains(reactionEventId)) {
        continue;
      }
      final content = _asMap(event['content']);
      final relation = _asMap(content['m.relates_to']);
      if (relation['rel_type'] != 'm.annotation') continue;
      final targetId = relation['event_id'];
      final key = relation['key'];
      if (targetId is! String || key is! String || key.isEmpty) continue;
      final target = messages[targetId];
      if (target == null || target.redacted) continue;
      final sender = _sender(event);
      reactions
          .putIfAbsent(targetId, () => <String, Set<String>>{})
          .putIfAbsent(key, () => <String>{})
          .add(sender);
    }

    for (final entry in reactions.entries) {
      final original = messages[entry.key];
      if (original == null) continue;
      final counts = <String, int>{};
      for (final reaction in entry.value.entries) {
        if (reaction.value.isNotEmpty) {
          counts[reaction.key] = reaction.value.length;
        }
      }
      messages[entry.key] = original.copyWith(reactions: counts);
    }

    final result = messages.values.toList(growable: false)
      ..sort((a, b) {
        final timestampOrder = a.timestamp.compareTo(b.timestamp);
        if (timestampOrder != 0) return timestampOrder;
        return a.eventId.compareTo(b.eventId);
      });
    return result;
  }

  static String _eventId(Map<String, dynamic> event) =>
      event['event_id'] as String? ?? '';

  static String _sender(Map<String, dynamic> event) =>
      event['sender'] as String? ?? 'unknown';

  static int _timestampMs(Map<String, dynamic> event) {
    final value = event['origin_server_ts'];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static DateTime _timestamp(Map<String, dynamic> event) =>
      DateTime.fromMillisecondsSinceEpoch(_timestampMs(event));

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }
}

class _Replacement {
  const _Replacement({
    required this.eventId,
    required this.body,
    required this.msgType,
    required this.timestampMs,
  });

  final String eventId;
  final String body;
  final String? msgType;
  final int timestampMs;

  bool isLaterThan(_Replacement other) {
    if (timestampMs != other.timestampMs) {
      return timestampMs > other.timestampMs;
    }
    return eventId.compareTo(other.eventId) > 0;
  }
}
