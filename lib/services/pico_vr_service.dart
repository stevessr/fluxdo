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
    this.hasExternalQrScanner = false,
    this.cameraCount = 0,
    this.cameraPermissionGranted = false,
    required this.supportsMultipleWindows,
    required this.isInMultiWindowMode,
    this.model = '',
  });

  factory PicoVrCapabilities.fromMap(Map<String, dynamic>? data) {
    return PicoVrCapabilities(
      isPico: data?['isPico'] == true,
      hasCamera2: data?['hasCamera2'] == true,
      hasCameraCaptureIntent: data?['hasCameraCaptureIntent'] == true,
      hasExternalQrScanner: data?['hasExternalQrScanner'] == true,
      cameraCount: data?['cameraCount'] is int ? data!['cameraCount'] as int : 0,
      cameraPermissionGranted: data?['cameraPermissionGranted'] == true,
      supportsMultipleWindows: data?['supportsMultipleWindows'] == true,
      isInMultiWindowMode: data?['isInMultiWindowMode'] == true,
      model: data?['model'] is String ? data!['model'] as String : '',
    );
  }

  final bool isPico;
  final bool hasCamera2;
  final bool hasCameraCaptureIntent;
  final bool hasExternalQrScanner;
  final int cameraCount;
  final bool cameraPermissionGranted;
  final bool supportsMultipleWindows;
  final bool isInMultiWindowMode;
  final String model;

  /// Only use mobile_scanner when a regular Android camera is enumerated.
  /// XR passthrough cameras cannot be inferred from a CAMERA permission.
  bool get canUseMobileScanner => hasCamera2;
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

  /// Recheck after USB camera attachment, permission changes, or activity resume.
  /// Does not assume that a PICO XR passthrough camera is an Android camera.
  Future<PicoVrCapabilities> refreshCapabilities() {
    _future = _loadCapabilities();
    return _future!;
  }

  /// ZXing's optional activity contract returns decoded content. It only works
  /// if an installed app advertises that contract (not necessarily on PICO).
  /// A null result means the user cancelled; callers must validate any payload.
  Future<String?> scanWithExternalApp() async {
    if (kIsWeb || !Platform.isAndroid) return null;
    return _channel.invokeMethod<String>('scanWithExternalApp');
  }

  Future<bool> openNewWindow() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('openNewWindow') ?? false;
    } on PlatformException catch (error) {
      debugPrint('[PicoVr] New window failed: ${error.code}');
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
