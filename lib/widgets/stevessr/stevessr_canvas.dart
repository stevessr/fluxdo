import 'package:flutter/material.dart';

import '../../models/stevessr_render_params.dart';
import 'stevessr_painter.dart';

/// StevesSR 预览和截图用画布。
class StevessrCanvas extends StatelessWidget {
  const StevessrCanvas({
    super.key,
    required this.params,
    required this.logicalWidth,
    this.repaintBoundaryKey,
  });

  final StevessrRenderParams params;
  final double logicalWidth;
  final GlobalKey? repaintBoundaryKey;

  static const _assetPrefix = 'assets/images/stevessr/';

  String get _expressionAsset => '$_assetPrefix${params.expression.key}.png';

  @override
  Widget build(BuildContext context) {
    final p = params.normalized();
    final logicalHeight = logicalWidth * p.height / p.width;
    final scaleX = logicalWidth / p.width;
    final scaleY = logicalHeight / p.height;
    final character = p.characterRect;

    final content = SizedBox(
      width: logicalWidth,
      height: logicalHeight,
      child: CustomPaint(
        painter: StevessrPainter(params: p),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              left: character.x * scaleX,
              top: character.y * scaleY,
              width: character.width * scaleX,
              height: character.height * scaleY,
              child: Image.asset(
                _expressionAsset,
                fit: BoxFit.fill,
                filterQuality: FilterQuality.high,
                gaplessPlayback: true,
                errorBuilder: (context, error, stackTrace) => const SizedBox(),
              ),
            ),
          ],
        ),
      ),
    );

    return RepaintBoundary(key: repaintBoundaryKey, child: content);
  }
}
