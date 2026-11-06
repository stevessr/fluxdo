import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/login_ready_coordinator.dart';

void main() {
  group('API Key 登录即时收口', () {
    test('认证就绪同步通知，不等待被阻塞的预加载', () async {
      final pending = Completer<void>();
      final events = <String>[];
      final coordinator = LoginReadyCoordinator(
        hydrateFromHtml: (_) async => false,
        refreshPreloadedData: () {
          events.add('preload');
          return pending.future;
        },
        notifyLoginReady: (token) => events.add('ready:$token'),
      );

      coordinator.finalizeImmediately(token: 'fresh-session');

      expect(events.first, 'ready:fresh-session');
      // The preload is deliberately still pending; UI readiness already fired.
      expect(pending.isCompleted, isFalse);
      pending.complete();
      await pending.future;
    });

    test('后台预加载失败不撤销已经广播的登录态', () async {
      final events = <String>[];
      final errors = <Object>[];
      final coordinator = LoginReadyCoordinator(
        hydrateFromHtml: (_) async => false,
        refreshPreloadedData: () async => throw StateError('offline'),
        notifyLoginReady: (token) => events.add('ready:$token'),
      );

      coordinator.finalizeImmediately(
        token: 'verified-session',
        onRefreshError: (error, _) => errors.add(error),
      );

      await Future<void>.delayed(Duration.zero);
      expect(events, ['ready:verified-session']);
      expect(errors, hasLength(1));
    });
  });

  group('LoginReadyCoordinator', () {
    test('HTML 预加载可复用时，先复用再广播登录成功', () async {
      final events = <String>[];
      final coordinator = LoginReadyCoordinator(
        hydrateFromHtml: (html) async {
          events.add('hydrate:$html');
          return true;
        },
        refreshPreloadedData: () async {
          events.add('refresh');
        },
        notifyLoginReady: (token) {
          events.add('notify:$token');
        },
      );

      final reused = await coordinator.finalize(
        token: 'token-1',
        pageHtml: '<html />',
      );

      expect(reused, isTrue);
      expect(events, ['hydrate:<html />', 'notify:token-1']);
    });

    test('HTML 不可复用时，refresh 完成后再广播登录成功', () async {
      final events = <String>[];
      final coordinator = LoginReadyCoordinator(
        hydrateFromHtml: (html) async {
          events.add('hydrate:$html');
          return false;
        },
        refreshPreloadedData: () async {
          events.add('refresh');
        },
        notifyLoginReady: (token) {
          events.add('notify:$token');
        },
      );

      final reused = await coordinator.finalize(
        token: 'token-2',
        pageHtml: '<html />',
      );

      expect(reused, isFalse);
      expect(events, ['hydrate:<html />', 'refresh', 'notify:token-2']);
    });

    test('缺少 HTML 时，直接 refresh 后广播登录成功', () async {
      final events = <String>[];
      final coordinator = LoginReadyCoordinator(
        hydrateFromHtml: (_) async {
          events.add('hydrate');
          return true;
        },
        refreshPreloadedData: () async {
          events.add('refresh');
        },
        notifyLoginReady: (token) {
          events.add('notify:$token');
        },
      );

      final reused = await coordinator.finalize(token: 'token-3');

      expect(reused, isFalse);
      expect(events, ['refresh', 'notify:token-3']);
    });
  });
}
