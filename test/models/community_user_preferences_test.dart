import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/community_user_preferences.dart';

void main() {
  group('CommunityUserPreferences', () {
    test('prefers the top-level timezone used by current Discourse', () {
      final preferences = CommunityUserPreferences.fromUserJson({
        'username': 'fish',
        'timezone': 'Asia/Shanghai',
        'can_edit': true,
        'user_option': {
          'timezone': 'UTC',
          'email_digests': true,
          'allow_private_messages': false,
        },
      });

      expect(preferences.username, 'fish');
      expect(preferences.timezone, 'Asia/Shanghai');
      expect(preferences.emailDigests, isTrue);
      expect(preferences.allowPrivateMessages, isFalse);
      expect(preferences.canEdit, isTrue);
    });

    test('keeps nested timezone fallback and unknown user options', () {
      final preferences = CommunityUserPreferences.fromUserJson({
        'username': 'fish',
        'can_change_bio': true,
        'user_option': {
          'timezone': 'America/New_York',
          'future_plugin_preference': 'preserved',
        },
      });

      expect(preferences.timezone, 'America/New_York');
      expect(preferences.canChangeBio, isTrue);
      expect(
        preferences.userOptionRaw['future_plugin_preference'],
        'preserved',
      );
    });
  });
}
