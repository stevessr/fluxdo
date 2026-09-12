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
    await tester.pumpAndSettle();

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
