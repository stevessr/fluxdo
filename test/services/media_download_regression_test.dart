import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/dio_http_client.dart';
import 'package:fluxdo/utils/url_helper.dart';

class _ImageAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromBytes([1, 2, 3], 200);

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('small image channels accept emoji and both avatar groups', () async {
    final dio = Dio()..httpClientAdapter = _ImageAdapter();
    final client = DioHttpClient.withClients(dio, dio);
    for (final host in ['linux.do', 'cdn.example.org']) {
      for (final group in <String?>[null, 'avatar', 'animatedAvatar']) {
        final bytes = await client.fetchBytes(
          Uri.parse('https://$host/image.png'),
          channel: DownloadChannel.small,
          smallGroup: group,
        ).timeout(const Duration(seconds: 2));
        expect(bytes, [1, 2, 3]);
      }
    }
    dio.close();
  });

  test('secure uploads and short paths are never rewritten to CDN', () {
    UrlHelper.debugSetOverrides(baseUri: '', cdnUrl: 'https://cdn.example.org');
    addTearDown(UrlHelper.debugClearOverrides);
    for (final path in [
      '/uploads/secure-uploads/a.png?signature=123',
      '/uploads/secure-media-uploads/a.png',
      '/uploads/short-url/abc.png',
    ]) {
      expect(UrlHelper.resolveMediaUrl(path), UrlHelper.resolveUrl(path));
    }
    expect(UrlHelper.resolveMediaUrl('uploads/default/a.png'),
        'https://cdn.example.org/uploads/default/a.png');
  });
}
