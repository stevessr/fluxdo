import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';

/// App-level adaptive mode selection, not a guarantee of panel-level VRR.
class DisplayRefreshService with WidgetsBindingObserver {
  DisplayRefreshService._();
  static final instance = DisplayRefreshService._();
  static const auto = -1;
  static const smart = -2;
  static int normalize(int? rate) =>
      rate == smart ? smart : (rate != null && rate > 0 ? rate : auto);

  int _policy = auto;
  int _generation = 0;
  bool _observing = false;
  bool _foreground = true;
  Timer? _idle;
  DisplayMode? _low;
  DisplayMode? _high;
  DisplayMode? _requested;
  Future<void> _serial = Future.value();

  static List<DisplayMode> validModes(List<DisplayMode> modes, DisplayMode active) =>
      modes.where((m) => m.refreshRate.isFinite && m.refreshRate > 0 &&
          m.width == active.width && m.height == active.height).toList()
        ..sort((a, b) => a.refreshRate.compareTo(b.refreshRate));

  Future<void> _request(DisplayMode mode, int generation) {
    if (generation != _generation || _requested == mode) return _serial;
    _requested = mode;
    _serial = _serial.then((_) async {
      if (generation != _generation) return;
      try {
        await FlutterDisplayMode.setPreferredMode(mode);
      } catch (e) {
        if (generation == _generation && _requested == mode) _requested = null;
        debugPrint('[DisplayRefresh] $e');
      }
    });
    return _serial;
  }

  Future<void> apply(int rate) async {
    if (!Platform.isAndroid) return;
    _policy = normalize(rate);
    final generation = ++_generation;
    _idle?.cancel();
    _requested = null;
    _low = _high = null;
    if (_observing) {
      GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
      WidgetsBinding.instance.removeObserver(this);
      _observing = false;
    }
    try {
      if (_policy == auto) {
        await _request(DisplayMode.auto, generation);
        return;
      }
      final modes = await FlutterDisplayMode.supported;
      final active = await FlutterDisplayMode.active;
      if (generation != _generation) return;
      final valid = validModes(modes, active);
      if (_policy != smart) {
        final matches = valid.where((m) => m.refreshRate.round() == _policy);
        await _request(matches.isEmpty ? DisplayMode.auto : matches.last, generation);
        return;
      }
      if (valid.length < 2 || valid.first.refreshRate.round() == valid.last.refreshRate.round()) {
        await _request(DisplayMode.auto, generation);
        return;
      }
      _low = valid.first;
      _high = valid.last;
      _foreground = WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
      GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
      if (_foreground) {
        interaction();
      } else {
        await _request(DisplayMode.auto, generation);
      }
    } catch (e) {
      debugPrint('[DisplayRefresh] $e');
      if (generation == _generation) await _request(DisplayMode.auto, generation);
    }
  }

  void _onPointer(PointerEvent event) {
    if (event is PointerDownEvent || event is PointerMoveEvent ||
        event is PointerSignalEvent) interaction();
  }

  void interaction() {
    if (!_observing || _policy != smart || !_foreground || _high == null || _low == null) return;
    final generation = _generation;
    unawaited(_request(_high!, generation));
    _idle?.cancel();
    _idle = Timer(const Duration(seconds: 2), () {
      if (_foreground && generation == _generation && _low != null) {
        unawaited(_request(_low!, generation));
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _idle?.cancel();
    if (_foreground) {
      unawaited(apply(smart));
    } else {
      unawaited(_request(DisplayMode.auto, ++_generation));
    }
  }
}
