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
      expect(request.mode, DeviceAuthorizationMode.cookieLogin);
      expect((sent[1].data as Map)['device_code'], request.deviceCode);
      expect(
        request.verificationUriWithRequest.queryParameters['request'],
        'abc123_-',
      );
    });

    test(
      'native grant verifies User API Key without OTP or old cookies',
      () async {
        final sent = <RequestOptions>[];
        final key = List.filled(64, 'b').join();
        String? persistedUsername;
        String? persistedClientId;
        final dio = Dio(BaseOptions(baseUrl: 'https://linux.do'));
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
              if (options.path == '/session/current.json') {
                return handler.resolve(
                  Response(
                    requestOptions: options,
                    statusCode: 200,
                    data: {
                      'current_user': {'username': 'alice'},
                    },
                  ),
                );
              }
              throw StateError('unexpected endpoint: ${options.path}');
            },
          ),
        );
        final service = DeviceAuthorizationService(
          dio,
          publicKeyProvider: () async => 'RSA-TEST-KEY',
          clientIdProvider: () async => 'DEVICE-CLIENT-ID',
          payloadDecryptor: (payload, nonce) async {
            expect(payload, 'ENCRYPTED-KEY');
            return {'key': key, 'nonce': nonce};
          },
          credentialSaver: (apiKey, clientId, username, expires) async {
            expect(apiKey, key);
            persistedUsername = username;
            persistedClientId = clientId;
          },
        );
        final request = await service.create(
          mode: DeviceAuthorizationMode.readOnly,
        );
        final identity = await service.authorize(request, 'ENCRYPTED-KEY');
        expect(identity.username, 'alice');
        expect(persistedUsername, 'alice');
        expect(persistedClientId, 'DEVICE-CLIENT-ID');
        expect(sent.map((r) => r.path), [
          '/user-api-key/device.json',
          '/session/current.json',
        ]);
        final verification = sent.last;
        expect(verification.method, 'GET');
        expect(verification.headers['User-Api-Key'], key);
        expect(verification.headers['User-Api-Client-Id'], 'DEVICE-CLIENT-ID');
        expect(verification.headers['Cookie'], '');
        expect(verification.extra['skipCookieManager'], true);
      },
    );

    test('native grant rejects unverified API identity', () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://linux.do'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
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
                data: {'current_user': null},
              ),
            );
          },
        ),
      );
      var stored = false;
      final service = DeviceAuthorizationService(
        dio,
        publicKeyProvider: () async => 'RSA-TEST-KEY',
        clientIdProvider: () async => 'DEVICE-CLIENT-ID',
        payloadDecryptor: (payload, nonce) async => {
          'key': List.filled(64, 'b').join(),
          'nonce': nonce,
        },
        credentialSaver: (key, clientId, username, expires) async {
          stored = true;
        },
      );
      final request = await service.create(
        mode: DeviceAuthorizationMode.readOnly,
      );
      await expectLater(
        service.authorize(request, 'ENCRYPTED-KEY'),
        throwsFormatException,
      );
      expect(stored, false);
    });

    test('native write grant mints OTP and revokes temporary key', () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://linux.do'));
      final key = List.filled(64, 'b').join();
      final sent = <RequestOptions>[];
      var revoked = false;
      var persisted = false;
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
            if (options.path == '/session/current.json') {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'current_user': {'username': 'alice'},
                  },
                ),
              );
            }
            throw StateError('unexpected endpoint: ${options.path}');
          },
        ),
      );
      final service = DeviceAuthorizationService(
        dio,
        publicKeyProvider: () async => 'RSA-TEST-KEY',
        clientIdProvider: () async => 'DEVICE-CLIENT-ID',
        payloadDecryptor: (payload, nonce) async => {
          'key': key,
          'nonce': nonce,
        },
        credentialSaver: (key, clientId, username, expires) async {
          persisted = true;
        },
        otpRequester: (authorizedKey, clientId, generation) async {
          expect(authorizedKey, key);
          expect(clientId, 'DEVICE-CLIENT-ID');
          return 'f00d1234';
        },
        keyRevoker: (authorizedKey) async {
          expect(authorizedKey, key);
          revoked = true;
          return true;
        },
      );
      final request = await service.create();
      final identity = await service.authorize(request, 'ENCRYPTED-KEY');
      expect(identity.username, 'alice');
      expect(identity.otp, 'f00d1234');
      expect(persisted, false);
      expect(revoked, true);
      expect((sent.first.data as Map)['scopes'], 'write');
      expect((sent.first.data as Map)['expires_in_seconds'], '600');
      expect(sent.last.headers['Cookie'], '');
      expect(sent.last.headers['User-Api-Client-Id'], 'DEVICE-CLIENT-ID');
    });

    test(
      'write device grant does not fabricate OTP on server denial',
      () async {
        final dio = Dio(BaseOptions(baseUrl: 'https://linux.do'));
        final key = List.filled(64, 'b').join();
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
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
                  data: {
                    'current_user': {'username': 'alice'},
                  },
                ),
              );
            },
          ),
        );
        var revoked = false;
        final service = DeviceAuthorizationService(
          dio,
          publicKeyProvider: () async => 'RSA-TEST-KEY',
          clientIdProvider: () async => 'DEVICE-CLIENT-ID',
          payloadDecryptor: (payload, nonce) async => {
            'key': key,
            'nonce': nonce,
          },
          otpRequester: (key, clientId, generation) async => null,
          keyRevoker: (key) async {
            revoked = true;
            return true;
          },
        );
        final request = await service.create();
        await expectLater(
          service.authorize(request, 'ENCRYPTED-KEY'),
          throwsA(isA<DeviceOtpUnavailableException>()),
        );
        expect(revoked, true);
      },
    );

    test('explicit read-only mode never mints OTP', () async {
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
                data: {
                  'current_user': {'username': 'alice'},
                },
              ),
            );
          },
        ),
      );
      var saved = false;
      final service = DeviceAuthorizationService(
        dio,
        publicKeyProvider: () async => 'RSA-TEST-KEY',
        clientIdProvider: () async => 'DEVICE-CLIENT-ID',
        payloadDecryptor: (payload, nonce) async => {
          'key': List.filled(64, 'b').join(),
          'nonce': nonce,
        },
        credentialSaver: (key, clientId, username, expires) async {
          saved = true;
        },
        otpRequester: (key, clientId, generation) async =>
            throw StateError('Read-only grants must not request OTP'),
      );
      final request = await service.create(
        mode: DeviceAuthorizationMode.readOnly,
      );
      final identity = await service.authorize(request, 'ENCRYPTED-KEY');
      expect(identity.otp, isNull);
      expect(saved, true);
      expect((sent.first.data as Map)['scopes'], 'read');
      expect((sent.first.data as Map)['expires_in_seconds'], '86400');
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
