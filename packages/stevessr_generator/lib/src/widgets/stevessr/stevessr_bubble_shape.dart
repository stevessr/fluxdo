import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../models/stevessr_render_params.dart';

/// 返回与 StevesSR 气泡绘制一致的裁剪路径。
abstract final class StevessrBubbleShape {
  static Path path(StevessrBubble bubble, Rect rect) {
    return switch (bubble) {
      StevessrBubble.thought => _thoughtPath(rect),
      StevessrBubble.speech => _roundedPath(rect, .16),
      StevessrBubble.cloud => _cloudPath(rect),
      StevessrBubble.shout => _shoutPath(rect),
      StevessrBubble.rounded => _roundedPath(rect, .22),
      StevessrBubble.caption => _roundedPath(rect, .08),
    };
  }

  static Path _thoughtPath(Rect r) {
    return Path()
      ..moveTo(r.left + r.width * .18, r.top)
      ..cubicTo(
        r.left + r.width * .07,
        r.top,
        r.left,
        r.top + r.height * .22,
        r.left,
        r.top + r.height * .50,
      )
      ..cubicTo(
        r.left,
        r.top + r.height * .79,
        r.left + r.width * .13,
        r.top + r.height,
        r.left + r.width * .34,
        r.top + r.height,
      )
      ..cubicTo(
        r.left + r.width * .53,
        r.top + r.height * 1.02,
        r.left + r.width * .79,
        r.top + r.height * .96,
        r.left + r.width,
        r.top + r.height * .72,
      )
      ..cubicTo(
        r.left + r.width * 1.04,
        r.top + r.height * .45,
        r.left + r.width * .95,
        r.top + r.height * .17,
        r.left + r.width * .79,
        r.top + r.height * .07,
      )
      ..cubicTo(
        r.left + r.width * .64,
        r.top - r.height * .02,
        r.left + r.width * .36,
        r.top - r.height * .02,
        r.left + r.width * .18,
        r.top,
      )
      ..close();
  }

  static Path _cloudPath(Rect r) {
    return Path()
      ..moveTo(r.left + r.width * .14, r.top + r.height * .24)
      ..cubicTo(
        r.left + r.width * .08,
        r.top + r.height * .02,
        r.left + r.width * .34,
        r.top - r.height * .04,
        r.left + r.width * .39,
        r.top + r.height * .12,
      )
      ..cubicTo(
        r.left + r.width * .50,
        r.top - r.height * .08,
        r.left + r.width * .72,
        r.top - r.height * .01,
        r.left + r.width * .72,
        r.top + r.height * .15,
      )
      ..cubicTo(
        r.left + r.width * .94,
        r.top + r.height * .08,
        r.left + r.width * 1.03,
        r.top + r.height * .34,
        r.left + r.width * .92,
        r.top + r.height * .47,
      )
      ..cubicTo(
        r.left + r.width * 1.05,
        r.top + r.height * .68,
        r.left + r.width * .88,
        r.top + r.height * .93,
        r.left + r.width * .72,
        r.top + r.height * .84,
      )
      ..cubicTo(
        r.left + r.width * .61,
        r.top + r.height * 1.04,
        r.left + r.width * .38,
        r.top + r.height * .98,
        r.left + r.width * .35,
        r.top + r.height * .85,
      )
      ..cubicTo(
        r.left + r.width * .16,
        r.top + r.height * .98,
        r.left - r.width * .02,
        r.top + r.height * .73,
        r.left + r.width * .08,
        r.top + r.height * .57,
      )
      ..cubicTo(
        r.left - r.width * .04,
        r.top + r.height * .42,
        r.left + r.width * .01,
        r.top + r.height * .26,
        r.left + r.width * .14,
        r.top + r.height * .24,
      )
      ..close();
  }

  static Path _shoutPath(Rect r) {
    final path = Path();
    final cx = r.left + r.width / 2;
    final cy = r.top + r.height / 2;
    for (var i = 0; i < 20; i++) {
      final angle = -math.pi / 2 + math.pi * 2 * i / 20;
      final radius = i.isEven ? 1.0 : .80;
      final point = Offset(
        cx + math.cos(angle) * r.width / 2 * radius,
        cy + math.sin(angle) * r.height / 2 * radius,
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    return path..close();
  }

  static Path _roundedPath(Rect rect, double radiusFactor) {
    final radius = math.min(rect.width, rect.height) * radiusFactor;
    return Path()
      ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
  }
}

/// 将图片裁剪到当前气泡的轮廓内。
class StevessrBubbleClipper extends CustomClipper<Path> {
  const StevessrBubbleClipper(this.bubble);

  final StevessrBubble bubble;

  @override
  Path getClip(Size size) {
    return StevessrBubbleShape.path(bubble, Offset.zero & size);
  }

  @override
  bool shouldReclip(covariant StevessrBubbleClipper oldClipper) {
    return oldClipper.bubble != bubble;
  }
}
