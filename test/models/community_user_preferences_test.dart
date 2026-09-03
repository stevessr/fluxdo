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

    test('parses native email and notification preference values', () {
      final preferences = CommunityUserPreferences.fromUserJson({
        'username': 'fish',
        'can_edit': true,
        'user_option': {
          'email_level': 1,
          'email_messages_level': 2,
          'like_notification_frequency': 3,
          'push_notification_level': 2,
          'notification_level_when_replying': 3,
          'include_tl0_in_digests': true,
          'skip_new_user_tips': true,
        },
      });

      expect(preferences.emailLevel, 1);
      expect(preferences.emailMessagesLevel, 2);
      expect(preferences.likeNotificationFrequency, 3);
      expect(preferences.pushNotificationLevel, 2);
      expect(preferences.notificationLevelWhenReplying, 3);
      expect(preferences.includeTl0InDigests, isTrue);
      expect(preferences.skipNewUserTips, isTrue);
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
