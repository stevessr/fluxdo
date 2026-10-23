import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/account_manager.dart';
import 'package:fluxdo/services/network/cookie/cookie_jar_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Cold start restores session-only _t from encrypted account snapshot',
    () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({
        'linux_do_username': 'alice',
        'multi_account_snapshot_alice': jsonEncode({
          'version': 2,
          'profile': 'alice',
          'cookies': [
            {
              'name': '_t',
              'value': 'snapshot-session-token',
              'domain': 'linux.do',
              'path': '/',
              'host_only': true,
              'http_only': true,
              'secure': true,
            },
          ],
        }),
      });

      final jar = CookieJarService();
      await jar.initialize();
      await jar.deleteCookie('_t');
      expect(await jar.getTToken(), isNull);

      expect(await AccountManager().restoreColdStartSessionIfMissing(), isTrue);
      expect(await jar.getTToken(), 'snapshot-session-token');
      // Restoring again must not overwrite cookies rotated after startup.
      await jar.setCookie(
        '_t',
        'rotated-session-token',
        httpOnly: true,
        trusted: true,
      );
      expect(await AccountManager().restoreColdStartSessionIfMissing(), isFalse);
      expect(await jar.getTToken(), 'rotated-session-token');
    },
  );
}
