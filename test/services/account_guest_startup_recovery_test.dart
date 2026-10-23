import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/account_manager.dart';
import 'package:fluxdo/services/network/cookie/cookie_jar_service.dart';
import 'package:fluxdo/services/storage/resilient_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Guest marker without an active account remains guest', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({
      'multi_account_guest_mode': '1',
    });

    expect(await AccountManager().isGuestSession(), isTrue);
  });

  test('Cold start repairs stale guest marker when identity and _t survive',
      () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({
      'multi_account_guest_mode': '1',
      'linux_do_username': 'alice',
      'multi_account_pending_new_login': 'old-user',
    });
    final jar = CookieJarService();
    await jar.initialize();
    await jar.setCookie(
      '_t',
      'persisted-session-token',
      httpOnly: true,
      trusted: true,
    );

    expect(await AccountManager().isGuestSession(), isFalse);
    final storage = ResilientSecureStorage();
    // Recovery cleanup is queued behind other account operations. Wait for
    // the automatic deletion rather than assuming it finished synchronously.
    await Future.doWhile(() async {
      if (await storage.read(key: 'multi_account_guest_mode') == null) {
        return false;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
      return true;
    }).timeout(const Duration(seconds: 3));
    expect(await storage.read(key: 'multi_account_guest_mode'), isNull);
    expect(await storage.read(key: 'multi_account_pending_new_login'), isNull);
    expect(await storage.read(key: 'linux_do_username'), 'alice');
    expect(await jar.getTToken(), 'persisted-session-token');
  });
}
