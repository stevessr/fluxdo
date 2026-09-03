import 'package:app_icons/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/s.dart';
import '../providers/discourse_providers.dart';
import 'bookmarks_page.dart';
import 'community_account_settings_page.dart';
import 'my_badges_page.dart';
import 'user_invites_page.dart';
import 'user_profile_overview_page.dart' as overview;

/// 用户资料页路由壳。
///
/// Discourse 在用户页顶层导航中直接暴露 badges / preferences / invited，
/// bookmarks 则属于仅本人可见的 activity 数据。这里保留原资料页主体不动，
/// 在路由层补一组移动端友好的用户区导航：公开资料只显示「总结、徽章」，
/// 本人额外显示「收藏、邀请、设置」。
class UserProfilePage extends ConsumerWidget {
  final String username;
  final bool embeddedMode;
  final VoidCallback? onEmbeddedBack;
  final bool parentActive;

  const UserProfilePage({
    super.key,
    required this.username,
    this.embeddedMode = false,
    this.onEmbeddedBack,
    this.parentActive = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider).value;
    final isOwnProfile =
        currentUser != null && currentUser.username == username;
    final canAccessInvites =
        isOwnProfile && (currentUser?.trustLevel ?? 0) >= 3;

    final destinations = <NavigationDestination>[
      NavigationDestination(
        icon: const Icon(Symbols.account_circle_rounded),
        label: context.l10n.userProfile_tabSummary,
      ),
      NavigationDestination(
        icon: const Icon(Symbols.military_tech_rounded),
        label: context.l10n.badge_defaultName,
      ),
    ];
    final actions = <VoidCallback?>[
      null,
      () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MyBadgesPage(username: username),
        ),
      ),
    ];

    if (isOwnProfile) {
      destinations.add(
        NavigationDestination(
          icon: const Icon(Symbols.bookmark_rounded),
          label: context.l10n.profile_myBookmarks,
        ),
      );
      actions.add(
        () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const BookmarksPage()),
        ),
      );

      if (canAccessInvites) {
        destinations.add(
          NavigationDestination(
            icon: const Icon(Symbols.link_rounded),
            label: context.l10n.profile_inviteLinks,
          ),
        );
        actions.add(
          () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => UserInvitesPage(username: username),
            ),
          ),
        );
      }

      destinations.add(
        NavigationDestination(
          icon: const Icon(Symbols.settings_rounded),
          label: context.l10n.profile_settings,
        ),
      );
      actions.add(
        () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const CommunityAccountSettingsPage(),
          ),
        ),
      );
    }

    return Scaffold(
      body: overview.UserProfilePage(
        username: username,
        embeddedMode: embeddedMode,
        onEmbeddedBack: onEmbeddedBack,
        parentActive: parentActive,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: destinations,
        onDestinationSelected: (index) => actions[index]?.call(),
      ),
    );
  }
}
