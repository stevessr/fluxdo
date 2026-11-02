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

  test('Google Noto 3D uses PNG from the official Fonts CDN', () {
    expect(
      EmojiStyleAssets.urlForUnicode('1f600', EmojiRenderStyle.threeD),
      'https://fonts.gstatic.com/s/e/noto3demoji/latest/1f600/512.png',
    );
  });

  test('Google animated Noto uses WebP from the official Fonts CDN', () {
    expect(
      EmojiStyleAssets.urlForUnicode('1f600', EmojiRenderStyle.animated),
      'https://fonts.gstatic.com/s/e/notoemoji/latest/1f600/512.webp',
    );
  });

  test('complex emoji use underscore-separated Unicode scalars', () {
    expect(EmojiStyleAssets.unicodeFor('👩‍💻'), '1f469_200d_1f4bb');
    expect(EmojiStyleAssets.unicodeFor('❤️'), '2764_fe0f');
    expect(
      EmojiStyleAssets.urlForUnicode(
        EmojiStyleAssets.unicodeFor('👩‍💻')!,
        EmojiRenderStyle.threeD,
      ),
      'https://fonts.gstatic.com/s/e/noto3demoji/latest/1f469_200d_1f4bb/512.png',
    );
  });

  test('Discourse standard shortcodes resolve to Google Unicode keys', () {
    expect(EmojiStyleAssets.unicodeFor('grinning'), '1f600');
    expect(EmojiStyleAssets.unicodeFor(':grinning:'), '1f600');
    expect(EmojiStyleAssets.unicodeFor('smile'), '1f603');
    expect(EmojiStyleAssets.unicodeFor('tada'), '1f389');
    expect(
      EmojiStyleAssets.urlFor('grinning', EmojiRenderStyle.animated),
      'https://fonts.gstatic.com/s/e/notoemoji/latest/1f600/512.webp',
    );
  });

  test('invalid CDN path characters never request arbitrary URLs', () {
    expect(
      EmojiStyleAssets.urlForUnicode('../test', EmojiRenderStyle.animated),
      isNull,
    );
  });

  test('unsupported shortcode has no replacement artwork', () {
    expect(EmojiStyleAssets.unicodeFor('not_a_real_emoji'), isNull);
  });
}
