/// Compact Matrix room metadata extracted from a `/sync` joined-room payload.
///
/// This helper intentionally avoids extra member/profile requests. For unnamed
/// DMs it uses the `m.heroes` summary returned by `/sync` and derives readable
/// localparts until a richer Matrix SDK provider can supply proper display
/// names/avatars.
class MatrixRoomMetadata {
  const MatrixRoomMetadata({
    required this.name,
    required this.encrypted,
  });

  final String name;
  final bool encrypted;
}

MatrixRoomMetadata resolveMatrixRoomMetadata({
  required String roomId,
  required Map<String, dynamic> roomData,
  String? previousName,
  bool previousEncrypted = false,
}) {
  final state = _asMap(roomData['state']);
  final stateEvents = _asList(state['events']);

  String? explicitName;
  String? canonicalAlias;
  var encrypted = previousEncrypted;

  for (final rawEvent in stateEvents) {
    final event = _asMap(rawEvent);
    final content = _asMap(event['content']);
    switch (event['type']) {
      case 'm.room.name':
        final value = content['name'];
        if (value is String && value.trim().isNotEmpty) {
          explicitName = value.trim();
        }
      case 'm.room.canonical_alias':
        final value = content['alias'];
        if (value is String && value.trim().isNotEmpty) {
          canonicalAlias = value.trim();
        }
      case 'm.room.encryption':
        encrypted = true;
    }
  }

  final summary = _asMap(roomData['summary']);
  final heroes = _asList(summary['m.heroes'])
      .whereType<String>()
      .where((value) => value.isNotEmpty)
      .toList(growable: false);
  final heroName = _heroRoomName(heroes);

  final previousIsUseful = previousName != null &&
      previousName.trim().isNotEmpty &&
      previousName != roomId;

  return MatrixRoomMetadata(
    name: explicitName ??
        canonicalAlias ??
        heroName ??
        (previousIsUseful ? previousName : null) ??
        roomId,
    encrypted: encrypted,
  );
}

String? _heroRoomName(List<String> heroes) {
  if (heroes.isEmpty) return null;
  final labels = heroes.map(_matrixUserLabel).toList(growable: false);
  if (labels.length <= 3) return labels.join(', ');
  return '${labels.take(3).join(', ')} +${labels.length - 3}';
}

String _matrixUserLabel(String userId) {
  if (!userId.startsWith('@')) return userId;
  final colon = userId.indexOf(':');
  if (colon <= 1) return userId;
  final localpart = userId.substring(1, colon);
  return localpart.isEmpty ? userId : localpart;
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return <String, dynamic>{};
}

List<dynamic> _asList(dynamic value) =>
    value is List ? value : const <dynamic>[];
