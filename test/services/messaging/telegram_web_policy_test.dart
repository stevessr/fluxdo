import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/messaging/telegram_web_policy.dart';

void main() {
  group('TelegramWebPolicy', () {
    test('accepts Telegram HTTPS origins', () {
      expect(
        TelegramWebPolicy.isTrustedTopLevelUri(
          Uri.parse('https://web.telegram.org/a/'),
        ),
        isTrue,
      );
      expect(
        TelegramWebPolicy.isTrustedTopLevelUri(
          Uri.parse('https://oauth.telegram.org/auth'),
        ),
        isTrue,
      );
      expect(
        TelegramWebPolicy.isTrustedTopLevelUri(
          Uri.parse('https://telegram.org/'),
        ),
        isTrue,
      );
    });

    test('rejects downgraded and lookalike top-level origins', () {
      for (final value in <String>[
        'http://web.telegram.org/a/',
        'https://telegram.org.evil.example/',
        'https://eviltelegram.org/',
        'https://t.me/example',
        'mailto:user@example.com',
      ]) {
        expect(
          TelegramWebPolicy.isTrustedTopLevelUri(Uri.parse(value)),
          isFalse,
          reason: value,
        );
      }
    });

    test('externalizes untrusted main-frame navigation', () {
      expect(
        TelegramWebPolicy.classify(
          Uri.parse('https://example.com/'),
          isMainFrame: true,
        ),
        TelegramWebNavigationDisposition.external,
      );
      expect(
        TelegramWebPolicy.classify(
          Uri.parse('https://web.telegram.org/a/'),
          isMainFrame: true,
        ),
        TelegramWebNavigationDisposition.embedded,
      );
    });

    test('keeps blob/data downloads inside the trusted WebView engine', () {
      expect(
        TelegramWebPolicy.shouldUseWebViewDownload(
          Uri.parse('blob:https://web.telegram.org/id'),
        ),
        isTrue,
      );
      expect(
        TelegramWebPolicy.shouldUseWebViewDownload(
          Uri.parse('data:application/octet-stream;base64,AA=='),
        ),
        isTrue,
      );
      expect(
        TelegramWebPolicy.shouldUseWebViewDownload(
          Uri.parse('https://example.com/file.zip'),
        ),
        isFalse,
      );
    });

    test('does not interfere with subframe/resource navigation', () {
      expect(
        TelegramWebPolicy.classify(
          Uri.parse('https://cdn.example.com/resource'),
          isMainFrame: false,
        ),
        TelegramWebNavigationDisposition.subframe,
      );
    });
  });
}
