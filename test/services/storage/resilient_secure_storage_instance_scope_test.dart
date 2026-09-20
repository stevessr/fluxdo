import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/config/discourse_instance_runtime.dart';
import 'package:fluxdo/services/storage/resilient_secure_storage.dart';

void main() {
  tearDown(DiscourseInstanceRuntime.reset);

  test('linux.do keeps legacy saved-login credential keys', () {
    final storage = ResilientSecureStorage();

    expect(
      storage.debugStorageKeyFor('login_credential_username'),
      'login_credential_username',
    );
    expect(
      storage.debugStorageKeyFor('login_credential_password'),
      'login_credential_password',
    );
  });

  test('custom Discourse namespaces saved-login credentials', () {
    DiscourseInstanceRuntime.activate(
      instanceId: 'ignored',
      baseUrl: 'https://forum.example.com/forum',
    );
    final storage = ResilientSecureStorage();

    final usernameKey = storage.debugStorageKeyFor('login_credential_username');
    final passwordKey = storage.debugStorageKeyFor('login_credential_password');

    expect(usernameKey, contains('discourse_instance'));
    expect(passwordKey, contains('discourse_instance'));
    expect(usernameKey, isNot('login_credential_username'));
    expect(passwordKey, isNot('login_credential_password'));
  });

  test('unrelated secure-storage keys remain device scoped', () {
    DiscourseInstanceRuntime.activate(
      instanceId: 'ignored',
      baseUrl: 'https://forum.example.com',
    );
    final storage = ResilientSecureStorage();

    expect(storage.debugStorageKeyFor('unrelated_secret'), 'unrelated_secret');
  });
}
