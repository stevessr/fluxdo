import 'package:flutter/material.dart';
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
    // 只需要完成布局/绘制即可截图；不要用 pumpAndSettle，Image.asset 的
    // 异步解码/调度状态不应成为 PNG 导出测试的无限等待条件。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final exported = await StevessrExportService.render(
      params: params,
      repaintBoundaryKey: boundaryKey,
    );
    final png = img.decodePng(exported.bytes);

    expect(png, isNotNull);
    expect(png!.numChannels, 4);
    expect(png.getPixel(0, 0).a.toInt(), 0);
  });
}
