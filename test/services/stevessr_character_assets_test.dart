import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/stevessr_render_params.dart';
import 'package:fluxdo/services/avatar_delta_codec.dart';
import 'package:fluxdo/services/stevessr_character_assets.dart';
import 'package:fluxdo/services/stevessr_export_service.dart';
import 'package:fluxdo/widgets/stevessr/stevessr_canvas.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final character in [
    StevessrCharacter.original,
    StevessrCharacter.claude,
    StevessrCharacter.deepseek,
  ]) {
    for (final expression in character.expressions.skip(1)) {
      test('${character.name}/${expression.key} 差分逐像素还原源稿并保留透明', () async {
        final bytes = await StevessrCharacterAssets.load(character, expression);
        final restored = img.decodePng(bytes)!;
        for (final pixel in restored) {
          if (pixel.a == 0) pixel.setRgba(0, 0, 0, 0);
        }
        if (character == StevessrCharacter.original) {
          final metadata = jsonDecode(
            File('tool/avatar_sources/stevessr/source.json').readAsStringSync(),
          ) as Map<String, dynamic>;
          expect(restored.width, metadata['width']);
          expect(restored.height, metadata['height']);
          expect(restored.getPixel(0, 0).a, 0);
          expect(
            sha256
                .convert(restored.getBytes(order: img.ChannelOrder.rgba))
                .toString(),
            metadata['expressions'][expression.key]['pixelHash'],
          );
          return;
        }
        final source = img.decodeWebP(
          File(
            'tool/avatar_sources/llm/${character.name}/${expression.key}.webp',
          ).readAsBytesSync(),
        )!;
        // 不比较完全透明像素中被 WebP 编码器自由改写的隐藏 RGB。
        for (final pixel in source) {
          if (pixel.a == 0) pixel.setRgba(0, 0, 0, 0);
        }
        expect(restored.width, source.width);
        expect(restored.height, source.height);
        expect(restored.getPixel(0, 0).a, 0);
        expect(
          sha256.convert(restored.getBytes(order: img.ChannelOrder.rgba)),
          sha256.convert(source.getBytes(order: img.ChannelOrder.rgba)),
        );
      });
    }
  }

  test('Claude WebP 保持原 PNG 的尺寸、可见像素和透明度', () async {
    final original = img.decodePng(
      File('tool/avatar_sources/llm/claude/original.png').readAsBytesSync(),
    )!;
    final webp = img.decodeWebP(
      await StevessrCharacterAssets.load(
        StevessrCharacter.claude,
        StevessrExpression.neutral,
      ),
    )!;
    expect(webp.width, original.width);
    expect(webp.height, original.height);
    for (final image in [original, webp]) {
      for (final pixel in image) {
        if (pixel.a == 0) pixel.setRgba(0, 0, 0, 0);
      }
    }
    expect(
      sha256.convert(webp.getBytes(order: img.ChannelOrder.rgba)),
      sha256.convert(original.getBytes(order: img.ChannelOrder.rgba)),
    );
  });

  test('差分可将主图中的不透明像素替换为透明，不采用 alpha 叠加', () async {
    final patch = img.Image(width: 2, height: 2, numChannels: 4);
    final base = await StevessrCharacterAssets.load(
      StevessrCharacter.claude,
      StevessrExpression.neutral,
    );
    final restored = img.decodePng(
      restoreAvatarDelta(<String, Object>{
        'base': base,
        'patch': Uint8List.fromList(img.encodePng(patch)),
        'x': 600,
        'y': 850,
      }),
    )!;
    expect(restored.getPixel(600, 850).a, 0);
    expect(
      restored.getPixel(599, 850).a,
      img.decodeWebP(base)!.getPixel(599, 850).a,
    );
  });

  test('资产清单不打包原 PNG、源稿或完整的非默认表情', () async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final assets = manifest.listAssets();
    expect(assets, contains('assets/images/avater/llm/claude.webp'));
    expect(
      assets.any((path) => path.startsWith('tool/avatar_sources/')),
      isFalse,
    );
    expect(assets, isNot(contains('assets/images/avater/llm/claude.png')));
    expect(assets, contains('assets/images/avater/stevessr/neutral.webp'));
    expect(assets, isNot(contains('assets/images/avater/stevessr/happy.webp')));
    expect(
      assets.where(
        (path) => path.startsWith('assets/images/avater/stevessr/original_'),
      ),
      hasLength(22),
    );
    expect(
      assets.where(
        (path) =>
            path.startsWith('assets/images/avater/llm/') &&
            path.endsWith('.webp'),
      ),
      hasLength(2),
    );
  });

  test('不支持的 LLM 表情回退主图，切换角色不会产生非法下拉值', () async {
    final params = StevessrRenderParams.defaults()
        .copyWith(expression: StevessrExpression.angry)
        .copyWith(character: StevessrCharacter.claude);
    expect(params.expression, StevessrExpression.neutral);
    expect(
      StevessrCharacterAssets.usesDelta(
        params.character,
        StevessrExpression.angry,
      ),
      isFalse,
    );
    final bytes = await StevessrCharacterAssets.load(
      params.character,
      StevessrExpression.angry,
    );
    expect(img.decodeWebP(bytes), isNotNull);
  });

  testWidgets('位图导出等待表情加载，截图包含爱心而不是空白或主图', (tester) async {
    final params = StevessrRenderParams.defaults().copyWith(
      character: StevessrCharacter.claude,
      expression: StevessrExpression.love,
      width: 512,
      height: 512,
      format: StevessrFormat.png,
      transparent: true,
      characterRect: const StevessrRect(x: 0, y: 0, width: 512, height: 512),
    );
    await tester.runAsync(
      () => StevessrCharacterAssets.load(params.character, params.expression),
    );
    final key = GlobalKey();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: StevessrCanvas(
            params: params,
            logicalWidth: 256,
            repaintBoundaryKey: key,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    var complete = false;
    final pending =
        StevessrExportService.render(
          params: params,
          repaintBoundaryKey: key,
        ).then((result) {
          complete = true;
          return result;
        });
    for (var i = 0; i < 100 && !complete; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    expect(complete, isTrue, reason: '图片加载和绘制应在等待帧后完成');
    final exported = await pending;
    final actual = img.decodePng(exported.bytes)!;
    final expected = img.decodeWebP(
      File('tool/avatar_sources/llm/claude/love.webp').readAsBytesSync(),
    )!;
    final heart = expected.getPixel(490, 800);
    final sample = actual.getPixel(
      (490 * 512 / expected.width).round(),
      (800 * 512 / expected.height).round(),
    );
    expect(actual.width, 512);
    expect(actual.height, 512);
    expect(sample.a, greaterThanOrEqualTo(250));
    expect((sample.r - heart.r).abs(), lessThan(15));
    expect((sample.g - heart.g).abs(), lessThan(15));
    expect((sample.b - heart.b).abs(), lessThan(15));
  });

  test('SVG 导出嵌入还原后的爱心表情，不仅是主图', () async {
    final params = StevessrRenderParams.defaults().copyWith(
      character: StevessrCharacter.claude,
      expression: StevessrExpression.love,
      format: StevessrFormat.svg,
    );
    final result = await StevessrExportService.render(
      params: params,
      repaintBoundaryKey: GlobalKey(),
    );
    final svg = utf8.decode(result.bytes);
    final bytes = await StevessrCharacterAssets.load(
      params.character,
      params.expression,
    );
    expect(svg, contains('data:image/png;base64,${base64Encode(bytes)}'));
  });
}
