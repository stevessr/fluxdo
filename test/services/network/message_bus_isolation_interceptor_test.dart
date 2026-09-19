import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/network/flux_request_spec.dart';
import 'package:fluxdo/services/network/interceptors/message_bus_isolation_interceptor.dart';

void main() {
  group('MessageBusIsolationInterceptor path boundary', () {
    test('matches root deployment and canonical default port', () {
      expect(
        MessageBusIsolationInterceptor.isMessageBusRequest(
          Uri.parse('https://forum.example.com:443/message-bus/client/poll'),
          'https://forum.example.com',
        ),
        isTrue,
      );
    });

    test('matches only inside configured relative-url-root', () {
      const baseUrl = 'https://forum.example.com/forum';
      expect(
        MessageBusIsolationInterceptor.isMessageBusRequest(
          Uri.parse('https://forum.example.com/forum/message-bus/client/poll'),
          baseUrl,
        ),
        isTrue,
      );
      expect(
        MessageBusIsolationInterceptor.isMessageBusRequest(
          Uri.parse('https://forum.example.com/message-bus/client/poll'),
          baseUrl,
        ),
        isFalse,
      );
      expect(
        MessageBusIsolationInterceptor.isMessageBusRequest(
          Uri.parse('https://forum.example.com/forum-other/message-bus/poll'),
          baseUrl,
        ),
        isFalse,
      );
    });

    test('rejects different scheme host and port', () {
      const baseUrl = 'https://forum.example.com/forum';
      for (final uri in [
        'http://forum.example.com/forum/message-bus/poll',
        'https://cdn.example.com/forum/message-bus/poll',
        'https://forum.example.com:8443/forum/message-bus/poll',
      ]) {
        expect(
          MessageBusIsolationInterceptor.isMessageBusRequest(
            Uri.parse(uri),
            baseUrl,
          ),
          isFalse,
          reason: uri,
        );
      }
    });
  });

  test('isolation flags disable discourse session side effects', () {
    final extra = <String, dynamic>{FluxRequestKeys.requestTag: 'message-bus'};

    MessageBusIsolationInterceptor.applyIsolationFlags(extra);

    expect(extra[FluxRequestKeys.isSilent], isTrue);
    expect(extra[FluxRequestKeys.skipCsrf], isTrue);
    expect(extra[FluxRequestKeys.skipAuthCheck], isTrue);
    expect(extra[FluxRequestKeys.skipSessionStateSync], isTrue);
    expect(extra[FluxRequestKeys.skipCfChallenge], isTrue);
    expect(extra[FluxRequestKeys.noRecovery], isTrue);
    expect(extra[FluxRequestKeys.skipNetworkLog], isTrue);
    expect(extra[FluxRequestKeys.requestTag], 'message-bus');
  });
}
