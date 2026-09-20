import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/stevessr_render_params.dart';
import 'stevessr_bubble_shape.dart';
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

  static const _assetRoot = 'assets/images/avater/';

  /// 角色立绘资产路径：original 渲染表情素材（表情由 expression 决定），
  /// 其余角色渲染对应目录下的固定立绘。
  String get _expressionAsset {
    final character = params.character;
    return '$_assetRoot${character.assetPath(expression: params.expression)}';
  }

  @override
  Widget build(BuildContext context) {
    final p = params.normalized();
    final logicalHeight = logicalWidth * p.height / p.width;
    final scaleX = logicalWidth / p.width;
    final scaleY = logicalHeight / p.height;
    final character = p.characterRect;
    final usesBubbleImage = p.usesBubbleImage;

    final content = SizedBox(
      width: logicalWidth,
      height: logicalHeight,
      child: CustomPaint(
        painter: StevessrPainter(
          params: p,
          drawBubbleStroke: !usesBubbleImage,
          drawText: !usesBubbleImage,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (usesBubbleImage) _buildBubbleImage(p, scaleX, scaleY),
            if (usesBubbleImage)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: StevessrPainter(
                      params: p,
                      drawBackground: false,
                      drawBubbleFill: false,
                      drawText: false,
                    ),
                  ),
                ),
              ),
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

  Widget _buildBubbleImage(
    StevessrRenderParams p,
    double scaleX,
    double scaleY,
  ) {
    final r = p.bubbleRect;
    final inset = math.max(8.0, p.bubbleStrokeWidth * 1.25);
    final width = math.max(1.0, r.width - inset * 2);
    final height = math.max(1.0, r.height - inset * 2);
    return Positioned(
      left: (r.x + inset) * scaleX,
      top: (r.y + inset) * scaleY,
      width: width * scaleX,
      height: height * scaleY,
      child: ClipPath(
        clipper: StevessrBubbleClipper(p.bubble),
        child: Image.memory(
          p.bubbleImageBytes!,
          fit: BoxFit.contain,
          alignment: Alignment.center,
          filterQuality: FilterQuality.high,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) => const SizedBox(),
        ),
      ),
    );
  }
}
