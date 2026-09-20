import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/stevessr_render_params.dart';
import 'package:fluxdo/services/stevessr_export_service.dart';
import 'package:fluxdo/widgets/stevessr/stevessr_canvas.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('透明背景导出 PNG 保留 alpha 通道', (tester) async {
    final boundaryKey = GlobalKey();
    final params = StevessrRenderParams.defaults().copyWith(
      transparent: true,
      format: StevessrFormat.png,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: StevessrCanvas(
              params: params,
              logicalWidth: 320,
              repaintBoundaryKey: boundaryKey,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final exported = await tester.runAsync(
      () => StevessrExportService.render(
        params: params,
        repaintBoundaryKey: boundaryKey,
      ),
    );
    expect(exported, isNotNull);
    final png = img.decodePng(exported!.bytes);

    expect(png, isNotNull);
    expect(png!.numChannels, 4);
    expect(png.getPixel(0, 0).a.toInt(), 0);
  });

  testWidgets('SVG 气泡内容可以使用图片并隐藏文字', (tester) async {
    final imageData = await rootBundle.load(
      'assets/images/stevessr/happy.webp',
    );
    final imageBytes = imageData.buffer.asUint8List(
      imageData.offsetInBytes,
      imageData.lengthInBytes,
    );
    final params = StevessrRenderParams.defaults().copyWith(
      format: StevessrFormat.svg,
      bubbleContent: StevessrBubbleContent.image,
      bubbleImageBytes: imageBytes,
      bubbleImageMimeType: 'image/webp',
    );

    final exported = await StevessrExportService.render(
      params: params,
      repaintBoundaryKey: GlobalKey(),
    );
    final svg = utf8.decode(exported.bytes);

    expect(svg, contains('stevessr-bubble-image-clip'));
    expect(svg, contains('clip-path="url(#stevessr-bubble-image-clip)"'));
    expect(svg, contains('data:image/webp;base64,'));
    expect(svg, isNot(contains('<text')));
  });

  testWidgets('PNG 导出会捕获气泡内图片', (tester) async {
    final imageData = await rootBundle.load(
      'assets/images/stevessr/happy.webp',
    );
    final imageBytes = imageData.buffer.asUint8List(
      imageData.offsetInBytes,
      imageData.lengthInBytes,
    );
    final params = StevessrRenderParams.defaults().copyWith(
      bubbleContent: StevessrBubbleContent.image,
      bubbleImageBytes: imageBytes,
      bubbleImageMimeType: 'image/webp',
    );
    final boundaryKey = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StevessrCanvas(
            params: params,
            logicalWidth: 320,
            repaintBoundaryKey: boundaryKey,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final exported = await tester.runAsync(
      () => StevessrExportService.render(
        params: params,
        repaintBoundaryKey: boundaryKey,
      ),
    );
    expect(exported, isNotNull);
    expect(img.decodePng(exported!.bytes), isNotNull);
  });

  testWidgets('画布支持所有气泡使用图片内容', (tester) async {
    final imageData = await rootBundle.load(
      'assets/images/stevessr/happy.webp',
    );
    final imageBytes = imageData.buffer.asUint8List(
      imageData.offsetInBytes,
      imageData.lengthInBytes,
    );
    var params = StevessrRenderParams.defaults().copyWith(
      bubbleContent: StevessrBubbleContent.image,
      bubbleImageBytes: imageBytes,
      bubbleImageMimeType: 'image/webp',
    );
    final boundaryKey = GlobalKey();

    for (final bubble in StevessrBubble.values) {
      params = params.copyWith(bubble: bubble);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StevessrCanvas(
              params: params,
              logicalWidth: 320,
              repaintBoundaryKey: boundaryKey,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
  });
}
