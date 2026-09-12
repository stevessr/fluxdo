class NotificationRoutePayload {
  const NotificationRoutePayload({
    required this.isPrivateMessage,
    required this.topicId,
    this.postNumber,
    this.instanceId,
  });

  final bool isPrivateMessage;
  final int topicId;
  final int? postNumber;

  /// null only for legacy payloads created before multi-instance routing.
  final String? instanceId;

  static String build({
    required String instanceId,
    required int topicId,
    int? postNumber,
    bool isPrivateMessage = false,
  }) {
    final kind = isPrivateMessage ? 'message' : 'topic';
    final encodedInstanceId = Uri.encodeComponent(instanceId);
    final base = 'discourse:v2:$kind:$encodedInstanceId:$topicId';
    return postNumber == null ? base : '$base:$postNumber';
  }

  static NotificationRoutePayload? parse(String payload) {
    if (payload.startsWith('discourse:v2:')) {
      final parts = payload.split(':');
      if (parts.length != 5 && parts.length != 6) return null;
      if (parts[0] != 'discourse' || parts[1] != 'v2') return null;

      final kind = parts[2];
      if (kind != 'topic' && kind != 'message') return null;
      if (parts[3].isEmpty) return null;

      final topicId = int.tryParse(parts[4]);
      final postNumber = parts.length == 6 ? int.tryParse(parts[5]) : null;
      if (topicId == null || (parts.length == 6 && postNumber == null)) {
        return null;
      }

      try {
        final instanceId = Uri.decodeComponent(parts[3]);
        if (instanceId.isEmpty) return null;
        return NotificationRoutePayload(
          isPrivateMessage: kind == 'message',
          instanceId: instanceId,
          topicId: topicId,
          postNumber: postNumber,
        );
      } on FormatException {
        return null;
      }
    }

    // Legacy notifications remain navigable for upgrade compatibility. They do
    // not carry an instance identity, so only newly-created v2 notifications
    // can enforce the multi-instance boundary.
    final isMessage = payload.startsWith('message:');
    if (!isMessage && !payload.startsWith('topic:')) return null;
    final parts = payload.substring(isMessage ? 8 : 6).split(':');
    if (parts.isEmpty || parts.length > 2) return null;
    final topicId = int.tryParse(parts[0]);
    final postNumber = parts.length == 2 ? int.tryParse(parts[1]) : null;
    if (topicId == null || (parts.length == 2 && postNumber == null)) {
      return null;
    }
    return NotificationRoutePayload(
      isPrivateMessage: isMessage,
      topicId: topicId,
      postNumber: postNumber,
    );
  }

  bool belongsToInstance(String currentInstanceId) =>
      instanceId == null || instanceId == currentInstanceId;
}
