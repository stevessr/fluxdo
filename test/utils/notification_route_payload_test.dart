import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/utils/notification_route_payload.dart';

void main() {
  test('v2 payload round-trips instance, message kind and post number', () {
    const instanceId = 'site-https%3A%2F%2Fforum.example.com%2Fforum';
    final encoded = NotificationRoutePayload.build(
      instanceId: instanceId,
      topicId: 42,
      postNumber: 7,
      isPrivateMessage: true,
    );

    final parsed = NotificationRoutePayload.parse(encoded);

    expect(parsed, isNotNull);
    expect(parsed!.instanceId, instanceId);
    expect(parsed.isPrivateMessage, isTrue);
    expect(parsed.topicId, 42);
    expect(parsed.postNumber, 7);
    expect(parsed.belongsToInstance(instanceId), isTrue);
    expect(parsed.belongsToInstance('linux-do'), isFalse);
  });

  test('legacy payload remains supported without an instance boundary', () {
    final parsed = NotificationRoutePayload.parse('topic:123:4');

    expect(parsed, isNotNull);
    expect(parsed!.instanceId, isNull);
    expect(parsed.isPrivateMessage, isFalse);
    expect(parsed.topicId, 123);
    expect(parsed.postNumber, 4);
    expect(parsed.belongsToInstance('any-instance'), isTrue);
  });

  test('rejects malformed v2 payload instead of cross-routing', () {
    expect(NotificationRoutePayload.parse('discourse:v2:topic::123'), isNull);
    expect(
      NotificationRoutePayload.parse('discourse:v2:unknown:linux-do:123'),
      isNull,
    );
    expect(
      NotificationRoutePayload.parse('discourse:v2:topic:linux-do:not-a-topic'),
      isNull,
    );
  });
}
