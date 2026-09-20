import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/config/discourse_instance_runtime.dart';
import 'package:fluxdo/services/account_manager.dart';

void main() {
  tearDown(DiscourseInstanceRuntime.reset);

  test('default instance preserves legacy account preference keys', () {
    expect(
      AccountManager.accountScopedKey('ldc_enabled', 'bob/example'),
      'ldc_enabled::bob%2Fexample',
    );
  });

  test('custom instances namespace the same account id independently', () {
    DiscourseInstanceRuntime.activate(
      instanceId: 'ignored',
      baseUrl: 'https://forum-a.example.com/forum',
    );
    final first = AccountManager.accountScopedKey('feature', 'same-user');

    DiscourseInstanceRuntime.activate(
      instanceId: 'ignored',
      baseUrl: 'https://forum-b.example.com/forum',
    );
    final second = AccountManager.accountScopedKey('feature', 'same-user');

    expect(first, isNot(second));
    expect(first, contains('discourse_instance'));
    expect(second, contains('discourse_instance'));
    expect(first, endsWith('::same-user'));
    expect(second, endsWith('::same-user'));
  });

  test('relative roots participate in account preference namespace', () {
    DiscourseInstanceRuntime.activate(
      instanceId: 'ignored',
      baseUrl: 'https://forum.example.com/Forum',
    );
    final upper = AccountManager.accountScopedKey('feature', 'alice');

    DiscourseInstanceRuntime.activate(
      instanceId: 'ignored',
      baseUrl: 'https://forum.example.com/forum',
    );
    final lower = AccountManager.accountScopedKey('feature', 'alice');

    expect(upper, isNot(lower));
  });
}
