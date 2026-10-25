import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/device_authorization_service.dart';

void main() {
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
        DeviceAuthorizationService.responseMap('{"status":"authorization_pending"}'),
        {'status': 'authorization_pending'},
      );
      expect(
        DeviceAuthorizationService.responseMap({'status': 'expired_token'}),
        {'status': 'expired_token'},
      );
    });
  });
}
