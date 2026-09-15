/// Applies Matrix reply/thread relation metadata to [content].
///
/// Rich replies intentionally do not use `rel_type`. Thread events always
/// point at the thread root and can optionally include a rich-reply fallback
/// for clients which do not render threads.
void attachMatrixRelation(
  Map<String, dynamic> content, {
  String? replyToEventId,
  String? threadRootEventId,
  bool threadFallback = false,
}) {
  if (threadRootEventId != null && threadRootEventId.isNotEmpty) {
    content['m.relates_to'] = <String, dynamic>{
      'rel_type': 'm.thread',
      'event_id': threadRootEventId,
      if (replyToEventId != null && replyToEventId.isNotEmpty)
        'm.in_reply_to': <String, dynamic>{'event_id': replyToEventId},
      if (threadFallback) 'is_falling_back': true,
    };
  } else if (replyToEventId != null && replyToEventId.isNotEmpty) {
    content['m.relates_to'] = <String, dynamic>{
      'm.in_reply_to': <String, dynamic>{'event_id': replyToEventId},
    };
  }
}

/// Builds the content object for an unencrypted Matrix `m.room.message` text
/// event while keeping reply/thread relation semantics in one testable place.
Map<String, dynamic> buildMatrixTextMessageContent(
  String body, {
  String? replyToEventId,
  String? threadRootEventId,
  bool threadFallback = false,
}) {
  final content = <String, dynamic>{'msgtype': 'm.text', 'body': body};
  attachMatrixRelation(
    content,
    replyToEventId: replyToEventId,
    threadRootEventId: threadRootEventId,
    threadFallback: threadFallback,
  );
  return content;
}

/// Builds an unencrypted Matrix attachment event.
///
/// The transport layer only needs to provide the already-uploaded MXC URI and
/// metadata. E2EE attachments deliberately use a different provider because
/// encrypted media uses the `file` object instead of the plaintext `url` field.
Map<String, dynamic> buildMatrixMediaMessageContent({
  required String contentUri,
  required String filename,
  required String contentType,
  required int size,
  String? replyToEventId,
  String? threadRootEventId,
  bool threadFallback = false,
}) {
  final normalizedType = contentType.trim().toLowerCase();
  final msgType = normalizedType.startsWith('image/') ? 'm.image' : 'm.file';
  final safeFilename = filename.trim().isEmpty ? 'attachment' : filename.trim();
  final content = <String, dynamic>{
    'msgtype': msgType,
    'body': safeFilename,
    'filename': safeFilename,
    'url': contentUri,
    'info': <String, dynamic>{
      'mimetype': contentType.trim().isEmpty
          ? 'application/octet-stream'
          : contentType.trim(),
      'size': size < 0 ? 0 : size,
    },
  };
  attachMatrixRelation(
    content,
    replyToEventId: replyToEventId,
    threadRootEventId: threadRootEventId,
    threadFallback: threadFallback,
  );
  return content;
}
