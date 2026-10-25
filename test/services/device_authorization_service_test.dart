import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/device_authorization_service.dart';

void main() {
  group('Discourse device authorization HTTP contract', () {
    test('create and poll use JSON payloads required by Discourse', () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://linux.do'));
      final sent = <RequestOptions>[];
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            sent.add(options);
            if (options.path == '/user-api-key/device.json') {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'device_code': List.filled(64, 'a').join(),
                    'user_code': 'ABCD-EFGH',
                    'verification_uri':
                        'https://linux.do/user-api-key/activate',
                    'verification_uri_with_request': 'https://linux.do/user-api-key/activate?request=abc123_-',
                    'expires_in': 600,
                    'interval': 5,
                  },
                ),
              );
            }
            return handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {'status': 'authorization_pending'},
              ),
            );
          },
        ),
      );

      final device = DeviceAuthorizationService(
        dio,
        publicKeyProvider: () async => 'RSA-TEST-KEY',
        clientIdProvider: () async => 'DEVICE-CLIENT-ID',
      );
      final request = await device.create();
      final status = await device.poll(request);
      expect(status.status, DeviceAuthorizationStatus.pending);
      expect(sent, hasLength(2));
      expect(sent[0].path, '/user-api-key/device.json');
      expect(sent[1].path, '/user-api-key/device/poll.json');
      for (final options in sent) {
        expect(options.method, 'POST');
        expect(options.contentType, Headers.jsonContentType);
        expect(options.data, isA<Map>());
      }
      final create = sent[0].data as Map;
      expect(create['scopes'], 'write');
      expect(create['client_id'], 'DEVICE-CLIENT-ID');
      expect(create['public_key'], 'RSA-TEST-KEY');
      expect(create['expires_in_seconds'], '600');
      expect(create['nonce'], request.nonce);
      expect((sent[1].data as Map)['device_code'], request.deviceCode);
      expect(
        request.verificationUriWithRequest.queryParameters['request'],
        'abc123_-',
      );
    });

    test('rejects altered activation origin and nonstandard ports', () async {
      for (final activation in [
        'https://evil.example/user-api-key/activate?request=abc123_-',
        'https://linux.do:8443/user-api-key/activate?request=abc123_-',
        'https://linux.do/user-api-key/activate?request=invalid!',
      ]) {
        final dio = Dio(BaseOptions(baseUrl: 'https://linux.do'));
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) => handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'device_code': List.filled(64, 'a').join(),
                  'user_code': 'ABCD-EFGH',
                  'verification_uri': 'https://linux.do/user-api-key/activate',
                  'verification_uri_with_request': activation,
                  'expires_in': 600,
                  'interval': 5,
                },
              ),
            ),
          ),
        );
        final service = DeviceAuthorizationService(
          dio,
          publicKeyProvider: () async => 'RSA-TEST-KEY',
          clientIdProvider: () async => 'DEVICE-CLIENT-ID',
        );
        await expectLater(service.create(), throwsFormatException);
      }
    });

    test('does not poll faster than server interval', () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://linux.do'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: {
                'device_code': List.filled(64, 'a').join(),
                'user_code': 'ABCD-EFGH',
                'verification_uri': 'https://linux.do/user-api-key/activate',
                'verification_uri_with_request':
                    'https://linux.do/user-api-key/activate?request=abc123_-',
                'expires_in': 600,
                'interval': 95,
              },
            ),
          ),
        ),
      );
      final service = DeviceAuthorizationService(
        dio,
        publicKeyProvider: () async => 'RSA-TEST-KEY',
        clientIdProvider: () async => 'DEVICE-CLIENT-ID',
      );
      final request = await service.create();
      expect(request.pollInterval, const Duration(seconds: 95));
    });
  });

  group('Discourse device authorization contract', () {
    test('pending approval does not expose credentials', () {
      final response = DeviceAuthorizationPoll.parse({
        'status': 'authorization_pending',
      });
      expect(response.status, DeviceAuthorizationStatus.pending);
      expect(response.encryptedPayload, isNull);
    });

    test('only authorized status may provide an encrypted payload', () {
      final response = DeviceAuthorizationPoll.parse({
        'status': 'authorized',
        'payload': 'BASE64-CIPHERTEXT',
      });
      expect(response.status, DeviceAuthorizationStatus.authorized);
      expect(response.encryptedPayload, 'BASE64-CIPHERTEXT');
    });

    test('missing payload is never treated as successful login', () {
      expect(
        () => DeviceAuthorizationPoll.parse({'status': 'authorized'}),
        throwsFormatException,
      );
    });

    test('denied and expired are terminal states', () {
      expect(
        DeviceAuthorizationPoll.parse({'status': 'access_denied'}).status,
        DeviceAuthorizationStatus.denied,
      );
      expect(
        DeviceAuthorizationPoll.parse({'status': 'expired_token'}).status,
        DeviceAuthorizationStatus.expired,
      );
    });

    test('unknown status and non-JSON responses fail closed', () {
      expect(
        () => DeviceAuthorizationPoll.parse({'status': 'approved'}),
        throwsFormatException,
      );
      expect(
        () => DeviceAuthorizationService.responseMap('not-json'),
        throwsFormatException,
      );
    });

    test('accepts decoded and serialized Discourse response maps', () {
      expect(
        DeviceAuthorizationService.responseMap(
          '{"status":"authorization_pending"}',
        ),
        {'status': 'authorization_pending'},
      );
      expect(
        DeviceAuthorizationService.responseMap({'status': 'expired_token'}),
        {'status': 'expired_token'},
      );
    });
  });
}
