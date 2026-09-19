import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/config/discourse_instance_runtime.dart';
import 'package:fluxdo/modules/ldc_reward/models/ldc_reward_credentials.dart';
import 'package:fluxdo/modules/ldc_reward/providers/ldc_reward_provider.dart';

void main() {
  tearDown(DiscourseInstanceRuntime.reset);

  test('custom Discourse instance cannot execute linux.do LDC rewards', () async {
    DiscourseInstanceRuntime.activate(
      instanceId: 'ignored',
      baseUrl: 'https://forum.example.com',
    );

    final result = await executeReward(
      credentials: const LdcRewardCredentials(
        clientId: 'client',
        clientSecret: 'secret',
      ),
      userId: 1,
      username: 'alice',
      amount: 1,
      topicId: 2,
      postId: 3,
    );

    expect(result.success, isFalse);
    expect(result.errorMsg, contains('LINUX DO'));
  });
}
