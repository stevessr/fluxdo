import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Lifecycle bridge for Flutter's fullscreen video surface.
class AndroidPictureInPicture extends ChangeNotifier {
  AndroidPictureInPicture._() {
    if (Platform.isAndroid) {
      channel.setMethodCallHandler((call) async {
        if (call.method == 'pipChanged') {
          inPictureInPicture = call.arguments == true;
          notifyListeners();
        }
      });
    }
  }

  static final instance = AndroidPictureInPicture._();
  static const channel = MethodChannel('com.github.lingyan000.fluxdo/picture_in_picture');

  bool inPictureInPicture = false;

  Future<void> setEligible(bool enabled, {double aspectRatio = 16 / 9}) async {
    if (!Platform.isAndroid) return;
    final ratio = aspectRatio.isFinite && aspectRatio > 0
        ? aspectRatio.clamp(0.42, 2.39)
        : 16 / 9;
    // Android PiP requires a rational between 1:2.39 and 2.39:1.
    try {
      await channel.invokeMethod<bool>('setEligible', {
        'enabled': enabled,
        'width': (ratio * 100).round(),
        'height': 100,
      });
    } on PlatformException catch (error) {
      debugPrint('[PiP] Could not update eligibility: $error');
    }
  }

  Future<bool> enter() async {
    if (!Platform.isAndroid) return false;
    try {
      return await channel.invokeMethod<bool>('enter') ?? false;
    } on PlatformException {
      return false;
    }
  }
}
