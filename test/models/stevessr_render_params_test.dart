import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/stevessr_render_params.dart';

void main() {
  test('默认参数使用右侧气泡尾巴', () {
    final params = StevessrRenderParams.defaults();

    expect(params.width, 1254);
    expect(params.height, 1254);
    expect(params.tail, StevessrTail.right);
    expect(params.expression, StevessrExpression.neutral);
    expect(params.bubble, StevessrBubble.thought);
    expect(
      params.bubbleRect,
      const StevessrRect(x: 65, y: 66, width: 665, height: 385),
    );
  });

  test('归一化会限制画布、字号、颜色排版参数和位置', () {
    final params = StevessrRenderParams.defaults().copyWith(
      width: 99999,
      height: 1,
      fontMin: 1,
      fontMax: 999,
      fontWeight: 1,
      bubbleStrokeWidth: 999,
      lineHeight: 99,
      padding: -20,
      quality: 1,
      bubbleRect: const StevessrRect(
        x: double.infinity,
        y: -99999,
        width: 1,
        height: double.nan,
      ),
      characterRect: const StevessrRect(
        x: -99999,
        y: double.infinity,
        width: 1,
        height: 1,
      ),
    );

    expect(params.width, 2048);
    expect(params.height, 128);
    expect(params.fontMin, 8);
    expect(params.fontMax, 220);
    expect(params.fontWeight, 100);
    expect(params.bubbleStrokeWidth, 60);
    expect(params.lineHeight, 2);
    expect(params.padding, 0);
    expect(params.quality, 20);
    expect(params.bubbleRect.x, closeTo(106, 0.001));
    expect(params.bubbleRect.height, closeTo(39, 0.001));
    expect(params.characterRect.width, 24);
    expect(params.characterRect.height, 24);
  });

  test('文本最多保留 500 个 rune', () {
    final text = List<String>.filled(600, '界').join();
    final params = StevessrRenderParams.defaults().copyWith(text: text);

    expect(params.text.runes.length, 500);
  });

  test('气泡图片内容需要有效图片数据并支持清除', () {
    final withoutImage = StevessrRenderParams.defaults().copyWith(
      bubbleContent: StevessrBubbleContent.image,
    );
    expect(withoutImage.bubbleContent, StevessrBubbleContent.text);
    expect(withoutImage.usesBubbleImage, isFalse);

    final withImage = StevessrRenderParams.defaults().copyWith(
      bubbleContent: StevessrBubbleContent.image,
      bubbleImageBytes: Uint8List.fromList([1, 2, 3]),
      bubbleImageMimeType: 'image/png',
    );
    expect(withImage.bubbleContent, StevessrBubbleContent.image);
    expect(withImage.usesBubbleImage, isTrue);

    final textMode = withImage.copyWith(
      bubbleContent: StevessrBubbleContent.text,
    );
    expect(textMode.usesBubbleImage, isFalse);
    expect(
      textMode
          .copyWith(bubbleContent: StevessrBubbleContent.image)
          .usesBubbleImage,
      isTrue,
    );

    final cleared = withImage.copyWith(clearBubbleImage: true);
    expect(cleared.bubbleContent, StevessrBubbleContent.text);
    expect(cleared.bubbleImageBytes, isNull);
    expect(cleared.usesBubbleImage, isFalse);
  });

  test('所有枚举都提供稳定的资源 key', () {
    expect(
      StevessrExpression.values.map((value) => value.key),
      containsAll(<String>[
        'neutral',
        'pout',
        'smug',
        'surprised',
        'happy',
        'cry',
        'angry',
        'embarrassed',
        'sleepy',
        'love',
        'laughing',
        'wink',
        'confused',
        'thinking',
        'panic',
        'pleading',
        'apologetic',
        'celebrating',
        'dizzy',
        'bored',
        'scared',
        'hungry',
        'grateful',
      ]),
    );
    expect(
      StevessrExpression.values.map((value) => value.key),
      isNot(contains('original')),
    );
    expect(
      StevessrCharacter.values.map((value) => value.key),
      containsAll(<String>[
        'reimu',
        'marisa',
        'flandre',
        'remilia',
        'sakuya',
        'patchouli',
        'koishi',
        'satori',
        'okuu',
        'okuu_rin',
        'yuyuko',
        'youmu',
        'yukari',
        'cirno',
        'sanae',
        'suika',
        'suwako',
        'tenshi',
        'kokoro',
        'kaguya',
        'einin',
        'aya',
        'akyuu',
        'renko',
        'sumireko',
        'maribel',
        'keine',
        'deepseek',
        'blue_archive_01',
        'blue_archive_02',
        'blue_archive_03',
        'blue_archive_04',
        'blue_archive_05',
        'witch_judgment_01',
        'witch_judgment_02',
        'witch_judgment_03',
        'witch_judgment_04',
        'witch_judgment_05',
        'witch_judgment_06',
        'witch_judgment_07',
        'witch_judgment_08',
        'witch_judgment_09',
        'witch_judgment_10',
      ]),
    );
    expect(
      StevessrCharacter.values.map((value) => value.displayName),
      containsAll(<String>[
        '博丽灵梦',
        '雾雨魔理沙',
        '琪露诺',
        '蕾米莉亚·斯卡蕾特',
        '碧蓝档案 01',
        '魔法少女的魔女审判 10',
      ]),
    );
    expect(StevessrCharacter.original.displayName, '');
    expect(StevessrCharacter.original.supportsExpression, isTrue);
    expect(StevessrCharacter.blueArchive01.supportsExpression, isFalse);
    expect(
      StevessrCharacter.blueArchive01.assetPath(),
      'blue_archive/blue_archive_01.webp',
    );
    expect(
      StevessrCharacter.witchJudgment10.assetPath(),
      'witch_judgment/witch_judgment_10.webp',
    );
    expect(
      StevessrBubble.values.map((value) => value.key),
      containsAll(<String>[
        'thought',
        'speech',
        'cloud',
        'shout',
        'rounded',
        'caption',
      ]),
    );
    expect(
      StevessrBubbleContent.values.map((value) => value.key),
      containsAll(<String>['text', 'image']),
    );
  });
}
