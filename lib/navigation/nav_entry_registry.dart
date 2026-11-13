import 'package:flutter/material.dart';
import 'package:app_icons/app_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/s.dart';
import '../models/user.dart';
import '../modules/mini_apps/mini_app_gallery_page.dart';
import '../pages/ai_bot_conversations_page.dart';
import '../pages/site_info_page.dart';
import '../pages/bookmarks_page.dart';
import '../pages/boards_page.dart';
import '../pages/browsing_history_page.dart';
import '../pages/community_events_page.dart';
import '../pages/drafts_page.dart';
import '../pages/groups_page.dart';
import '../pages/leaderboard_page.dart';
import '../pages/profile_page.dart';
import '../pages/chat/chat_page.dart';
import '../pages/seeking_page.dart';
import '../pages/private_messages_page.dart';
import '../pages/topics_screen.dart';
import '../providers/chat_providers.dart';
import '../providers/discourse_providers.dart';
import '../widgets/common/smart_avatar.dart';
import '../pages/notifications_page.dart';
import 'nav_action_bus.dart';
import 'nav_entry.dart';

/// 注册所有可选底栏入口
///
/// 用户在底栏布局编辑器里从这些里挑选显示哪些、顺序如何。
/// 增加新入口时在 [buildAll] 里追加一条即可。
class NavEntryRegistry {
  NavEntryRegistry._();

  /// 构建完整候选列表
  static List<NavEntry> buildAll() {
    return [
      NavEntry(
        id: NavEntryIds.home,
        kind: NavEntryKind.page,
        iconData: Symbols.home_rounded,
        selectedIconData: Symbols.home_rounded,
        label: (ctx) => ctx.l10n.nav_home,
        pageBuilder: (ctx, isActive) => TopicsScreen(isActive: isActive),
        locked: true,
        defaultInBottomNav: true,
      ),
      NavEntry(
        id: NavEntryIds.boards,
        kind: NavEntryKind.page,
        iconData: Icons.view_kanban_outlined,
        selectedIconData: Icons.view_kanban,
        label: _boardsLabel,
        pageBuilder: (ctx, isActive) => BoardsPage(isActive: isActive),
        defaultInBottomNav: false,
      ),
      NavEntry(
        id: NavEntryIds.miniApps,
        kind: NavEntryKind.page,
        iconData: Symbols.apps_rounded,
        selectedIconData: Symbols.apps_rounded,
        label: (ctx) => ctx.l10n.miniApp_title,
        pageBuilder: (ctx, isActive) =>
            MiniAppGalleryPage(active: isActive, workspace: true),
        defaultInBottomNav: false,
      ),
      NavEntry(
        id: NavEntryIds.chat,
        kind: NavEntryKind.page,
        iconData: Symbols.chat_rounded,
        selectedIconData: Symbols.chat_rounded,
        label: (ctx) => ctx.l10n.nav_chat,
        pageBuilder: (ctx, isActive) => const ChatPage(),
        defaultInBottomNav: true,
        requiresLogin: true,
        // 未读徽章：watch 即激活 chatChannelsProvider（全局非 autoDispose），
        // 使 new-channel / user-tracking-state 订阅随底栏常驻
        customIconBuilder: (ctx, ref) => _chatIcon(ref, selected: false),
        customSelectedIconBuilder: (ctx, ref) => _chatIcon(ref, selected: true),
      ),
      NavEntry(
        id: NavEntryIds.aiBot,
        kind: NavEntryKind.page,
        iconData: Icons.smart_toy_outlined,
        selectedIconData: Icons.smart_toy_rounded,
        label: _aiBotLabel,
        pageBuilder: (ctx, isActive) => const AiBotConversationsPage(),
        defaultInBottomNav: true,
        requiresLogin: true,
      ),
      NavEntry(
        id: NavEntryIds.messages,
        kind: NavEntryKind.page,
        iconData: Symbols.mail_rounded,
        selectedIconData: Symbols.mail_rounded,
        label: (ctx) => ctx.l10n.privateMessages_title,
        pageBuilder: (ctx, isActive) => PrivateMessagesPage(isActive: isActive),
        defaultInBottomNav: false,
        requiresLogin: true,
      ),
      NavEntry(
        id: NavEntryIds.profile,
        kind: NavEntryKind.page,
        iconData: Symbols.person_rounded,
        selectedIconData: Symbols.person_rounded,
        label: (ctx) => ctx.l10n.nav_mine,
        pageBuilder: (ctx, isActive) => ProfilePage(isActive: isActive),
        locked: true,
        defaultInBottomNav: true,
        // 已登录时用用户头像替代默认图标
        customIconBuilder: (ctx, ref) =>
            _profileIcon(ctx, ref, selected: false),
        customSelectedIconBuilder: (ctx, ref) =>
            _profileIcon(ctx, ref, selected: true),
      ),
      NavEntry(
        id: 'leaderboard',
        kind: NavEntryKind.page,
        iconData: Symbols.leaderboard_rounded,
        selectedIconData: Symbols.leaderboard_rounded,
        label: _leaderboardLabel,
        pageBuilder: (ctx, isActive) => LeaderboardPage(isActive: isActive),
        defaultInBottomNav: false,
      ),
      NavEntry(
        id: 'groups',
        kind: NavEntryKind.page,
        iconData: Symbols.groups_rounded,
        selectedIconData: Symbols.groups_rounded,
        label: _groupsLabel,
        pageBuilder: (ctx, isActive) => GroupsPage(isActive: isActive),
        defaultInBottomNav: false,
      ),
      NavEntry(
        id: 'upcoming_events',
        kind: NavEntryKind.page,
        iconData: Symbols.calendar_today_rounded,
        selectedIconData: Symbols.calendar_today_rounded,
        label: (ctx) => _communityEventLabel(ctx, CommunityEventsView.upcoming),
        pageBuilder: (ctx, isActive) =>
            const CommunityEventsPage(view: CommunityEventsView.upcoming),
        defaultInBottomNav: false,
        requiresLogin: true,
      ),
      NavEntry(
        id: 'anniversaries',
        kind: NavEntryKind.page,
        iconData: Symbols.celebration_rounded,
        selectedIconData: Symbols.celebration_rounded,
        label: (ctx) =>
            _communityEventLabel(ctx, CommunityEventsView.anniversaries),
        pageBuilder: (ctx, isActive) =>
            const CommunityEventsPage(view: CommunityEventsView.anniversaries),
        defaultInBottomNav: false,
        requiresLogin: true,
      ),
      NavEntry(
        id: NavEntryIds.bookmarks,
        kind: NavEntryKind.page,
        iconData: Symbols.bookmark_rounded,
        selectedIconData: Symbols.bookmark_rounded,
        label: (ctx) => ctx.l10n.nav_bookmarks,
        pageBuilder: (ctx, isActive) => BookmarksPage(isActive: isActive),
        requiresLogin: true,
      ),
      NavEntry(
        id: NavEntryIds.history,
        kind: NavEntryKind.page,
        iconData: Symbols.history_rounded,
        selectedIconData: Symbols.history_rounded,
        label: (ctx) => ctx.l10n.nav_history,
        pageBuilder: (ctx, isActive) => BrowsingHistoryPage(isActive: isActive),
        requiresLogin: true,
      ),
      NavEntry(
        id: NavEntryIds.drafts,
        kind: NavEntryKind.page,
        iconData: Symbols.drafts_rounded,
        selectedIconData: Symbols.drafts_rounded,
        label: (ctx) => ctx.l10n.nav_drafts,
        pageBuilder: (ctx, isActive) => DraftsPage(isActive: isActive),
        requiresLogin: true,
      ),
      NavEntry(
        id: NavEntryIds.seeking,
        kind: NavEntryKind.page,
        iconData: Symbols.visibility_rounded,
        selectedIconData: Symbols.visibility_rounded,
        label: (ctx) => ctx.l10n.seeking_title,
        pageBuilder: (ctx, isActive) => SeekingPage(isActive: isActive),
        requiresLogin: true,
      ),
      NavEntry(
        id: NavEntryIds.notifications,
        kind: NavEntryKind.page,
        iconData: Symbols.notifications_rounded,
        selectedIconData: Symbols.notifications_rounded,
        label: (ctx) => ctx.l10n.nav_notifications,
        pageBuilder: (ctx, isActive) => const NotificationsPage(),
        requiresLogin: true,
      ),
      NavEntry(
        id: 'site_about',
        kind: NavEntryKind.page,
        iconData: Symbols.info_rounded,
        selectedIconData: Symbols.info_rounded,
        label: _siteAboutLabel,
        pageBuilder: (ctx, isActive) => SiteInfoPage(isActive: isActive),
        defaultInBottomNav: false,
      ),
    ];
  }

  /// Map legacy saved navigation IDs to the single site information entry.
  /// Retain compatibility with users who pinned a policy in older versions.
  static String canonicalId(String id) {
    if (id == 'birthdays') return 'anniversaries';
    if (id == 'site_guidelines' ||
        id == 'site_terms' ||
        id == 'site_privacy') {
      return 'site_about';
    }
    return id;
  }

  /// 按 id 查找 entry
  static NavEntry? byId(String id) {
    final resolved = canonicalId(id);
    for (final e in buildAll()) {
      if (e.id == resolved) return e;
    }
    return null;
  }

  /// 根据用户登录状态过滤可用 entry
  static bool isAvailable(NavEntry entry, User? user) {
    if (!entry.requiresLogin) return true;
    return user != null;
  }

  /// 默认底栏 id 列表
  static List<String> defaultBottomNavIds() {
    return buildAll()
        .where((e) => e.defaultInBottomNav)
        .map((e) => e.id)
        .toList();
  }

  /// 必须包含的 locked id 列表
  static List<String> lockedIds() {
    return buildAll().where((e) => e.locked).map((e) => e.id).toList();
  }

  /// 桌面固定首页和广场，其余沿用用户导航配置，不回写移动端底栏偏好。
  static List<NavEntry> desktopEntries(List<NavEntry> entries) => [
    byId(NavEntryIds.home)!,
    byId(NavEntryIds.miniApps)!,
    ...entries.where(
      (entry) =>
          entry.id != NavEntryIds.home && entry.id != NavEntryIds.miniApps,
    ),
  ];
}

String _boardsLabel(BuildContext context) {
  final locale = Localizations.localeOf(context);
  return locale.languageCode == 'zh' ? '看板' : 'Boards';
}

String _leaderboardLabel(BuildContext context) {
  final locale = Localizations.localeOf(context);
  return locale.languageCode == 'zh' ? '排行榜' : 'Leaderboard';
}

String _siteAboutLabel(BuildContext context) {
  final locale = Localizations.localeOf(context);
  return locale.languageCode == 'zh' ? '关于' : 'About';
}

String _groupsLabel(BuildContext context) {
  final locale = Localizations.localeOf(context);
  return locale.languageCode == 'zh' ? '群组' : 'Groups';
}

String _aiBotLabel(BuildContext context) {
  final locale = Localizations.localeOf(context);
  return locale.languageCode == 'zh' ? 'AI 聊天' : 'AI Chat';
}

String _communityEventLabel(BuildContext context, CommunityEventsView view) {
  final zh = Localizations.localeOf(context).languageCode == 'zh';
  return switch (view) {
    CommunityEventsView.upcoming => zh ? '近期活动' : 'Upcoming events',
    CommunityEventsView.anniversaries =>
      zh ? '纪念日与生日' : 'Anniversaries & Birthdays',
    CommunityEventsView.birthdays => zh ? '生日' : 'Birthdays',
  };
}

/// 聊天入口图标：未读总数 > 0 时叠角标。
Widget _chatIcon(WidgetRef ref, {required bool selected}) {
  final unread = ref.watch(chatUnreadProvider);
  final icon = Icon(Symbols.chat_rounded, fill: selected ? 1 : 0);
  if (unread <= 0) return icon;
  return Badge(label: Text(unread > 99 ? '99+' : '$unread'), child: icon);
}

Widget _profileIcon(
  BuildContext context,
  WidgetRef ref, {
  required bool selected,
}) {
  final user = ref.watch(currentUserProvider).value;
  final avatarUrl = user?.getAvatarUrl();
  final hasAvatar = avatarUrl != null && avatarUrl.isNotEmpty;
  if (hasAvatar) {
    return SmartAvatar(
      imageUrl: avatarUrl,
      radius: 12,
      fallbackText: user?.username,
    );
  }
  return Icon(Symbols.person_rounded, fill: selected ? 1 : 0);
}
