import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stevessr_generator/stevessr_generator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('file sharing is disabled on Linux targets', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expect(StevessrExportService.canShareFiles, isFalse);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(StevessrExportService.canShareFiles, isTrue);
    debugDefaultTargetPlatformOverride = null;
  });

  test('default parameters normalize to a usable render size', () {
    final params = StevessrRenderParams.defaults().normalized();
    expect(params.width, 1254);
    expect(params.height, 1254);
    expect(params.character, StevessrCharacter.original);
  });

  test('package assets load neutral art and restore an expression delta', () async {
    final neutral = await StevessrCharacterAssets.load(
      StevessrCharacter.original,
      StevessrExpression.neutral,
    );
    final happy = await StevessrCharacterAssets.load(
      StevessrCharacter.original,
      StevessrExpression.happy,
    );

    expect(neutral, isNotEmpty);
    expect(happy, isNotEmpty);
    expect(happy, isNot(equals(neutral)));
  });

  test('neutral art loads for every packaged character', () async {
    for (final character in StevessrCharacter.values) {
      final bytes = await StevessrCharacterAssets.load(
        character,
        StevessrExpression.neutral,
      );
      expect(bytes, isNotEmpty, reason: character.assetPath());
    }
  });

  test('text layout wraps text within the configured bubble', () {
    final params = StevessrRenderParams.defaults();
    final result = StevessrTextLayout.fit(
      text: 'A longer sentence that needs wrapping',
      box: params.bubbleRect,
      padding: params.padding,
      minFont: params.fontMin,
      maxFont: params.fontMax,
      lineHeight: params.lineHeight,
      font: params.font,
      fontWeight: params.fontWeight,
    );
    expect(result.lines.length, greaterThan(1));
  });
}
