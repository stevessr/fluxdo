import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/qr_login_service.dart';

void main() {
  group('QrLoginService payload codec', () {
    final service = QrLoginService.instance;

    test('encode/parse roundtrip', () {
      final exp = DateTime.utc(2030, 1, 2, 3, 4, 5);
      final payload = QrLoginPayload(
        version: 1,
        token: 'abc.def-token_01',
        username: 'alice',
        expiresAt: exp,
      );
      final raw = service.encodePayload(payload);
      expect(raw.startsWith('fluxdo://qr-login?'), isTrue);

      final parsed = service.parsePayload(raw);
      expect(parsed, isNotNull);
      expect(parsed!.version, 1);
      expect(parsed.token, 'abc.def-token_01');
      expect(parsed.username, 'alice');
      expect(parsed.expiresAt.toUtc(), exp);
    });

    test('reject non fluxdo scheme', () {
      expect(service.parsePayload('https://linux.do/t/1'), isNull);
      expect(service.parsePayload('fluxdo://topic/1'), isNull);
      expect(service.parsePayload('not a uri'), isNull);
    });

    test('requireValidPayload rejects expired', () {
      final exp = DateTime.now().toUtc().subtract(const Duration(seconds: 5));
      final raw = service.encodePayload(
        QrLoginPayload(
          version: 1,
          token: 'tok',
          username: 'bob',
          expiresAt: exp,
        ),
      );
      expect(
        () => service.requireValidPayload(raw),
        throwsA(
          isA<QrLoginException>().having(
            (e) => e.error,
            'error',
            QrLoginError.expired,
          ),
        ),
      );
    });

    test('requireValidPayload rejects bad version', () {
      final exp = DateTime.now().toUtc().add(const Duration(minutes: 2));
      final raw = service.encodePayload(
        QrLoginPayload(
          version: 99,
          token: 'tok',
          username: 'bob',
          expiresAt: exp,
        ),
      );
      expect(
        () => service.requireValidPayload(raw),
        throwsA(
          isA<QrLoginException>().having(
            (e) => e.error,
            'error',
            QrLoginError.unsupportedVersion,
          ),
        ),
      );
    });

    test('requireValidPayload accepts fresh payload', () {
      final exp = DateTime.now().toUtc().add(const Duration(minutes: 2));
      final raw = service.encodePayload(
        QrLoginPayload(
          version: 1,
          token: 'tok',
          username: 'bob',
          expiresAt: exp,
        ),
      );
      final valid = service.requireValidPayload(raw);
      expect(valid.token, 'tok');
      expect(valid.isExpired, isFalse);
    });
  });
}
