import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/l10n/slang/strings.g.dart';
import 'package:fluxdo/models/chat/chat_models.dart';
import 'package:fluxdo/models/user.dart';
import 'package:fluxdo/pages/chat/chat_channel_settings_sheet.dart';
import 'package:fluxdo/pages/chat/chat_message_page.dart';
import 'package:fluxdo/providers/chat_providers.dart';
import 'package:fluxdo/providers/core_providers.dart';
import 'package:fluxdo/providers/theme_provider.dart';
import 'package:fluxdo/services/discourse/discourse_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _groupChannel = ChatChannel(
  id: 42,
  title: '测试群聊',
  chatableType: 'DirectMessage',
  isGroupDm: true,
  following: true,
);

const _channelsState = ChatChannelsState(
  publicChannels: [],
  directMessageChannels: [_groupChannel],
  tracking: {},
);

class _TestChatChannelsNotifier extends ChatChannelsNotifier {
  @override
  Future<ChatChannelsState> build() async => _channelsState;
}

class _TestCurrentUserNotifier extends CurrentUserNotifier {
  @override
  FutureOr<User?> build() => null;
}

class _TestChatMessagesNotifier extends ChatMessagesNotifier {
  _TestChatMessagesNotifier(super.channelId);

  @override
  Future<List<ChatMessage>> build() async {
    resetPagingState();
    return [];
  }
}

class _TestDiscourseService implements DiscourseService {
  @override
  Future<void> reportChatPresence(int channelId) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<Widget> _host({
  required Widget home,
  bool includeMessages = false,
}) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();

  return TranslationProvider(
    child: ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        chatChannelsProvider.overrideWith(_TestChatChannelsNotifier.new),
        currentUserProvider.overrideWith(_TestCurrentUserNotifier.new),
        discourseServiceProvider.overrideWithValue(_TestDiscourseService()),
        if (includeMessages) ...[
          chatMessagesProvider.overrideWith2(_TestChatMessagesNotifier.new),
          chatChannelDetailProvider.overrideWith(
            (ref, channelId) async => _groupChannel,
          ),
        ],
      ],
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocaleUtils.supportedLocales,
        home: home,
      ),
    ),
  );
}

void main() {
  testWidgets('消息页右上角不再显示离开频道的三点菜单', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      await _host(
        includeMessages: true,
        home: const ChatMessagePage(channelId: 42, channelTitle: '测试群聊'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(PopupMenuButton<String>), findsNothing);
    expect(find.byIcon(Icons.more_vert), findsNothing);
    expect(find.byTooltip('频道设置'), findsOneWidget);
  });

  testWidgets('群组设置中的离开操作会先要求二次确认', (tester) async {
    await tester.pumpWidget(
      await _host(
        home: const Scaffold(
          body: ChatChannelSettingsSheet(channelId: 42, channelTitle: '测试群聊'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final leaveAction = find.widgetWithText(ListTile, '离开群聊');
    await tester.scrollUntilVisible(
      leaveAction,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(leaveAction);
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('离开此群聊？你将不再是成员，需要他人再次邀请才能加入。'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '取消'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '离开'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(leaveAction, findsOneWidget);
  });
}
