import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android 2D camera enumeration is independent of PICO's XR passthrough API.
@immutable
class PicoVrCapabilities {
  const PicoVrCapabilities({
    required this.isPico,
    required this.hasCamera2,
    this.hasCameraCaptureIntent = false,
    required this.supportsMultipleWindows,
    required this.isInMultiWindowMode,
    this.maxWindows = 1,
    this.model = '',
  });

  factory PicoVrCapabilities.fromMap(Map<String, dynamic>? data) {
    return PicoVrCapabilities(
      isPico: data?['isPico'] == true,
      hasCamera2: data?['hasCamera2'] == true,
      hasCameraCaptureIntent: data?['hasCameraCaptureIntent'] == true,
      supportsMultipleWindows: data?['supportsMultipleWindows'] == true,
      isInMultiWindowMode: data?['isInMultiWindowMode'] == true,
      maxWindows: data?['maxWindows'] is int &&
              (data!['maxWindows'] as int) > 0
          ? data['maxWindows'] as int
          : 1,
      model: data?['model'] is String ? data!['model'] as String : '',
    );
  }

  final bool isPico;
  final bool hasCamera2;
  final bool hasCameraCaptureIntent;
  final bool supportsMultipleWindows;
  final bool isInMultiWindowMode;
  /// Maximum number of FluxDO native panels, including the main window.
  final int maxWindows;
  final String model;

  /// Only use mobile_scanner when a regular Android camera is enumerated.
  /// XR passthrough cameras cannot be inferred from a CAMERA permission.
  bool get canUseMobileScanner => hasCamera2;
}

/// A one-shot navigation target owned by the newly launched Android Activity.
@immutable
class PicoVrLaunchRequest {
  const PicoVrLaunchRequest({
    required this.topicId,
    this.postNumber,
  });

  factory PicoVrLaunchRequest.fromMap(Map<String, dynamic>? raw) {
    final topicId = raw?['topicId'];
    final postNumber = raw?['postNumber'];
    if (topicId is! int || topicId <= 0) {
      throw const FormatException('Invalid native window topic');
    }
    return PicoVrLaunchRequest(
      topicId: topicId,
      postNumber: postNumber is int && postNumber > 0 ? postNumber : null,
    );
  }

  final int topicId;
  final int? postNumber;
}

/// Live capacity snapshot for FluxDO-owned Android Activity windows.
@immutable
class PicoVrWindowStatus {
  const PicoVrWindowStatus({
    required this.maxWindows,
    required this.openWindows,
    required this.pendingWindows,
    required this.availableSlots,
  });

  factory PicoVrWindowStatus.fromMap(Map<String, dynamic>? data) {
    int number(String key) {
      final value = data?[key];
      return value is int && value >= 0 ? value : 0;
    }

    return PicoVrWindowStatus(
      maxWindows: number('maxWindows'),
      openWindows: number('openWindows'),
      pendingWindows: number('pendingWindows'),
      availableSlots: number('availableSlots'),
    );
  }

  final int maxWindows;
  final int openWindows;
  final int pendingWindows;
  final int availableSlots;

  bool get isAtCapacity => maxWindows > 0 && availableSlots == 0;
}

class PicoVrService {
  PicoVrService._();

  static final PicoVrService instance = PicoVrService._();
  static const MethodChannel _channel = MethodChannel('com.fluxdo/pico_vr');

  Future<PicoVrCapabilities>? _future;
  PicoVrCapabilities? _lastCapabilities;

  PicoVrCapabilities? get cachedCapabilities => _lastCapabilities;

  /// Cached for this Flutter engine; repeated settings/QR pages don't
  /// re-enumerate the Camera2 service or trigger a new device query.
  Future<PicoVrCapabilities> get capabilities =>
      _future ??= _loadCapabilities();

  Future<PicoVrCapabilities> _loadCapabilities() async {
    if (kIsWeb || !Platform.isAndroid) {
      return const PicoVrCapabilities(
        isPico: false,
        hasCamera2: false,
        supportsMultipleWindows: false,
        isInMultiWindowMode: false,
      );
    }
    try {
      final data = await _channel.invokeMapMethod<String, dynamic>(
        'getCapabilities',
      );
      final caps = PicoVrCapabilities.fromMap(data);
      _lastCapabilities = caps;
      return caps;
    } on PlatformException catch (error) {
      debugPrint('[PicoVr] Capabilities unavailable: ${error.code}');
    } on MissingPluginException {
      debugPrint('[PicoVr] Native compatibility channel unavailable');
    }
    // Native channel failure must not turn off scanning on ordinary phones.
    // The scanner's own errorBuilder still handles a missing physical camera.
    return const PicoVrCapabilities(
      isPico: false,
      hasCamera2: true,
      supportsMultipleWindows: false,
      isInMultiWindowMode: false,
    );
  }

  /// Lightweight native count; unlike capabilities this is NOT cached.
  Future<PicoVrWindowStatus?> getWindowStatus() async {
    if (kIsWeb || !Platform.isAndroid) return null;
    try {
      final status = await _channel.invokeMapMethod<String, dynamic>(
        'getWindowStatus',
      );
      return status == null ? null : PicoVrWindowStatus.fromMap(status);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// The Android shell owns placement. A positive topic ID opens that topic
  /// in the new task, rather than returning to the home feed.
  Future<bool> openNewWindow({int? topicId, int? postNumber}) async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('openNewWindow', {
            if (topicId != null && topicId > 0) 'topicId': topicId,
            if (postNumber != null && postNumber > 0)
              'postNumber': postNumber,
          }) ??
          false;
    } on PlatformException catch (error) {
      debugPrint('[PicoVr] New window failed: ${error.code}');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Read once from the *current* native Activity. Never use shared
  /// preferences or a process-global variable for cross-window routing.
  Future<PicoVrLaunchRequest?> consumeLaunchRequest() async {
    if (kIsWeb || !Platform.isAndroid) return null;
    try {
      final data = await _channel.invokeMapMethod<String, dynamic>(
        'consumeLaunchRequest',
      );
      if (data == null) return null;
      return PicoVrLaunchRequest.fromMap(data);
    } on PlatformException catch (error) {
      debugPrint('[PicoVr] Window launch request unavailable: ${error.code}');
    } on MissingPluginException {
      return null;
    } on FormatException {
      debugPrint('[PicoVr] Invalid native window launch request');
    }
    return null;
  }
}
