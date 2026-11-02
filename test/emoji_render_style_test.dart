import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/providers/preferences_provider.dart';
import 'package:fluxdo/widgets/common/styled_emoji_image.dart';

void main() {
  test('invalid or missing emoji style settings remain normal', () {
    expect(EmojiRenderStyle.fromString(null), EmojiRenderStyle.normal);
    expect(EmojiRenderStyle.fromString('unknown'), EmojiRenderStyle.normal);
    expect(EmojiRenderStyle.fromString('animated'), EmojiRenderStyle.animated);
    expect(EmojiRenderStyle.fromString('threeD'), EmojiRenderStyle.threeD);
  });

  test('normal style does not request third-party artwork', () {
    expect(EmojiStyleAssets.urlForUnicode('1f600', EmojiRenderStyle.normal), isNull);
  });

  test('3D uses Fluent emoji raster artwork', () {
    expect(
      EmojiStyleAssets.urlForUnicode('1f600', EmojiRenderStyle.threeD),
      'https://registry.npmmirror.com/@lobehub/fluent-emoji-3d/latest/files/assets/1f600.webp',
    );
  });

  test('animated assets are partitioned into four published packages', () {
    const samples = <String, String>{
      '1f44b': 'fluent-emoji-anim-1',
      '1f469': 'fluent-emoji-anim-2',
      '1f620': 'fluent-emoji-anim-3',
      '1f9a0': 'fluent-emoji-anim-4',
    };
    for (final entry in samples.entries) {
      expect(
        EmojiStyleAssets.urlForUnicode(entry.key, EmojiRenderStyle.animated),
        'https://registry.npmmirror.com/@lobehub/${entry.value}/latest/files/assets/${entry.key}.webp',
      );
    }
  });

  test('unsupported shortcode has no replacement artwork', () {
    expect(EmojiStyleAssets.unicodeFor('not_a_real_emoji'), isNull);
  });
}
