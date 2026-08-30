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
