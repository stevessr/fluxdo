import 'dart:ui';

/// StevesSR 可用的角色表情。
enum StevessrExpression { neutral, pout, smug, surprised, happy, cry, original }

/// StevesSR 可用的气泡造型。
enum StevessrBubble { thought, speech, cloud, shout, rounded, caption }

enum StevessrFont { sans, serif, mono, rounded }

enum StevessrTextAlign { left, center, right }

enum StevessrTail { left, right, none }

enum StevessrFormat { png, webp, svg }

extension StevessrExpressionKey on StevessrExpression {
  String get key => name;
}

extension StevessrBubbleKey on StevessrBubble {
  String get key => name;
}

extension StevessrFontKey on StevessrFont {
  String get key => name;
}

extension StevessrTextAlignKey on StevessrTextAlign {
  String get key => name;
}

extension StevessrTailKey on StevessrTail {
  String get key => name;
}

extension StevessrFormatKey on StevessrFormat {
  String get key => name;
}

/// 源 API 中用于描述气泡和角色的位置矩形。
class StevessrRect {
  const StevessrRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final double x;
  final double y;
  final double width;
  final double height;

  StevessrRect copyWith({double? x, double? y, double? width, double? height}) {
    return StevessrRect(
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is StevessrRect &&
        other.x == x &&
        other.y == y &&
        other.width == width &&
        other.height == height;
  }

  @override
  int get hashCode => Object.hash(x, y, width, height);
}

/// StevesSR 生成参数。
///
/// 参数范围与源项目 `parseRenderParams` 保持一致，页面控件只修改这个模型，
/// 绘制器和导出器不直接依赖表单状态。
class StevessrRenderParams {
  const StevessrRenderParams({
    required this.text,
    required this.expression,
    required this.bubble,
    required this.format,
    required this.width,
    required this.height,
    required this.transparent,
    required this.background,
    required this.bubbleFill,
    required this.bubbleStroke,
    required this.bubbleStrokeWidth,
    required this.textColor,
    required this.font,
    required this.fontWeight,
    required this.fontMin,
    required this.fontMax,
    required this.lineHeight,
    required this.padding,
    required this.align,
    required this.tail,
    required this.quality,
    required this.bubbleRect,
    required this.characterRect,
  });

  factory StevessrRenderParams.defaults() {
    return const StevessrRenderParams(
      text: '今天也要\n可可爱爱地\n摸鱼一下！',
      expression: StevessrExpression.neutral,
      bubble: StevessrBubble.thought,
      format: StevessrFormat.png,
      width: 1254,
      height: 1254,
      transparent: false,
      background: Color(0xffffffff),
      bubbleFill: Color(0xffffffff),
      bubbleStroke: Color(0xff071716),
      bubbleStrokeWidth: 15.048,
      textColor: Color(0xff111111),
      font: StevessrFont.sans,
      fontWeight: 600,
      fontMin: 23,
      fontMax: 71,
      lineHeight: 1.15,
      padding: 45,
      align: StevessrTextAlign.center,
      tail: StevessrTail.right,
      quality: 90,
      bubbleRect: StevessrRect(x: 65, y: 66, width: 665, height: 385),
      characterRect: StevessrRect(x: 464, y: 451, width: 803, height: 803),
    );
  }

  final String text;
  final StevessrExpression expression;
  final StevessrBubble bubble;
  final StevessrFormat format;
  final int width;
  final int height;
  final bool transparent;
  final Color background;
  final Color bubbleFill;
  final Color bubbleStroke;
  final double bubbleStrokeWidth;
  final Color textColor;
  final StevessrFont font;
  final int fontWeight;
  final int fontMin;
  final int fontMax;
  final double lineHeight;
  final double padding;
  final StevessrTextAlign align;
  final StevessrTail tail;
  final int quality;
  final StevessrRect bubbleRect;
  final StevessrRect characterRect;

  /// 将用户输入限制到源 API 的安全范围。
  StevessrRenderParams normalized() {
    final safeWidth = width.clamp(320, 2048).toInt();
    final safeHeight = height.clamp(320, 2048).toInt();
    final defaultBubble = StevessrRect(
      x: (safeWidth * .052).roundToDouble(),
      y: (safeHeight * .053).roundToDouble(),
      width: (safeWidth * .530).roundToDouble(),
      height: (safeHeight * .307).roundToDouble(),
    );
    final defaultCharacter = StevessrRect(
      x: (safeWidth * .37).roundToDouble(),
      y: (safeHeight * .36).roundToDouble(),
      width: (safeWidth * .64).roundToDouble(),
      height: (safeHeight * .64).roundToDouble(),
    );
    final maxFont = fontMax.clamp(12, 220).toInt();
    final minFont = fontMin.clamp(8, maxFont).toInt();

    return StevessrRenderParams(
      text: _truncateText(text),
      expression: expression,
      bubble: bubble,
      format: format,
      width: safeWidth,
      height: safeHeight,
      transparent: transparent,
      background: background,
      bubbleFill: bubbleFill,
      bubbleStroke: bubbleStroke,
      bubbleStrokeWidth: bubbleStrokeWidth.clamp(1, 60).toDouble(),
      textColor: textColor,
      font: font,
      fontWeight: fontWeight.clamp(100, 900).toInt(),
      fontMin: minFont,
      fontMax: maxFont,
      lineHeight: lineHeight.clamp(.8, 2.0).toDouble(),
      padding: padding.clamp(0, 180).toDouble(),
      align: align,
      tail: tail,
      quality: quality.clamp(20, 100).toInt(),
      bubbleRect: _normalizeBubble(
        bubbleRect,
        defaultBubble,
        safeWidth,
        safeHeight,
      ),
      characterRect: _normalizeCharacter(
        characterRect,
        defaultCharacter,
        safeWidth,
        safeHeight,
      ),
    );
  }

  StevessrRect _normalizeBubble(
    StevessrRect value,
    StevessrRect fallback,
    int safeWidth,
    int safeHeight,
  ) {
    return StevessrRect(
      x: value.x.isFinite
          ? value.x.clamp(-safeWidth, safeWidth * 2).toDouble()
          : fallback.x,
      y: value.y.isFinite
          ? value.y.clamp(-safeHeight, safeHeight * 2).toDouble()
          : fallback.y,
      width: value.width.isFinite
          ? value.width.clamp(120, safeWidth * 1.5).toDouble()
          : fallback.width,
      height: value.height.isFinite
          ? value.height.clamp(90, safeHeight * 1.5).toDouble()
          : fallback.height,
    );
  }

  StevessrRect _normalizeCharacter(
    StevessrRect value,
    StevessrRect fallback,
    int safeWidth,
    int safeHeight,
  ) {
    return StevessrRect(
      x: value.x.isFinite
          ? value.x.clamp(-safeWidth, safeWidth * 2).toDouble()
          : fallback.x,
      y: value.y.isFinite
          ? value.y.clamp(-safeHeight, safeHeight * 2).toDouble()
          : fallback.y,
      width: value.width.isFinite
          ? value.width.clamp(64, safeWidth * 2).toDouble()
          : fallback.width,
      height: value.height.isFinite
          ? value.height.clamp(64, safeHeight * 2).toDouble()
          : fallback.height,
    );
  }

  StevessrRenderParams copyWith({
    String? text,
    StevessrExpression? expression,
    StevessrBubble? bubble,
    StevessrFormat? format,
    int? width,
    int? height,
    bool? transparent,
    Color? background,
    Color? bubbleFill,
    Color? bubbleStroke,
    double? bubbleStrokeWidth,
    Color? textColor,
    StevessrFont? font,
    int? fontWeight,
    int? fontMin,
    int? fontMax,
    double? lineHeight,
    double? padding,
    StevessrTextAlign? align,
    StevessrTail? tail,
    int? quality,
    StevessrRect? bubbleRect,
    StevessrRect? characterRect,
  }) {
    return StevessrRenderParams(
      text: text ?? this.text,
      expression: expression ?? this.expression,
      bubble: bubble ?? this.bubble,
      format: format ?? this.format,
      width: width ?? this.width,
      height: height ?? this.height,
      transparent: transparent ?? this.transparent,
      background: background ?? this.background,
      bubbleFill: bubbleFill ?? this.bubbleFill,
      bubbleStroke: bubbleStroke ?? this.bubbleStroke,
      bubbleStrokeWidth: bubbleStrokeWidth ?? this.bubbleStrokeWidth,
      textColor: textColor ?? this.textColor,
      font: font ?? this.font,
      fontWeight: fontWeight ?? this.fontWeight,
      fontMin: fontMin ?? this.fontMin,
      fontMax: fontMax ?? this.fontMax,
      lineHeight: lineHeight ?? this.lineHeight,
      padding: padding ?? this.padding,
      align: align ?? this.align,
      tail: tail ?? this.tail,
      quality: quality ?? this.quality,
      bubbleRect: bubbleRect ?? this.bubbleRect,
      characterRect: characterRect ?? this.characterRect,
    ).normalized();
  }

  static String _truncateText(String value) {
    final runes = value.runes.toList(growable: false);
    if (runes.length <= 500) return value;
    return String.fromCharCodes(runes.take(500));
  }
}
