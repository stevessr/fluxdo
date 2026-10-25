import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/android_optional_plugin_service.dart';
import 'package:fluxdo_plugin_contract/fluxdo_plugin_contract.dart'
    show androidPluginCatalog, pluginTransportTimeout;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Android optional plugin account partition', () {
    test('guest is explicit and never hashes into a remembered user slot', () {
      expect(
        AndroidOptionalPluginService.sessionSlotForUsername(null),
        'guest',
      );
      expect(AndroidOptionalPluginService.sessionSlotForUsername(''), 'guest');
      expect(
        AndroidOptionalPluginService.sessionSlotForUsername('   '),
        'guest',
      );
    });

    test('same username maps to the same opaque 64 character slot', () {
      final a = AndroidOptionalPluginService.sessionSlotForUsername(' Alice ');
      final b = AndroidOptionalPluginService.sessionSlotForUsername('alice');
      expect(a, b);
      expect(a, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(a, isNot(contains('alice')));
    });

    test('different users do not share the same WebView session slot', () {
      final a = AndroidOptionalPluginService.sessionSlotForUsername('alice');
      final b = AndroidOptionalPluginService.sessionSlotForUsername('bob');
      expect(a, isNot(b));
      expect(a, isNot('guest'));
      expect(b, isNot('guest'));
    });
  });

  group('Android plugin transport contract', () {
    const channel = MethodChannel(
      'com.github.lingyan000.fluxdo/optional_plugins',
    );
    const stickerChannel = MethodChannel(
      'com.github.lingyan000.fluxdo/sticker_companion',
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final service = AndroidOptionalPluginService.instance;
    final calls = <MethodCall>[];

    Map<String, dynamic> status(String id) => {
      'id': id,
      'package': androidPluginCatalog[id]!.packageName,
      'installed': true,
      'compatible': true,
      'reason': 'ready',
      'version': '0.1.0',
    };

    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      calls.clear();
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return switch (call.method) {
          'list' => [status('network')],
          'launch' => true,
          'invoke' => '{"ok":true}',
          _ => throw MissingPluginException(),
        };
      });
      messenger.setMockMethodCallHandler(
        stickerChannel,
        (_) async => status('sticker'),
      );
    });
    tearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      messenger.setMockMethodCallHandler(stickerChannel, null);
      debugDefaultTargetPlatformOverride = null;
    });

    test(
      'invalid operations and credential fields never reach the platform',
      () async {
        await expectLater(
          service.invoke('network', 'device.snapshot'),
          throwsArgumentError,
        );
        await expectLater(
          service.invoke('deviceinfo', 'device.snapshot', {'cookie': 'secret'}),
          throwsFormatException,
        );
        await expectLater(
          service.launch('ldc', payload: {'token': 'secret'}),
          throwsFormatException,
        );
        expect(calls, isEmpty);
      },
    );

    test('normalizes valid arguments and uses only declared fields', () async {
      expect(
        await service.invoke('network', 'network.lookup', {
          'hostname': ' linux.do ',
        }),
        {'ok': true},
      );
      final arguments = calls.single.arguments as Map<dynamic, dynamic>;
      expect(jsonDecode(arguments['payload'] as String), {
        'hostname': 'linux.do',
      });
      expect(await service.launch('cdk'), isTrue);
      expect((calls.last.arguments as Map<dynamic, dynamic>)['payload'], {
        'accountSlot': 'guest',
      });
    });

    test('missing platform reply is a protocol error', () async {
      messenger.setMockMethodCallHandler(channel, (_) async => null);
      await expectLater(
        service.invoke('deviceinfo', 'device.snapshot'),
        throwsFormatException,
      );
      await expectLater(service.list(), throwsFormatException);
    });

    test(
      'native and Sticker statuses are validated as one immutable set',
      () async {
        final plugins = await service.list();
        expect(plugins.map((plugin) => plugin.id), ['network', 'sticker']);
        expect(plugins.clear, throwsUnsupportedError);
        messenger.setMockMethodCallHandler(
          stickerChannel,
          (_) async => status('network'),
        );
        await expectLater(service.list(), throwsFormatException);
      },
    );

    test(
      'older hosts may omit the Sticker channel without hiding native plugins',
      () async {
        messenger.setMockMethodCallHandler(
          stickerChannel,
          (_) async => throw MissingPluginException(),
        );
        expect((await service.list()).single.id, 'network');
      },
    );

    test('unsupported platforms make no Android calls', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      expect(await service.list(), isEmpty);
      expect(await service.launch('cdk'), isFalse);
      await expectLater(
        service.invoke('network', 'network.state'),
        throwsUnsupportedError,
      );
      expect(calls, isEmpty);
    });

    testWidgets(
      'lost platform completion times out and late reply stays harmless',
      (tester) async {
        final reply = Completer<Object?>();
        messenger.setMockMethodCallHandler(channel, (_) => reply.future);
        final expectation = expectLater(
          service.invoke('network', 'network.state'),
          throwsA(isA<TimeoutException>()),
        );
        await tester.pump(
          pluginTransportTimeout + const Duration(milliseconds: 1),
        );
        await expectation;
        reply.complete('{"late":true}');
        await tester.pump();
      },
    );
  });
}
