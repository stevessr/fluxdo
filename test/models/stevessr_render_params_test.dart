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
    expect(params.height, 320);
    expect(params.fontMin, 8);
    expect(params.fontMax, 220);
    expect(params.fontWeight, 100);
    expect(params.bubbleStrokeWidth, 60);
    expect(params.lineHeight, 2);
    expect(params.padding, 0);
    expect(params.quality, 20);
    expect(params.bubbleRect.x, closeTo(106, 0.001));
    expect(params.bubbleRect.height, closeTo(98, 0.001));
    expect(params.characterRect.width, 64);
    expect(params.characterRect.height, 64);
  });

  test('文本最多保留 500 个 rune', () {
    final text = List<String>.filled(600, '界').join();
    final params = StevessrRenderParams.defaults().copyWith(text: text);

    expect(params.text.runes.length, 500);
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
        'original',
      ]),
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
  });
}
