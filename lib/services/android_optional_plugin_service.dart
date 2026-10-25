import 'dart:convert';

import 'package:crypto/crypto.dart' show sha256;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:fluxdo_plugin_contract/fluxdo_plugin_contract.dart';

export 'package:fluxdo_plugin_contract/fluxdo_plugin_contract.dart'
    show AndroidOptionalPlugin;

/// Android APK extensions communicate through signed Binder services rather
/// than loading code into the Flutter engine. Other platforms see no plugins.
class AndroidOptionalPluginService {
  AndroidOptionalPluginService._();

  static final instance = AndroidOptionalPluginService._();
  static const _channel = MethodChannel(
    'com.github.lingyan000.fluxdo/optional_plugins',
  );

  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Opaque account partition ID for an independently installed WebView APK.
  /// Never sends the username, forum cookie, auth token or password via IPC.
  /// A logged-out invocation uses guest, which plugins treat as ephemeral.
  static String sessionSlotForUsername(String? username) {
    final value = username?.trim().toLowerCase();
    if (value == null || value.isEmpty) return 'guest';
    return sha256.convert(utf8.encode(value)).toString();
  }

  Future<List<AndroidOptionalPlugin>> list() async {
    if (!supported) return const [];
    final items = await _channel
        .invokeMethod<List<dynamic>>('list')
        .timeout(pluginTransportTimeout);
    if (items == null) {
      throw const FormatException('Plugin host did not return a status list');
    }
    final statuses = List<dynamic>.of(items);
    try {
      const stickerChannel = MethodChannel(
        'com.github.lingyan000.fluxdo/sticker_companion',
      );
      final sticker = await stickerChannel
          .invokeMapMethod<dynamic, dynamic>('status')
          .timeout(pluginTransportTimeout);
      if (sticker != null) {
        statuses.add(sticker);
      }
    } on MissingPluginException {
      // Older FluxDO installations have no sticker companion bridge.
    }
    return AndroidOptionalPlugin.parseList(statuses);
  }

  Future<bool> launch(
    String id, {
    Map<String, dynamic> payload = const {},
  }) async {
    if (!supported) return false;
    final arguments = AndroidPluginContract.launchPayload(id, payload);
    return await _channel
            .invokeMethod<bool>('launch', {'id': id, 'payload': arguments})
            .timeout(pluginTransportTimeout) ??
        false;
  }

  Future<Map<String, dynamic>> invoke(
    String id,
    String operation, [
    Map<String, dynamic> payload = const {},
  ]) async {
    if (!supported) throw UnsupportedError('Android plugins are unavailable');
    final encoded = AndroidPluginContract.encodeInvocation(
      id,
      operation,
      payload,
    );
    final raw = await _channel
        .invokeMethod<String>('invoke', {
          'id': id,
          'operation': operation,
          'payload': encoded,
        })
        .timeout(pluginTransportTimeout);
    return AndroidPluginContract.decodeResponse(raw);
  }
}
