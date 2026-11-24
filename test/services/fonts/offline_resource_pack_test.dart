import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/fonts/offline_resource_pack.dart';

void main() {
  test('offline resource paths preserve aliases and skin tone variants', () {
    expect(OfflineResourcePack.emojiPath('+1:t3', 'noto_animated'),
        'emoji/noto_animated/+1/3.webp');
    expect(OfflineResourcePack.emojiPath('grinning', 'noto_3d'),
        'emoji/noto_3d/grinning.png');
    expect(OfflineResourcePack.emojiPath('woman_technologist', 'noto'),
        'emoji/noto/woman_technologist.png');
  });

  test('rejects traversal, unknown sets and malformed skin tones', () {
    for (final name in ['../secret', 'a/b', 'x:t9', 'x.png', '']) {
      expect(OfflineResourcePack.emojiPath(name, 'noto'), isNull);
    }
    expect(OfflineResourcePack.emojiPath('grinning', '../foo'), isNull);
  });
}
