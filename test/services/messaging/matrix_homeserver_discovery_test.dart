import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/messaging/matrix_homeserver_discovery.dart';

void main() {
  group('MatrixHomeserverDiscoveryService', () {
    test('extracts server names from Matrix IDs and domains', () {
      expect(
        MatrixHomeserverDiscoveryService.serverNameFromInput(
          '@alice:example.org',
        ),
        'example.org',
      );
      expect(
        MatrixHomeserverDiscoveryService.serverNameFromInput(
          '@alice:example.org:8448',
        ),
        'example.org:8448',
      );
      expect(
        MatrixHomeserverDiscoveryService.serverNameFromInput('example.org'),
        'example.org',
      );
      expect(
        MatrixHomeserverDiscoveryService.serverNameFromInput(
          'https://example.org',
        ),
        isNull,
      );
    });

    test('uses well-known homeserver and validates versions', () async {
      final requested = <Uri>[];
      final service = MatrixHomeserverDiscoveryService.withTransport((uri) async {
        requested.add(uri);
        if (uri.path == '/.well-known/matrix/client') {
          return const MatrixDiscoveryResponse(
            statusCode: 200,
            data: <String, dynamic>{
              'm.homeserver': <String, dynamic>{
                'base_url': 'https://matrix.example.net/',
              },
              'm.identity_server': <String, dynamic>{
                'base_url': 'https://identity.example.net/',
              },
            },
          );
        }
        if (uri.toString() ==
            'https://matrix.example.net/_matrix/client/versions') {
          return const MatrixDiscoveryResponse(
            statusCode: 200,
            data: <String, dynamic>{
              'versions': <String>['v1.11', 'v1.12'],
            },
          );
        }
        return const MatrixDiscoveryResponse(statusCode: 404);
      });

      final result = await service.discover('@alice:example.org');

      expect(result.baseUrl, 'https://matrix.example.net');
      expect(result.serverName, 'example.org');
      expect(
        result.source,
        MatrixHomeserverDiscoverySource.wellKnown,
      );
      expect(result.versions, <String>['v1.11', 'v1.12']);
      expect(result.identityServerBaseUrl, 'https://identity.example.net');
      expect(requested.first.host, 'example.org');
      expect(requested.first.path, '/.well-known/matrix/client');
    });

    test('404 well-known falls back to validated direct HTTPS server', () async {
      final requested = <Uri>[];
      final service = MatrixHomeserverDiscoveryService.withTransport((uri) async {
        requested.add(uri);
        if (uri.path == '/.well-known/matrix/client') {
          return const MatrixDiscoveryResponse(statusCode: 404);
        }
        if (uri.toString() ==
            'https://example.org:8448/_matrix/client/versions') {
          return const MatrixDiscoveryResponse(
            statusCode: 200,
            data: <String, dynamic>{'versions': <String>['v1.12']},
          );
        }
        return const MatrixDiscoveryResponse(statusCode: 500);
      });

      final result = await service.discover('@alice:example.org:8448');

      expect(result.baseUrl, 'https://example.org:8448');
      expect(
        result.source,
        MatrixHomeserverDiscoverySource.directServerName,
      );
      expect(requested.first.toString(),
          'https://example.org/.well-known/matrix/client');
    });

    test('explicit homeserver URL skips well-known and is validated', () async {
      final requested = <Uri>[];
      final service = MatrixHomeserverDiscoveryService.withTransport((uri) async {
        requested.add(uri);
        return const MatrixDiscoveryResponse(
          statusCode: 200,
          data: <String, dynamic>{'versions': <String>['v1.12']},
        );
      });

      final result = await service.discover('https://matrix.example.org/');

      expect(result.baseUrl, 'https://matrix.example.org');
      expect(result.source, MatrixHomeserverDiscoverySource.explicitUrl);
      expect(
        requested.single.toString(),
        'https://matrix.example.org/_matrix/client/versions',
      );
    });

    test('non-404 well-known failures are not silently guessed around', () async {
      final service = MatrixHomeserverDiscoveryService.withTransport((uri) async {
        return const MatrixDiscoveryResponse(statusCode: 503);
      });

      expect(
        () => service.discover('@alice:example.org'),
        throwsA(isA<MatrixHomeserverDiscoveryException>()),
      );
    });

    test('rejects discovered endpoints that are not Matrix homeservers', () async {
      final service = MatrixHomeserverDiscoveryService.withTransport((uri) async {
        if (uri.path == '/.well-known/matrix/client') {
          return const MatrixDiscoveryResponse(
            statusCode: 200,
            data: <String, dynamic>{
              'm.homeserver': <String, dynamic>{
                'base_url': 'https://not-matrix.example',
              },
            },
          );
        }
        return const MatrixDiscoveryResponse(
          statusCode: 200,
          data: <String, dynamic>{'versions': <String>[]},
        );
      });

      expect(
        () => service.discover('@alice:example.org'),
        throwsA(isA<MatrixHomeserverDiscoveryException>()),
      );
    });
  });
}
