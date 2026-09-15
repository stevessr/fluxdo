import 'package:fluxdo/services/matrix_client_service.dart';
import 'package:fluxdo/services/messaging/matrix_media_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const session = MatrixSession(
    homeserver: 'https://client.example/base',
    accessToken: 'secret-token',
    userId: '@alice:example.org',
  );

  group('MatrixMediaService', () {
    test('parses normal and port-bearing mxc URIs', () {
      final normal = MatrixMediaService.parseMxcUri(
        'mxc://media.example/abc123',
      );
      expect(normal?.serverName, 'media.example');
      expect(normal?.mediaId, 'abc123');

      final withPort = MatrixMediaService.parseMxcUri(
        'mxc://media.example:8448/abc123',
      );
      expect(withPort?.serverName, 'media.example:8448');
      expect(withPort?.mediaId, 'abc123');
    });

    test('rejects malformed or ambiguous mxc URIs', () {
      expect(MatrixMediaService.parseMxcUri('https://media.example/a'), isNull);
      expect(MatrixMediaService.parseMxcUri('mxc://media.example/a/b'), isNull);
      expect(MatrixMediaService.parseMxcUri('mxc://user@media.example/a'), isNull);
      expect(MatrixMediaService.parseMxcUri('mxc://media.example/a?x=1'), isNull);
      expect(MatrixMediaService.parseMxcUri('mxc://media.example/a#fragment'), isNull);
    });

    test('builds authenticated client media download endpoint', () {
      final service = MatrixMediaService(session: session);
      final uri = service.downloadUri(
        'mxc://media.example:8448/abc123',
        filename: 'photo 1.jpg',
      );

      expect(uri.scheme, 'https');
      expect(uri.host, 'client.example');
      expect(uri.pathSegments, <String>[
        'base',
        '_matrix',
        'client',
        'v1',
        'media',
        'download',
        'media.example:8448',
        'abc123',
        'photo 1.jpg',
      ]);
      expect(service.authorizationHeaders['Authorization'], 'Bearer secret-token');
      expect(uri.query, isEmpty);
    });

    test('builds bounded authenticated thumbnail endpoint', () {
      final service = MatrixMediaService(session: session);
      final uri = service.thumbnailUri(
        'mxc://media.example:8448/abc123',
        width: 9000,
        height: 1,
        method: 'crop',
        animated: true,
      );

      expect(uri.pathSegments, <String>[
        'base',
        '_matrix',
        'client',
        'v1',
        'media',
        'thumbnail',
        'media.example:8448',
        'abc123',
      ]);
      expect(uri.queryParameters, <String, String>{
        'width': '2048',
        'height': '32',
        'method': 'crop',
        'animated': 'true',
      });
      expect(uri.queryParameters.containsKey('access_token'), isFalse);
    });
  });
}
