import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/board.dart';
import 'package:fluxdo/models/chat/chat_channel.dart';
import 'package:fluxdo/models/group.dart';
import 'package:fluxdo/models/invite_link.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/models/user.dart';

void main() {
  group('Discourse management compatibility payloads', () {
    test('Board parses granular archive capabilities', () {
      final board = DiscourseBoard.fromJson({
        'id': 7,
        'name': 'Roadmap',
        'unicode_name': 'Roadmap',
        'slug': 'roadmap',
        'archived': true,
        'old_slug_used': true,
        'created_by': {
          'username': 'alice',
          'avatar_template': '/user_avatar/example/alice/{size}/1.png',
        },
        'columns': [
          {
            'id': 2,
            'title': 'Doing',
            'unicode_title': 'Doing',
            'position': 0,
            'default_sort': 'recency',
            'icon': 'hammer',
            'tag_id': 9,
            'tag_name': 'work',
            'move_to_category_id': 42,
            'move_to_assigned': 'alice',
            'move_to_status': 'closed',
            'color': '336699',
            'cards': [
              {
                'id': 3,
                'board_id': 7,
                'column_id': 2,
                'card_type': 'floater',
                'position': 1,
                'inline_onebox_data': {'url': 'https://example.test'},
                'tag_ids': [9, 10],
                'tags': const <Map<String, dynamic>>[],
                'column_changed_at': '2026-10-03T12:00:00.000Z',
              },
            ],
          },
        ],
        'can_manage': false,
        'can_write': false,
        'can_archive': false,
        'can_unarchive': true,
        'acl': [
          {
            'type': 'group',
            'id': 5,
            'permission': 'view',
            'display_name': 'logged_in_users',
          },
          {
            'type': 'group',
            'id': 13,
            'permission': 'manage',
            'display_name': 'trust_level_3',
          },
        ],
      });

      expect(board.archived, isTrue);
      expect(board.oldSlugUsed, isTrue);
      expect(board.createdBy?.username, 'alice');
      expect(board.columns.single.icon, 'hammer');
      expect(board.columns.single.tagId, 9);
      expect(board.columns.single.tagName, 'work');
      expect(board.columns.single.moveToCategoryId, 42);
      expect(board.columns.single.moveToAssigned, 'alice');
      expect(board.columns.single.cards.single.tagIds, [9, 10]);
      expect(
        board.columns.single.cards.single.inlineOneboxData?['url'],
        'https://example.test',
      );
      expect(
        board.columns.single.cards.single.columnChangedAt?.toUtc(),
        DateTime.utc(2026, 10, 3, 12),
      );
      expect(board.canManage, isFalse);
      expect(board.canArchive, isFalse);
      expect(board.canUnarchive, isTrue);
      expect(board.acl, hasLength(2));
      expect(board.acl.first.id, 5);
      expect(board.acl.first.permission, 'view');
      expect(board.acl.last.toJson(), {
        'type': 'group',
        'id': 13,
        'permission': 'manage',
      });
    });

    test('Board falls back to can_manage on older payloads', () {
      final board = DiscourseBoard.fromJson({
        'id': 8,
        'name': 'Legacy',
        'unicode_name': 'Legacy',
        'slug': 'legacy',
        'can_manage': true,
      });

      expect(board.canArchive, isTrue);
      expect(board.canUnarchive, isTrue);
    });

    test('Group requester parser preserves moderation context', () {
      final result = GroupMembersResult.fromJson({
        'members': [
          {
            'id': 42,
            'username': 'alice',
            'name': 'Alice',
            'reason': 'Need access for the project',
            'requested_at': '2026-10-03T12:34:56.000Z',
          },
        ],
        'meta': {'total': 1, 'limit': 50, 'offset': 0},
      });

      expect(result.members, hasLength(1));
      expect(
        result.members.single.requestReason,
        'Need access for the project',
      );
      expect(
        result.members.single.requestedAt?.toUtc(),
        DateTime.utc(2026, 10, 3, 12, 34, 56),
      );
    });

    test('Chat channel capabilities prefer server metadata', () {
      final groupDm = ChatChannel.fromJson({
        'id': 12,
        'chatable_type': 'DirectMessage',
        'chatable': {'group': true, 'users': const <Map<String, dynamic>>[]},
        'meta': {
          'can_flag': false,
          'user_silenced': true,
          'can_moderate': true,
          'can_delete_self': false,
          'can_delete_others': true,
          'can_remove_members': false,
          'can_manage_pins': true,
        },
      });

      expect(groupDm.serverCanFlag, isFalse);
      expect(groupDm.serverUserSilenced, isTrue);
      expect(groupDm.serverCanModerate, isTrue);
      expect(groupDm.serverCanDeleteSelf, isFalse);
      expect(groupDm.serverCanDeleteOthers, isTrue);
      expect(groupDm.serverCanManagePins, isTrue);
      // 服务端 capability 必须覆盖本地 admin/type 推断。
      expect(groupDm.canRemoveMembers(isAdmin: true), isFalse);
    });

    test('Chat member removal keeps legacy fallback without metadata', () {
      final groupDm = ChatChannel.fromJson({
        'id': 13,
        'chatable_type': 'DirectMessage',
        'chatable': {'group': true, 'users': const <Map<String, dynamic>>[]},
      });
      final categoryChannel = ChatChannel.fromJson({
        'id': 14,
        'chatable_type': 'Category',
      });

      expect(groupDm.canRemoveMembers(isAdmin: false), isFalse);
      expect(groupDm.canRemoveMembers(isAdmin: true), isTrue);
      expect(categoryChannel.canRemoveMembers(isAdmin: true), isTrue);
    });

    test('Invite parser accepts flat serializer payload', () {
      final response = InviteLinkResponse.fromJson({
        'id': 15,
        'invite_key': 'abc123',
        'link': 'https://example.test/invites/abc123',
        'description': 'team',
        'email': 'user@example.test',
        'can_delete_invite': true,
        'topics': [
          {
            'id': 21,
            'title': 'Welcome',
            'fancy_title': 'Welcome',
            'slug': 'welcome',
            'posts_count': 3,
          },
        ],
        'groups': [
          {
            'id': 5,
            'name': 'team',
            'full_name': 'Team',
            'user_count': 10,
          },
        ],
        'created_at': '2026-10-03T00:00:00.000Z',
      });

      expect(response.inviteLink, 'https://example.test/invites/abc123');
      expect(response.invite?.id, 15);
      expect(response.invite?.inviteKey, 'abc123');
      expect(response.invite?.description, 'team');
      expect(response.invite?.email, 'user@example.test');
      expect(response.invite?.canDeleteInvite, isTrue);
      expect(response.invite?.topics.single['id'], 21);
      expect(response.invite?.topics.single['slug'], 'welcome');
      expect(response.invite?.groups.single['id'], 5);
      expect(response.invite?.groups.single['name'], 'team');
    });

    test('Post parses staff management state and custom notice raw text', () {
      final post = Post.fromJson({
        'id': 20,
        'username': 'alice',
        'avatar_template': '/user_avatar/example/alice/{size}/1.png',
        'cooked': '<p>Hello</p>',
        'post_number': 2,
        'post_type': 1,
        'can_permanently_delete': true,
        'locked': true,
        'notice': {
          'type': 'custom',
          'raw': 'Staff note',
          'cooked': '<p>Staff note</p>',
        },
      });

      expect(post.canPermanentlyDelete, isTrue);
      expect(post.locked, isTrue);
      final copied = post.copyWith(bookmarked: true);
      expect(copied.canPermanentlyDelete, isTrue);
      expect(copied.locked, isTrue);
      expect(copied, isNot(equals(post)));
      expect(post.notice?.type, 'custom');
      expect(post.notice?.raw, 'Staff note');
    });

    test('Current user parses Boards plugin capabilities', () {
      final user = User.fromJson({
        'id': 1,
        'username': 'admin',
        'trust_level': 4,
        'admin': true,
        'can_manage_boards': true,
        'can_edit_any_boards': true,
      });

      expect(user.admin, isTrue);
      expect(user.canManageBoards, isTrue);
      expect(user.canEditAnyBoards, isTrue);

      final cached = User.fromCacheJson(user.toCacheJson());
      expect(cached.canManageBoards, isTrue);
      expect(cached.canEditAnyBoards, isTrue);
    });
  });
}
