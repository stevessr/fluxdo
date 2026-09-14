import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Runtime policy for the operating system's battery/power saving mode.
///
/// The service deliberately keeps a very small surface: widgets listen to this
/// notifier and decide which expensive visual work can be skipped. On Android
/// it also caps the preferred display mode around 60 Hz while power saving is
/// active, then restores the user's refresh-rate preference when it is disabled.
class PowerSavingModeService extends ChangeNotifier with WidgetsBindingObserver {
  PowerSavingModeService._();

  static final PowerSavingModeService instance = PowerSavingModeService._();

  final Battery _battery = Battery();

  bool _initialized = false;
  bool _enabled = false;
  bool _refreshInProgress = false;

  bool get isEnabled => _enabled;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    WidgetsBinding.instance.addObserver(this);
    await refresh();
  }

  /// Re-read the platform power-saving state.
  ///
  /// There is no portable battery-saver change stream, so lifecycle resume is
  /// the important synchronization point: toggling battery saver from system
  /// settings normally backgrounds FluxDO first and is picked up immediately
  /// when the app returns.
  Future<void> refresh() async {
    if (_refreshInProgress) return;
    _refreshInProgress = true;
    try {
      final next = await _readPlatformState();
      final changed = next != _enabled;
      _enabled = next;
      if (changed) {
        notifyListeners();
      }

      if (!kIsWeb &&
          defaultTargetPlatform == TargetPlatform.android &&
          (changed || next)) {
        await _applyAndroidDisplayPolicy(powerSaving: next);
      }
    } finally {
      _refreshInProgress = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(refresh());
    }
  }

  Future<bool> _readPlatformState() async {
    if (kIsWeb) return false;

    // battery_plus exposes the native saver state on these platforms. Linux
    // currently has no equivalent API in the plugin, so keep normal behavior.
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        try {
          return await _battery.isInBatterySaveMode;
        } catch (error) {
          debugPrint('[PowerSavingMode] 读取系统省电状态失败: $error');
          return false;
        }
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return false;
    }
  }

  Future<void> _applyAndroidDisplayPolicy({required bool powerSaving}) async {
    try {
      if (powerSaving) {
        final modes = await FlutterDisplayMode.supported;
        if (modes.isEmpty) return;

        final active = await FlutterDisplayMode.active;
        final sameResolution = modes
            .where((mode) =>
                mode.width == active.width && mode.height == active.height)
            .toList();
        final candidates = sameResolution.isEmpty ? modes : sameResolution;

        // Prefer the highest mode up to 60 Hz. If a panel exposes no <=60 Hz
        // mode, use its lowest available mode instead of accidentally keeping
        // 90/120/144 Hz during battery saver.
        final atMost60 = candidates
            .where((mode) => mode.refreshRate <= 60.5)
            .toList();
        final pool = atMost60.isEmpty ? candidates : atMost60;
        final picked = pool.reduce((a, b) {
          if (atMost60.isEmpty) {
            return a.refreshRate <= b.refreshRate ? a : b;
          }
          return a.refreshRate >= b.refreshRate ? a : b;
        });
        await FlutterDisplayMode.setPreferredMode(picked);
        debugPrint(
          '[PowerSavingMode] 省电模式刷新率降档: '
          '${picked.width}x${picked.height}@${picked.refreshRate}',
        );
        return;
      }

      // Restore the same preference semantics used by main.dart: 0 means auto,
      // otherwise choose the requested rate and prefer the active resolution.
      final prefs = await SharedPreferences.getInstance();
      final targetRate = prefs.getInt('pref_display_mode_refresh_rate') ?? 0;
      if (targetRate == 0) {
        await FlutterDisplayMode.setPreferredMode(DisplayMode.auto);
        return;
      }

      final modes = await FlutterDisplayMode.supported;
      final active = await FlutterDisplayMode.active;
      final matches = modes
          .where((mode) => mode.refreshRate.round() == targetRate)
          .toList();
      if (matches.isEmpty) {
        await FlutterDisplayMode.setPreferredMode(DisplayMode.auto);
        return;
      }
      final picked = matches.firstWhere(
        (mode) => mode.width == active.width && mode.height == active.height,
        orElse: () => matches.first,
      );
      await FlutterDisplayMode.setPreferredMode(picked);
    } catch (error) {
      debugPrint('[PowerSavingMode] 应用显示策略失败: $error');
    }
  }
}
