import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class VpnBypassStatus {
  const VpnBypassStatus({
    required this.supported,
    required this.enabled,
    required this.vpnActive,
    required this.bound,
    required this.validated,
    required this.transport,
    required this.reason,
  });

  const VpnBypassStatus.disabled()
    : supported = true,
      enabled = false,
      vpnActive = false,
      bound = false,
      validated = false,
      transport = 'other',
      reason = 'disabled';

  final bool supported;
  final bool enabled;
  final bool vpnActive;
  final bool bound;
  final bool validated;
  final String transport;
  final String reason;

  factory VpnBypassStatus.fromMap(Object? value) {
    if (value is! Map) {
      return const VpnBypassStatus(
        supported: false,
        enabled: false,
        vpnActive: false,
        bound: false,
        validated: false,
        transport: 'other',
        reason: 'invalidStatus',
      );
    }
    return VpnBypassStatus(
      supported: value['supported'] == true,
      enabled: value['enabled'] == true,
      vpnActive: value['vpnActive'] == true,
      bound: value['bound'] == true,
      validated: value['validated'] == true,
      transport: value['transport']?.toString() ?? 'other',
      reason: value['reason']?.toString() ?? 'unknown',
    );
  }
}

/// Android VPN bypass controller.
///
/// Android only permits an app to bind around a VPN when the VPN itself allows
/// bypass (VpnService.Builder.allowBypass()) and no lockdown policy blocks
/// direct traffic. This service exposes that best-effort capability without
/// pretending it can override the VPN owner's policy.
class VpnBypassService {
  VpnBypassService._();

  static final VpnBypassService instance = VpnBypassService._();

  static const _channel = MethodChannel('com.fluxdo/vpn_bypass');
  static const _prefsKey = 'vpn_bypass_enabled';

  SharedPreferences? _prefs;
  bool _initialized = false;

  final enabledNotifier = ValueNotifier<bool>(false);
  final statusNotifier = ValueNotifier<VpnBypassStatus>(
    const VpnBypassStatus.disabled(),
  );

  bool get enabled => enabledNotifier.value;
  VpnBypassStatus get status => statusNotifier.value;

  Future<void> initialize(SharedPreferences prefs) async {
    if (_initialized) return;
    _initialized = true;
    _prefs = prefs;

    final configured = prefs.getBool(_prefsKey) ?? false;
    enabledNotifier.value = configured;

    if (!Platform.isAndroid) {
      statusNotifier.value = VpnBypassStatus(
        supported: false,
        enabled: configured,
        vpnActive: false,
        bound: false,
        validated: false,
        transport: 'other',
        reason: 'unsupported',
      );
      return;
    }

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'statusChanged') {
        statusNotifier.value = VpnBypassStatus.fromMap(call.arguments);
      }
    });

    await _applyNative(configured);
  }

  Future<void> setEnabled(bool value) async {
    if (enabledNotifier.value == value && status.enabled == value) return;

    enabledNotifier.value = value;
    await _prefs?.setBool(_prefsKey, value);

    if (!Platform.isAndroid) {
      statusNotifier.value = VpnBypassStatus(
        supported: false,
        enabled: value,
        vpnActive: false,
        bound: false,
        validated: false,
        transport: 'other',
        reason: 'unsupported',
      );
      return;
    }

    await _applyNative(value);
  }

  Future<void> refresh() async {
    if (!Platform.isAndroid) return;
    try {
      final raw = await _channel.invokeMethod<Object?>('getStatus');
      statusNotifier.value = VpnBypassStatus.fromMap(raw);
    } on PlatformException catch (e) {
      debugPrint('[VpnBypass] getStatus failed: ${e.code}: ${e.message}');
    }
  }

  Future<void> _applyNative(bool value) async {
    try {
      final raw = await _channel.invokeMethod<Object?>(
        'setEnabled',
        {'enabled': value},
      );
      statusNotifier.value = VpnBypassStatus.fromMap(raw);
    } on MissingPluginException {
      statusNotifier.value = VpnBypassStatus(
        supported: false,
        enabled: value,
        vpnActive: false,
        bound: false,
        validated: false,
        transport: 'other',
        reason: 'unsupported',
      );
    } on PlatformException catch (e) {
      debugPrint('[VpnBypass] setEnabled failed: ${e.code}: ${e.message}');
      statusNotifier.value = VpnBypassStatus(
        supported: true,
        enabled: value,
        vpnActive: false,
        bound: false,
        validated: false,
        transport: 'other',
        reason: 'nativeError',
      );
    }
  }
}
