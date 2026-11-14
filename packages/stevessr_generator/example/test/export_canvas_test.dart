import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:stevessr_generator/stevessr_generator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('transparent PNG canvas export retains alpha', (tester) async {
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
}
