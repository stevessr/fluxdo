/// Builds the content object for an unencrypted Matrix `m.room.message` text
/// event while keeping reply/thread relation semantics in one testable place.
Map<String, dynamic> buildMatrixTextMessageContent(
  String body, {
  String? replyToEventId,
  String? threadRootEventId,
  bool threadFallback = false,
}) {
  final content = <String, dynamic>{'msgtype': 'm.text', 'body': body};

  if (threadRootEventId != null && threadRootEventId.isNotEmpty) {
    content['m.relates_to'] = <String, dynamic>{
      'rel_type': 'm.thread',
      'event_id': threadRootEventId,
      if (replyToEventId != null && replyToEventId.isNotEmpty)
        'm.in_reply_to': <String, dynamic>{'event_id': replyToEventId},
      if (threadFallback) 'is_falling_back': true,
    };
  } else if (replyToEventId != null && replyToEventId.isNotEmpty) {
    // Rich replies are special: they intentionally do not use rel_type.
    content['m.relates_to'] = <String, dynamic>{
      'm.in_reply_to': <String, dynamic>{'event_id': replyToEventId},
    };
  }

  return content;
}
