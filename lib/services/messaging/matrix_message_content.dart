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
