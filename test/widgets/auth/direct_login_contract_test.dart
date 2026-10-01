import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('直接登录自适应契约', () {
    test('默认先尝试无验证码 session，按需再开放 hCaptcha', () {
      final source = File('lib/widgets/auth/webview_login_dialog.dart')
          .readAsStringSync();

      expect(source, contains('bool _initialLoginStarted = false;'));
      expect(source, contains('bool _captchaPrompted = false;'));
      expect(
        source,
        contains(
          'hcaptchaToken: null,\n'
          '          secondFactorToken: null,\n'
          '          secondFactorMethod: 1,',
        ),
      );
      expect(
        source,
        contains('bool _sessionNeedsCaptcha(int status, String body)'),
      );
      expect(source, contains('status == 403'));
    });

    test('验证码 endpoint 关闭时允许无验证码回退且不会循环', () {
      final source = File('lib/widgets/auth/webview_login_dialog.dart')
          .readAsStringSync();

      expect(source, contains('bool _captchaEndpointFallbackUsed = false;'));
      for (final status in const [403, 404, 405, 410]) {
        expect(source, contains('status == $status'));
      }
      expect(
        source,
        contains(
          '_captchaPrompted &&\n'
          '        !_captchaEndpointFallbackUsed',
        ),
        isFalse,
        reason: 'endpoint 回退后不应重新进入验证码循环',
      );
      expect(
        source,
        contains(
          '!_captchaPrompted &&\n'
          '        !_captchaEndpointFallbackUsed',
        ),
      );
    });

    test('Cloudflare 改为真正命中 challenge 时才按需处理', () {
      final loginPage = File('lib/pages/login_page.dart').readAsStringSync();
      final dialog = File('lib/widgets/auth/webview_login_dialog.dart')
          .readAsStringSync();

      expect(loginPage, isNot(contains('_ensureCfClearance')));
      expect(dialog, contains("cfMitigated: s.headers.get('cf-mitigated')"));
      expect(dialog, contains("if (cfMitigated == 'challenge')"));
    });
  });

  group('直接登录二步验证契约', () {
    test('TOTP 与备用码使用 Discourse 标准 method 1/2', () {
      final dialog = File('lib/widgets/auth/two_factor_dialog.dart')
          .readAsStringSync();
      final login = File('lib/widgets/auth/webview_login_dialog.dart')
          .readAsStringSync();

      expect(dialog, contains('totp(1)'));
      expect(dialog, contains('backupCode(2)'));
      expect(
        login,
        contains("'&second_factor_method=' + encodeURIComponent(method)"),
      );
      expect(
        login,
        contains('secondFactorMethod: submission.method.discourseValue'),
      );
    });

    test('识别 Discourse 初次 2FA 的 method/capability 错误响应', () {
      final source = File('lib/services/discourse/_login.dart')
          .readAsStringSync();

      expect(source, contains("case 'invalid_second_factor':"));
      expect(source, contains("case 'invalid_second_factor_method':"));
      expect(source, contains("case 'not_enabled_second_factor_method':"));
      expect(source, contains("body['backup_enabled'] == true"));
      expect(source, contains("body['security_key_enabled'] == true"));
      expect(source, contains("body['totp_enabled'] == true"));
    });

    test('WebAuthn 回退在原生登录弹窗关闭后再导航', () {
      final source = File('lib/pages/login_page.dart').readAsStringSync();

      final flag = source.indexOf('var fallbackToWebLogin = false;');
      final callback = source.indexOf(
        'onUseWebLogin: () => fallbackToWebLogin = true',
      );
      final canceled = source.indexOf(
        'result.status == WebViewLoginStatus.canceled',
      );
      final fallback = source.indexOf(
        'if (fallbackToWebLogin && mounted)',
        canceled,
      );

      expect(flag, greaterThanOrEqualTo(0));
      expect(callback, greaterThan(flag));
      expect(canceled, greaterThan(callback));
      expect(fallback, greaterThan(canceled));
    });
  });
}
