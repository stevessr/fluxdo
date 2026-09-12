import 'dart:math' as math;

import 'package:flutter/rendering.dart';

import '../../models/stevessr_render_params.dart';
import '../../services/stevessr_text_layout.dart';

/// 绘制 StevesSR 的背景、气泡和文字。
class StevessrPainter extends CustomPainter {
  const StevessrPainter({required this.params});

  final StevessrRenderParams params;

  @override
  void paint(Canvas canvas, Size size) {
    final p = params.normalized();
    final scaleX = size.width / p.width;
    final scaleY = size.height / p.height;
    canvas.save();
    canvas.scale(scaleX, scaleY);

    if (!p.transparent) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, p.width.toDouble(), p.height.toDouble()),
        Paint()..color = p.background,
      );
    }

    _drawBubble(canvas, p);
    _drawText(canvas, p);
    canvas.restore();
  }

  void _drawBubble(Canvas canvas, StevessrRenderParams p) {
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

    switch (p.bubble) {
      case StevessrBubble.thought:
        final path = _thoughtPath(r);
        canvas.drawPath(path, fill);
        canvas.drawPath(path, stroke);
        _drawThoughtTail(canvas, r, p, fill, stroke);
      case StevessrBubble.speech:
        _drawSpeechTail(canvas, r, p, fill, stroke);
        final radius = math.min(r.width, r.height) * .16;
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(r.x, r.y, r.width, r.height),
          Radius.circular(radius),
        );
        canvas.drawRRect(rect, fill);
        canvas.drawRRect(rect, stroke);
      case StevessrBubble.cloud:
        final path = _cloudPath(r);
        canvas.drawPath(path, fill);
        canvas.drawPath(path, stroke);
        _drawCloudTail(canvas, r, p, fill, stroke);
      case StevessrBubble.shout:
        final path = _shoutPath(r);
        canvas.drawPath(path, fill);
        canvas.drawPath(path, stroke);
      case StevessrBubble.rounded:
        final radius = math.min(r.width, r.height) * .22;
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(r.x, r.y, r.width, r.height),
          Radius.circular(radius),
        );
        canvas.drawRRect(rect, fill);
        canvas.drawRRect(rect, stroke);
      case StevessrBubble.caption:
        final radius = math.min(r.width, r.height) * .08;
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(r.x, r.y, r.width, r.height),
          Radius.circular(radius),
        );
        final captionFill = Paint()
          ..color = p.bubbleFill.withValues(alpha: p.bubbleFill.a * .94)
          ..style = PaintingStyle.fill
          ..isAntiAlias = true;
        canvas.drawRRect(rect, captionFill);
        canvas.drawRRect(rect, stroke);
        final topLine = Paint()
          ..color = p.bubbleStroke.withValues(alpha: p.bubbleStroke.a * .25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(2, p.bubbleStrokeWidth * .4)
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(
          Offset(r.x + r.width * .08, r.y + r.height * .12),
          Offset(r.x + r.width * .92, r.y + r.height * .12),
          topLine,
        );
    }
  }

  Path _thoughtPath(StevessrRect r) {
    return Path()
      ..moveTo(r.x + r.width * .18, r.y)
      ..cubicTo(
        r.x + r.width * .07,
        r.y,
        r.x,
        r.y + r.height * .22,
        r.x,
        r.y + r.height * .50,
      )
      ..cubicTo(
        r.x,
        r.y + r.height * .79,
        r.x + r.width * .13,
        r.y + r.height,
        r.x + r.width * .34,
        r.y + r.height,
      )
      ..cubicTo(
        r.x + r.width * .53,
        r.y + r.height * 1.02,
        r.x + r.width * .79,
        r.y + r.height * .96,
        r.x + r.width,
        r.y + r.height * .72,
      )
      ..cubicTo(
        r.x + r.width * 1.04,
        r.y + r.height * .45,
        r.x + r.width * .95,
        r.y + r.height * .17,
        r.x + r.width * .79,
        r.y + r.height * .07,
      )
      ..cubicTo(
        r.x + r.width * .64,
        r.y - r.height * .02,
        r.x + r.width * .36,
        r.y - r.height * .02,
        r.x + r.width * .18,
        r.y,
      )
      ..close();
  }

  Path _cloudPath(StevessrRect r) {
    return Path()
      ..moveTo(r.x + r.width * .14, r.y + r.height * .24)
      ..cubicTo(
        r.x + r.width * .08,
        r.y + r.height * .02,
        r.x + r.width * .34,
        r.y - r.height * .04,
        r.x + r.width * .39,
        r.y + r.height * .12,
      )
      ..cubicTo(
        r.x + r.width * .50,
        r.y - r.height * .08,
        r.x + r.width * .72,
        r.y - r.height * .01,
        r.x + r.width * .72,
        r.y + r.height * .15,
      )
      ..cubicTo(
        r.x + r.width * .94,
        r.y + r.height * .08,
        r.x + r.width * 1.03,
        r.y + r.height * .34,
        r.x + r.width * .92,
        r.y + r.height * .47,
      )
      ..cubicTo(
        r.x + r.width * 1.05,
        r.y + r.height * .68,
        r.x + r.width * .88,
        r.y + r.height * .93,
        r.x + r.width * .72,
        r.y + r.height * .84,
      )
      ..cubicTo(
        r.x + r.width * .61,
        r.y + r.height * 1.04,
        r.x + r.width * .38,
        r.y + r.height * .98,
        r.x + r.width * .35,
        r.y + r.height * .85,
      )
      ..cubicTo(
        r.x + r.width * .16,
        r.y + r.height * .98,
        r.x - r.width * .02,
        r.y + r.height * .73,
        r.x + r.width * .08,
        r.y + r.height * .57,
      )
      ..cubicTo(
        r.x - r.width * .04,
        r.y + r.height * .42,
        r.x + r.width * .01,
        r.y + r.height * .26,
        r.x + r.width * .14,
        r.y + r.height * .24,
      )
      ..close();
  }

  Path _shoutPath(StevessrRect r) {
    final path = Path();
    final cx = r.x + r.width / 2;
    final cy = r.y + r.height / 2;
    for (var i = 0; i < 20; i++) {
      final angle = -math.pi / 2 + math.pi * 2 * i / 20;
      final outer = i.isEven;
      final rx = r.width / 2 * (outer ? 1 : .80);
      final ry = r.height / 2 * (outer ? 1 : .80);
      final point = Offset(
        cx + math.cos(angle) * rx,
        cy + math.sin(angle) * ry,
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    return path..close();
  }

  void _drawThoughtTail(
    Canvas canvas,
    StevessrRect r,
    StevessrRenderParams p,
    Paint fill,
    Paint stroke,
  ) {
    if (p.tail == StevessrTail.none) return;
    final direction = p.tail == StevessrTail.right ? 1 : -1;
    final anchor = p.tail == StevessrTail.right
        ? r.x + r.width * .74
        : r.x + r.width * .31;
    canvas.drawCircle(
      Offset(anchor, r.y + r.height + 42),
      math.max(10, r.height * .065),
      fill,
    );
    canvas.drawCircle(
      Offset(anchor, r.y + r.height + 42),
      math.max(10, r.height * .065),
      stroke,
    );
    final second = Offset(
      anchor + direction * r.width * .085,
      r.y + r.height + 82,
    );
    canvas.drawCircle(second, math.max(7, r.height * .040), fill);
    canvas.drawCircle(second, math.max(7, r.height * .040), stroke);
  }

  void _drawSpeechTail(
    Canvas canvas,
    StevessrRect r,
    StevessrRenderParams p,
    Paint fill,
    Paint stroke,
  ) {
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
    canvas.drawPath(path, fill);
    canvas.drawPath(path, stroke);
  }

  void _drawCloudTail(
    Canvas canvas,
    StevessrRect r,
    StevessrRenderParams p,
    Paint fill,
    Paint stroke,
  ) {
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
    canvas.drawCircle(first, math.max(10, r.height * .055), fill);
    canvas.drawCircle(first, math.max(10, r.height * .055), stroke);
    canvas.drawCircle(second, math.max(7, r.height * .035), fill);
    canvas.drawCircle(second, math.max(7, r.height * .035), stroke);
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
    return oldDelegate.params != params;
  }
}
