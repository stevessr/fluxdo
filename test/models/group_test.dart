import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/group.dart';

void main() {
  group('DiscourseGroup permissions', () {
    test('owner can manage a non-automatic group', () {
      final group = DiscourseGroup.fromJson({
        'id': 1,
        'name': 'fish',
        'is_group_owner': true,
      });
      expect(group.canManageMembers, isTrue);
    });

    test('can_admin_group can manage a non-automatic group', () {
      final group = DiscourseGroup.fromJson({
        'id': 1,
        'name': 'fish',
        'can_admin_group': true,
      });
      expect(group.canManageMembers, isTrue);
    });

    test('automatic groups cannot be manually managed', () {
      final group = DiscourseGroup.fromJson({
        'id': 1,
        'name': 'moderators',
        'automatic': true,
        'is_group_owner': true,
        'can_admin_group': true,
      });
      expect(group.canManageMembers, isFalse);
    });

    test('public admission allows non-members to join', () {
      final group = DiscourseGroup.fromJson({
        'id': 1,
        'name': 'fish',
        'public_admission': true,
        'is_group_user': false,
      });
      expect(group.canJoin, isTrue);
      expect(group.canLeave, isFalse);
    });

    test('public exit allows members to leave', () {
      final group = DiscourseGroup.fromJson({
        'id': 1,
        'name': 'fish',
        'public_exit': true,
        'is_group_user': true,
      });
      expect(group.canJoin, isFalse);
      expect(group.canLeave, isTrue);
    });

    test('membership capabilities require the matching public flag', () {
      final member = DiscourseGroup.fromJson({
        'id': 1,
        'name': 'private-member',
        'is_group_user': true,
      });
      final outsider = DiscourseGroup.fromJson({
        'id': 2,
        'name': 'private-outsider',
        'is_group_user': false,
      });
      expect(member.canLeave, isFalse);
      expect(outsider.canJoin, isFalse);
    });

    test('copyWith updates membership state and count', () {
      final group = DiscourseGroup.fromJson({
        'id': 1,
        'name': 'fish',
        'user_count': 10,
        'public_admission': true,
      });
      final joined = group.copyWith(
        userCount: 11,
        isGroupUser: true,
        isGroupOwner: false,
      );
      expect(joined.userCount, 11);
      expect(joined.isGroupUser, isTrue);
      expect(joined.canJoin, isFalse);
    });
  });

  test('member result marks owners from the owners array', () {
    final result = GroupMembersResult.fromJson({
      'owners': [
        {'id': 2, 'username': 'owner'},
      ],
      'members': [
        {'id': 1, 'username': 'member'},
        {'id': 2, 'username': 'owner'},
      ],
      'meta': {'total': 2, 'limit': 50, 'offset': 0},
    });

    expect(result.members.first.owner, isFalse);
    expect(result.members.last.owner, isTrue);
    expect(result.hasMore, isFalse);
  });
}
