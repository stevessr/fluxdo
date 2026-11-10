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

  test('目录简介优先使用 bio_excerpt 并去除 HTML 标签', () {
    final group = DiscourseGroup.fromJson({
      'id': 105,
      'name': 'g-s-linux-desktop',
      'full_name': 'g/桌面GNU/Linux',
      'bio_excerpt': '【桌面GNU/Linux】版块群组 <a href="https://gnu.org">GNU &amp; 自由软件</a>',
      'bio_cooked': '<p>这是备用的简介</p>',
      'flair_url': 'https://example.com/group.svg',
      'flair_bg_color': '3369FF',
    });

    expect(group.bioPreview, '【桌面GNU/Linux】版块群组 GNU & 自由软件');
    expect(group.flairUrl, 'https://example.com/group.svg');
    final copy = group.copyWith(isGroupUser: true);
    expect(copy.bioPreview, group.bioPreview);
  });

  test('目录简介缺失时使用 bio_cooked 并保留换行语义', () {
    final group = DiscourseGroup.fromJson({
      'id': 90,
      'name': 'g-adsfree',
      'bio_cooked': '<p>加入群组</p><p>进出自由<br>尊重态度</p>',
    });
    expect(group.bioPreview, '加入群组 进出自由 尊重态度');
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
