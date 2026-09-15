import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../matrix_client_service.dart';
import 'matrix_message_content.dart';

class MatrixMxcUri {
  const MatrixMxcUri({required this.serverName, required this.mediaId});

  final String serverName;
  final String mediaId;
}

class MatrixMediaUpload {
  const MatrixMediaUpload({
    required this.contentUri,
    required this.filename,
    required this.contentType,
    required this.size,
  });

  final String contentUri;
  final String filename;
  final String contentType;
  final int size;
}

class MatrixMediaException implements Exception {
  const MatrixMediaException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Authenticated Matrix content-repository transport for unencrypted rooms.
///
/// E2EE attachment encryption deliberately does not live here: encrypted rooms
/// must be handled by the future crypto-aware SDK provider instead of silently
/// uploading plaintext bytes.
class MatrixMediaService {
  MatrixMediaService({required this.session, Dio? dio}) : _dio = dio ?? Dio();

  static const int defaultDownloadLimitBytes = 64 * 1024 * 1024;
  static const int defaultThumbnailLimitBytes = 12 * 1024 * 1024;

  final MatrixSession session;
  final Dio _dio;

  Map<String, String> get authorizationHeaders => <String, String>{
    'Authorization': 'Bearer ${session.accessToken}',
  };

  Future<int?> maxUploadBytes() async {
    try {
      final response = await _dio.get<dynamic>(
        '${session.homeserver}/_matrix/client/v1/media/config',
        options: _authorizedOptions(),
      );
      final data = _asMap(response.data);
      final value = data['m.upload.size'];
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '');
    } on DioException catch (error) {
      throw MatrixMediaException(_matrixErrorMessage(error));
    }
  }

  Future<MatrixMediaUpload> upload({
    required Uint8List bytes,
    required String filename,
    required String contentType,
    ProgressCallback? onSendProgress,
  }) {
    return uploadStream(
      stream: Stream<List<int>>.value(bytes),
      length: bytes.length,
      filename: filename,
      contentType: contentType,
      onSendProgress: onSendProgress,
    );
  }

  /// Streams an unencrypted attachment directly into the Matrix media API.
  /// This avoids retaining a second full-file copy in Dart heap for desktop and
  /// mobile file-picker uploads.
  Future<MatrixMediaUpload> uploadStream({
    required Stream<List<int>> stream,
    required int length,
    required String filename,
    required String contentType,
    ProgressCallback? onSendProgress,
  }) async {
    if (length < 0) {
      throw const MatrixMediaException('附件长度不能为负数。');
    }
    final safeFilename = filename.trim().isEmpty ? 'attachment' : filename.trim();
    final safeContentType = contentType.trim().isEmpty
        ? 'application/octet-stream'
        : contentType.trim();

    try {
      final response = await _dio.post<dynamic>(
        '${session.homeserver}/_matrix/media/v3/upload',
        queryParameters: <String, dynamic>{'filename': safeFilename},
        data: stream,
        onSendProgress: onSendProgress,
        options: Options(
          headers: <String, dynamic>{
            ...authorizationHeaders,
            Headers.contentTypeHeader: safeContentType,
            Headers.contentLengthHeader: length,
          },
          responseType: ResponseType.json,
        ),
      );
      final data = _asMap(response.data);
      final contentUri = data['content_uri'];
      if (contentUri is! String || parseMxcUri(contentUri) == null) {
        throw const MatrixMediaException(
          'Matrix media upload 未返回有效的 mxc:// URI。',
        );
      }
      return MatrixMediaUpload(
        contentUri: contentUri,
        filename: safeFilename,
        contentType: safeContentType,
        size: length,
      );
    } on DioException catch (error) {
      throw MatrixMediaException(_matrixErrorMessage(error));
    }
  }

  Future<void> sendUpload(
    String roomId,
    MatrixMediaUpload upload, {
    String? replyToEventId,
    String? threadRootEventId,
    bool threadFallback = false,
  }) async {
    final encodedRoomId = Uri.encodeComponent(roomId);
    final transactionId =
        'fluxdo-media-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
    final isImage = upload.contentType.toLowerCase().startsWith('image/');
    final content = <String, dynamic>{
      'msgtype': isImage ? 'm.image' : 'm.file',
      'body': upload.filename,
      'filename': upload.filename,
      'url': upload.contentUri,
      'info': <String, dynamic>{
        'mimetype': upload.contentType,
        'size': upload.size,
      },
    };
    attachMatrixRelation(
      content,
      replyToEventId: replyToEventId,
      threadRootEventId: threadRootEventId,
      threadFallback: threadFallback,
    );

    try {
      await _dio.put<void>(
        '${session.homeserver}/_matrix/client/v3/rooms/'
        '$encodedRoomId/send/m.room.message/$transactionId',
        data: content,
        options: _authorizedOptions(),
      );
    } on DioException catch (error) {
      throw MatrixMediaException(_matrixErrorMessage(error));
    }
  }

  Uri downloadUri(String contentUri, {String? filename}) {
    final mxc = parseMxcUri(contentUri);
    if (mxc == null) {
      throw MatrixMediaException('无效的 Matrix content URI：$contentUri');
    }

    final base = Uri.parse(session.homeserver);
    final baseSegments = base.pathSegments.where((segment) => segment.isNotEmpty);
    return base.replace(
      pathSegments: <String>[
        ...baseSegments,
        '_matrix',
        'client',
        'v1',
        'media',
        'download',
        mxc.serverName,
        mxc.mediaId,
        if (filename != null && filename.trim().isNotEmpty) filename.trim(),
      ],
      query: null,
      fragment: null,
    );
  }

  Uri thumbnailUri(
    String contentUri, {
    int width = 640,
    int height = 640,
    String method = 'scale',
    bool animated = false,
  }) {
    final mxc = parseMxcUri(contentUri);
    if (mxc == null) {
      throw MatrixMediaException('无效的 Matrix content URI：$contentUri');
    }
    final base = Uri.parse(session.homeserver);
    final baseSegments = base.pathSegments.where((segment) => segment.isNotEmpty);
    return base.replace(
      pathSegments: <String>[
        ...baseSegments,
        '_matrix',
        'client',
        'v1',
        'media',
        'thumbnail',
        mxc.serverName,
        mxc.mediaId,
      ],
      queryParameters: <String, String>{
        'width': width.clamp(32, 2048).toString(),
        'height': height.clamp(32, 2048).toString(),
        'method': method == 'crop' ? 'crop' : 'scale',
        'animated': animated.toString(),
      },
      fragment: null,
    );
  }

  Future<Uint8List> downloadBytes(
    String contentUri, {
    int maxBytes = defaultDownloadLimitBytes,
  }) {
    return _downloadUriBytes(downloadUri(contentUri), maxBytes: maxBytes);
  }

  Future<Uint8List> downloadThumbnailBytes(
    String contentUri, {
    int width = 640,
    int height = 640,
    int maxBytes = defaultThumbnailLimitBytes,
  }) {
    return _downloadUriBytes(
      thumbnailUri(contentUri, width: width, height: height),
      maxBytes: maxBytes,
    );
  }

  Future<Uint8List> _downloadUriBytes(
    Uri uri, {
    required int maxBytes,
  }) async {
    if (maxBytes <= 0) {
      throw const MatrixMediaException('下载大小上限必须大于 0。');
    }
    try {
      final response = await _dio.get<ResponseBody>(
        uri.toString(),
        options: Options(
          headers: authorizationHeaders,
          responseType: ResponseType.stream,
        ),
      );
      final declaredLength = int.tryParse(
        response.headers.value(Headers.contentLengthHeader) ?? '',
      );
      if (declaredLength != null && declaredLength > maxBytes) {
        throw MatrixMediaException(
          'Matrix media 大小 $declaredLength bytes 超过客户端上限 $maxBytes bytes。',
        );
      }
      final body = response.data;
      if (body == null) {
        throw const MatrixMediaException('Matrix media download 返回空内容。');
      }

      final builder = BytesBuilder(copy: false);
      var received = 0;
      await for (final chunk in body.stream) {
        received += chunk.length;
        if (received > maxBytes) {
          throw MatrixMediaException(
            'Matrix media 下载超过客户端上限 $maxBytes bytes，已中止。',
          );
        }
        builder.add(chunk);
      }
      return builder.takeBytes();
    } on DioException catch (error) {
      throw MatrixMediaException(_matrixErrorMessage(error));
    }
  }

  static MatrixMxcUri? parseMxcUri(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        uri.scheme != 'mxc' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      return null;
    }
    final segments = uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    if (segments.length != 1) return null;
    return MatrixMxcUri(
      serverName: uri.authority,
      mediaId: segments.single,
    );
  }

  Options _authorizedOptions() => Options(
    headers: <String, dynamic>{...authorizationHeaders},
  );

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  static String _matrixErrorMessage(DioException error) {
    final data = error.response?.data;
    if (data is Map) {
      final message = data['error'];
      final errcode = data['errcode'];
      if (message is String && message.isNotEmpty) {
        return errcode is String ? '$errcode: $message' : message;
      }
    }
    return error.message ?? 'Matrix media request failed.';
  }
}
