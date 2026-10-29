import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/pico_vr_service.dart';

void main() {
  group('PicoVrCapabilities', () {
    test('does not mistake XR passthrough for an Android Camera2 camera', () {
      final caps = PicoVrCapabilities.fromMap({
        'isPico': true,
        'model': 'PICO 4 Ultra',
        'hasCamera2': false,
        'hasCameraCaptureIntent': true,
        'hasExternalQrScanner': true,
        'supportsMultipleWindows': true,
        'isInMultiWindowMode': true,
        'maxWindows': 10,
      });

      expect(caps.isPico, isTrue);
      expect(caps.model, 'PICO 4 Ultra');
      expect(caps.canUseMobileScanner, isFalse);
      expect(caps.hasCameraCaptureIntent, isTrue);
      expect(caps.hasExternalQrScanner, isTrue);
      expect(caps.supportsMultipleWindows, isTrue);
      expect(caps.isInMultiWindowMode, isTrue);
      expect(caps.maxWindows, 10);
    });

    test('uses Android Camera2 when it is enumerated', () {
      final caps = PicoVrCapabilities.fromMap({
        'isPico': false,
        'hasCamera2': true,
        'supportsMultipleWindows': true,
      });
      expect(caps.canUseMobileScanner, isTrue);
      expect(caps.isPico, isFalse);
    });

    test('missing or malformed native data fails closed', () {
      final caps = PicoVrCapabilities.fromMap({
        'isPico': 'true',
        'hasCamera2': null,
        'hasCameraCaptureIntent': 'true',
        'supportsMultipleWindows': 1,
      });
      expect(caps.isPico, isFalse);
      expect(caps.canUseMobileScanner, isFalse);
      expect(caps.hasCameraCaptureIntent, isFalse);
      expect(caps.supportsMultipleWindows, isFalse);

      final missing = PicoVrCapabilities.fromMap(null);
      expect(missing.canUseMobileScanner, isFalse);
      expect(missing.model, isEmpty);
      expect(missing.hasCameraCaptureIntent, isFalse);
      expect(missing.hasExternalQrScanner, isFalse);
      expect(missing.maxWindows, 1);
    });
  });
  group('PicoVrLaunchRequest', () {
    test('decodes a scoped native topic and optional post number', () {
      final target = PicoVrLaunchRequest.fromMap({
        'topicId': 123,
        'postNumber': 7,
      });
      expect(target.topicId, 123);
      expect(target.postNumber, 7);

      final home = PicoVrLaunchRequest.fromMap({
        'topicId': 123,
        'postNumber': 0,
      });
      expect(home.postNumber, isNull);
    });

    test('rejects malformed launch requests', () {
      expect(
        () => PicoVrLaunchRequest.fromMap({'topicId': '123'}),
        throwsFormatException,
      );
      expect(
        () => PicoVrLaunchRequest.fromMap(null),
        throwsFormatException,
      );
    });
  });

  group('PicoVrWindowStatus', () {
    test('ten total windows includes the primary and nine extra windows', () {
      final status = PicoVrWindowStatus.fromMap({
        'maxWindows': 10,
        'openWindows': 10,
        'pendingWindows': 0,
        'availableSlots': 0,
      });
      expect(status.isAtCapacity, isTrue);
      expect(status.openWindows, 10);
    });

    test('pending secondary launches consume capacity until acknowledged', () {
      final status = PicoVrWindowStatus.fromMap({
        'maxWindows': 10,
        'openWindows': 7,
        'pendingWindows': 2,
        'availableSlots': 1,
      });
      expect(status.isAtCapacity, isFalse);
      expect(status.availableSlots, 1);
      expect(PicoVrWindowStatus.fromMap(null).isAtCapacity, isFalse);
    });
  });
}
