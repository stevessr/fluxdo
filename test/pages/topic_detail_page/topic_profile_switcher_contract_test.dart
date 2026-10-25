import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File(
    'lib/pages/topic_detail_page/topic_detail_page.dart',
  ).readAsStringSync();

  String section(String start, String end) {
    final begin = source.indexOf(start);
    expect(begin, greaterThanOrEqualTo(0));
    final finish = source.indexOf(end, begin + start.length);
    expect(finish, greaterThan(begin));
    return source.substring(begin, finish);
  }

  test('topic app bars retain their top-right profile switcher', () {
    final search = section(
      'if (searchState.isSearchMode) {',
      '// 正常模式下的 AppBar',
    );
    expect(search, contains('final profileAction = _buildProfileSwitcherAction();'));
    expect(search, contains('if (profileAction != null) profileAction'));

    final workspace = section(
      'PreferredSizeWidget _buildEmbeddedMobileWorkspaceAppBar({',
      'Widget _buildEmbeddedMobileWorkspaceTitle(',
    );
    expect(workspace, contains('final profileAction = _buildProfileSwitcherAction();'));
    expect(workspace, contains('if (profileAction != null) profileAction'));

    final normal = section(
      'List<Widget> _buildAppBarActions({',
      'Widget _buildMoreMenuAction({',
    );
    expect(normal, contains('final profileAction = _buildProfileSwitcherAction();'));
    expect(normal, contains('return [if (profileAction != null) profileAction];'));
    expect(normal, contains('if (profileAction != null) profileAction'));
  });

  test('profile avatar preserves tap and long-press account switching', () {
    final action = section(
      'Widget? _buildProfileSwitcherAction() {',
      '/// 构建 AppBar Actions',
    );
    expect(action, contains('ref.watch(currentUserProvider).value'));
    expect(action, contains('if (currentUser == null) return null;'));
    expect(action, contains('SmartAvatar('));
    expect(action, contains('currentUser.getAvatarUrl()'));
    expect(action, contains('AccountSwitcherSheet.showClassic(context)'));
    expect(action, contains('onLongPress:'));
    expect(action, contains('AccountSwitcherSheet.show('));
    expect(action, contains('AccountQuickSwitcherPlacement.topRight'));
  });
}
