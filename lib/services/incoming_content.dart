/// A platform share copied to the app cache while Android's URI grant is valid.
class IncomingAttachment {
  const IncomingAttachment({
    required this.path,
    required this.name,
    required this.isImage,
    this.mimeType = '',
  });

  final String path;
  final String name;
  final bool isImage;
  final String mimeType;

  String get extension => name.split('.').last.toLowerCase();
  bool get isAudio => mimeType.startsWith('audio/') ||
      const {'mp3', 'm4a', 'aac', 'ogg', 'opus', 'flac', 'wav'}.contains(extension);
  bool get isVideo => mimeType.startsWith('video/') ||
      const {'mp4', 'mov', 'mkv', 'webm', 'm4v'}.contains(extension);

  static IncomingAttachment? fromMap(Object? value) {
    if (value is! Map) return null;
    final path = value['path'];
    final name = value['name'];
    if (path is! String || path.isEmpty || name is! String || name.isEmpty) {
      return null;
    }
    return IncomingAttachment(
      path: path,
      name: name,
      isImage: value['image'] == true,
      mimeType: value['mimeType'] is String ? value['mimeType'] as String : '',
    );
  }
}

class IncomingContent {
  const IncomingContent({required this.action, this.title = '', this.text = '', this.attachments = const [], this.skippedFiles = 0});

  final String action;
  final String title;
  final String text;
  final List<IncomingAttachment> attachments;
  final int skippedFiles;

  static IncomingContent? fromMap(Object? value) {
    if (value is! Map) return null;
    final action = value['action'];
    if (action is! String || !const {'share', 'topic', 'message', 'search'}.contains(action)) return null;
    return IncomingContent(
      action: action,
      title: (value['title'] is String ? value['title'] as String : '').trim(),
      text: value['text'] is String ? value['text'] as String : '',
      skippedFiles: value['skippedFiles'] is int ? (value['skippedFiles'] as int).clamp(0, 1000) : 0,
      attachments: value['files'] is List
          ? (value['files'] as List)
              .map(IncomingAttachment.fromMap)
              .whereType<IncomingAttachment>()
              .toList(growable: false)
          : const [],
    );
  }
}
