import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/preloaded_data_service.dart';

void main() {
  group('PreloadProgress', () {
    test('uses indeterminate progress before topic parsing starts', () {
      const requesting = PreloadProgress(phase: PreloadPhase.requesting);
      const decoding = PreloadProgress(phase: PreloadPhase.decoding);

      expect(requesting.isActive, isTrue);
      expect(requesting.fraction, isNull);
      expect(decoding.isActive, isTrue);
      expect(decoding.fraction, isNull);
    });

    test('reports and clamps parsed topic progress', () {
      const halfway = PreloadProgress(
        phase: PreloadPhase.parsingTopics,
        parsedTopics: 12,
        totalTopics: 24,
      );
      const overComplete = PreloadProgress(
        phase: PreloadPhase.parsingTopics,
        parsedTopics: 30,
        totalTopics: 24,
      );

      expect(halfway.isActive, isTrue);
      expect(halfway.fraction, 0.5);
      expect(overComplete.fraction, 1.0);
    });

    test('complete and failed phases stop the active indicator', () {
      const complete = PreloadProgress(phase: PreloadPhase.complete);
      const failed = PreloadProgress(phase: PreloadPhase.failed);

      expect(complete.isActive, isFalse);
      expect(complete.fraction, 1.0);
      expect(failed.isActive, isFalse);
      expect(failed.fraction, isNull);
    });
  });
}
