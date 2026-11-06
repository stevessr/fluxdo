import 'dart:math' as math;

import 'package:flutter/rendering.dart';

import '../../models/stevessr_render_params.dart';
import '../../services/stevessr_text_layout.dart';
import 'stevessr_bubble_shape.dart';

/// 绘制 StevesSR 的背景、气泡和文字。
class StevessrPainter extends CustomPainter {
  const StevessrPainter({
    required this.params,
    this.drawBackground = true,
    this.drawBubbleFill = true,
    this.drawBubbleStroke = true,
    this.drawText = true,
  });

  final StevessrRenderParams params;
  final bool drawBackground;
  final bool drawBubbleFill;
  final bool drawBubbleStroke;
  final bool drawText;

  @override
  void paint(Canvas canvas, Size size) {
    final p = params.normalized();
    final scaleX = size.width / p.width;
    final scaleY = size.height / p.height;
    canvas.save();
    canvas.scale(scaleX, scaleY);

    if (drawBackground && !p.transparent) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, p.width.toDouble(), p.height.toDouble()),
        Paint()..color = p.background,
      );
    }

    _drawBubble(
      canvas,
      p,
      drawFill: drawBubbleFill,
      drawStroke: drawBubbleStroke,
    );
    if (drawText && !p.usesBubbleImage) _drawText(canvas, p);
    canvas.restore();
  }

  void _drawBubble(
    Canvas canvas,
    StevessrRenderParams p, {
    required bool drawFill,
    required bool drawStroke,
  }) {
    final r = p.bubbleRect;
    final fill = Paint()
      ..color = p.bubbleFill
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final stroke = Paint()
      ..color = p.bubbleStroke
      ..style = PaintingStyle.stroke
      ..strokeWidth = p.bubbleStrokeWidth
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    void drawPath(Path path) {
      if (drawFill) canvas.drawPath(path, fill);
      if (drawStroke) canvas.drawPath(path, stroke);
    }

    switch (p.bubble) {
      case StevessrBubble.thought:
        drawPath(_bubblePath(p));
        _drawThoughtTail(
          canvas,
          r,
          p,
          fill,
          stroke,
          drawFill: drawFill,
          drawStroke: drawStroke,
        );
      case StevessrBubble.speech:
        _drawSpeechTail(
          canvas,
          r,
          p,
          fill,
          stroke,
          drawFill: drawFill,
          drawStroke: drawStroke,
        );
        drawPath(_bubblePath(p));
      case StevessrBubble.cloud:
        drawPath(_bubblePath(p));
        _drawCloudTail(
          canvas,
          r,
          p,
          fill,
          stroke,
          drawFill: drawFill,
          drawStroke: drawStroke,
        );
      case StevessrBubble.shout:
        drawPath(_bubblePath(p));
      case StevessrBubble.rounded:
        drawPath(_bubblePath(p));
      case StevessrBubble.caption:
        final captionFill = Paint()
          ..color = p.bubbleFill.withValues(alpha: p.bubbleFill.a * .94)
          ..style = PaintingStyle.fill
          ..isAntiAlias = true;
        if (drawFill) canvas.drawPath(_bubblePath(p), captionFill);
        if (drawStroke) canvas.drawPath(_bubblePath(p), stroke);
        final topLine = Paint()
          ..color = p.bubbleStroke.withValues(alpha: p.bubbleStroke.a * .25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(2, p.bubbleStrokeWidth * .4)
          ..strokeCap = StrokeCap.round;
        if (drawStroke) {
          canvas.drawLine(
            Offset(r.x + r.width * .08, r.y + r.height * .12),
            Offset(r.x + r.width * .92, r.y + r.height * .12),
            topLine,
          );
        }
    }
  }

  Path _bubblePath(StevessrRenderParams p) {
    final r = p.bubbleRect;
    return StevessrBubbleShape.path(
      p.bubble,
      Rect.fromLTWH(r.x, r.y, r.width, r.height),
    );
  }

  void _drawThoughtTail(
    Canvas canvas,
    StevessrRect r,
    StevessrRenderParams p,
    Paint fill,
    Paint stroke, {
    required bool drawFill,
    required bool drawStroke,
  }) {
    if (p.tail == StevessrTail.none) return;
    final direction = p.tail == StevessrTail.right ? 1 : -1;
    final anchor = p.tail == StevessrTail.right
        ? r.x + r.width * .74
        : r.x + r.width * .31;
    if (drawFill) {
      canvas.drawCircle(
        Offset(anchor, r.y + r.height + 42),
        math.max(10, r.height * .065),
        fill,
      );
    }
    if (drawStroke) {
      canvas.drawCircle(
        Offset(anchor, r.y + r.height + 42),
        math.max(10, r.height * .065),
        stroke,
      );
    }
    final second = Offset(
      anchor + direction * r.width * .085,
      r.y + r.height + 82,
    );
    if (drawFill) canvas.drawCircle(second, math.max(7, r.height * .040), fill);
    if (drawStroke) {
      canvas.drawCircle(second, math.max(7, r.height * .040), stroke);
    }
  }

  void _drawSpeechTail(
    Canvas canvas,
    StevessrRect r,
    StevessrRenderParams p,
    Paint fill,
    Paint stroke, {
    required bool drawFill,
    required bool drawStroke,
  }) {
    if (p.tail == StevessrTail.none) return;
    final path = Path();
    if (p.tail == StevessrTail.right) {
      path
        ..moveTo(r.x + r.width * .70, r.y + r.height * .90)
        ..lineTo(r.x + r.width * .88, r.y + r.height * 1.14)
        ..lineTo(r.x + r.width * .84, r.y + r.height * .82);
    } else {
      path
        ..moveTo(r.x + r.width * .30, r.y + r.height * .90)
        ..lineTo(r.x + r.width * .12, r.y + r.height * 1.14)
        ..lineTo(r.x + r.width * .16, r.y + r.height * .82);
    }
    path.close();
    if (drawFill) canvas.drawPath(path, fill);
    if (drawStroke) canvas.drawPath(path, stroke);
  }

  void _drawCloudTail(
    Canvas canvas,
    StevessrRect r,
    StevessrRenderParams p,
    Paint fill,
    Paint stroke, {
    required bool drawFill,
    required bool drawStroke,
  }) {
    if (p.tail == StevessrTail.none) return;
    final anchor = p.tail == StevessrTail.right
        ? r.x + r.width * .72
        : r.x + r.width * .27;
    final direction = p.tail == StevessrTail.right ? 1 : -1;
    final first = Offset(anchor, r.y + r.height + 34);
    final second = Offset(
      anchor + direction * r.width * .075,
      r.y + r.height + 73,
    );
    if (drawFill) canvas.drawCircle(first, math.max(10, r.height * .055), fill);
    if (drawStroke) {
      canvas.drawCircle(first, math.max(10, r.height * .055), stroke);
    }
    if (drawFill) canvas.drawCircle(second, math.max(7, r.height * .035), fill);
    if (drawStroke) {
      canvas.drawCircle(second, math.max(7, r.height * .035), stroke);
    }
  }

  void _drawText(Canvas canvas, StevessrRenderParams p) {
    final layout = StevessrTextLayout.fit(
      text: p.text,
      box: p.bubbleRect,
      padding: p.padding,
      minFont: p.fontMin,
      maxFont: p.fontMax,
      lineHeight: p.lineHeight,
      font: p.font,
      fontWeight: p.fontWeight,
    );
    final box = p.bubbleRect;
    final firstBaseline =
        box.y + (box.height - layout.totalHeight) / 2 + layout.fontSize * .80;
    final style = StevessrTextLayout.styleFor(
      font: p.font,
      fontSize: layout.fontSize,
      fontWeight: p.fontWeight,
      color: p.textColor,
    );

    for (var i = 0; i < layout.lines.length; i++) {
      final painter = TextPainter(
        text: TextSpan(text: layout.lines[i], style: style),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      final x = switch (p.align) {
        StevessrTextAlign.left => box.x + p.padding,
        StevessrTextAlign.center => box.x + (box.width - painter.width) / 2,
        StevessrTextAlign.right =>
          box.x + box.width - p.padding - painter.width,
      };
      final top =
          firstBaseline +
          i * layout.fontSize * layout.lineHeight -
          layout.fontSize * .80;
      painter.paint(canvas, Offset(x, top));
    }
  }

  @override
  bool shouldRepaint(covariant StevessrPainter oldDelegate) {
    return oldDelegate.params != params ||
        oldDelegate.drawBackground != drawBackground ||
        oldDelegate.drawBubbleFill != drawBubbleFill ||
        oldDelegate.drawBubbleStroke != drawBubbleStroke ||
        oldDelegate.drawText != drawText;
  }
}
