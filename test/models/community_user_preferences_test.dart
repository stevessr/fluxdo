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

    test('parses account title primary-group and flair choices', () {
      final preferences = CommunityUserPreferences.fromUserJson({
        'username': 'fish',
        'title': 'Badge title',
        'primary_group_id': '8',
        'flair_group_id': 9,
        '_fluxdo_user_selected_primary_groups': true,
        '_fluxdo_available_badge_titles': ['Badge title', 'Extra badge'],
        'groups': [
          {
            'id': 2,
            'name': 'trust_level_1',
            'automatic': true,
            'title': 'Basic user',
          },
          {
            'id': 3,
            'name': 'moderators',
            'display_name': 'Moderators',
            'automatic': true,
            'title': 'Moderator',
          },
          {'id': 8, 'name': 'builders', 'automatic': false, 'title': 'Builder'},
          {'id': 9, 'name': 'fish', 'automatic': false, 'flair_url': 'star'},
        ],
      });

      expect(preferences.title, 'Badge title');
      expect(preferences.primaryGroupId, 8);
      expect(preferences.flairGroupId, 9);
      expect(
        preferences.availableTitles,
        containsAll([
          'Badge title',
          'Extra badge',
          'Basic user',
          'Moderator',
          'Builder',
        ]),
      );
      expect(preferences.availablePrimaryGroups.map((group) => group.id), [
        3,
        8,
        9,
      ]);
      expect(preferences.availableFlairGroups.map((group) => group.id), [9]);
    });

    test('does not expose primary-group choices when the site gate is off', () {
      final preferences = CommunityUserPreferences.fromUserJson({
        'username': 'fish',
        '_fluxdo_user_selected_primary_groups': false,
        'groups': [
          {'id': 8, 'name': 'builders', 'automatic': false},
        ],
      });

      expect(preferences.availablePrimaryGroups, isEmpty);
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
