import 'package:flutter/widgets.dart';

import '../models/stevessr_render_params.dart';

/// 一次 StevesSR 文字适配的结果。
class StevessrTextLayoutResult {
  const StevessrTextLayoutResult({
    required this.fontSize,
    required this.lines,
    required this.totalHeight,
    required this.overflow,
    required this.lineHeight,
  });

  final double fontSize;
  final List<String> lines;
  final double totalHeight;
  final bool overflow;
  final double lineHeight;
}

/// StevesSR 文字换行与字号适配。
abstract final class StevessrTextLayout {
  /// 使用与绘制器一致的字体测量文字，避免 Canvas 预览和导出排版漂移。
  static StevessrTextLayoutResult fit({
    required String text,
    required StevessrRect box,
    required double padding,
    required int minFont,
    required int maxFont,
    required double lineHeight,
    required StevessrFont font,
    required int fontWeight,
  }) {
    final innerWidth = (box.width - padding * 2)
        .clamp(8.0, double.infinity)
        .toDouble();
    final innerHeight = (box.height - padding * 2)
        .clamp(8.0, double.infinity)
        .toDouble();

    for (var size = maxFont; size >= minFont; size--) {
      final lines = wrapText(
        text,
        maxWidth: innerWidth,
        fontSize: size.toDouble(),
        font: font,
        fontWeight: fontWeight,
      );
      final totalHeight = lines.length * size * lineHeight;
      final widest = lines.fold<double>(0, (max, line) {
        return max > _measure(line, size.toDouble(), font, fontWeight)
            ? max
            : _measure(line, size.toDouble(), font, fontWeight);
      });
      if (totalHeight <= innerHeight && widest <= innerWidth) {
        return StevessrTextLayoutResult(
          fontSize: size.toDouble(),
          lines: lines,
          totalHeight: totalHeight,
          overflow: false,
          lineHeight: lineHeight,
        );
      }
    }

    final lines = wrapText(
      text,
      maxWidth: innerWidth,
      fontSize: minFont.toDouble(),
      font: font,
      fontWeight: fontWeight,
    );
    return StevessrTextLayoutResult(
      fontSize: minFont.toDouble(),
      lines: lines,
      totalHeight: lines.length * minFont * lineHeight,
      overflow: true,
      lineHeight: lineHeight,
    );
  }

  static List<String> wrapText(
    String text, {
    required double maxWidth,
    required double fontSize,
    required StevessrFont font,
    required int fontWeight,
  }) {
    return text
        .replaceAll('\r', '')
        .split('\n')
        .expand(
          (paragraph) => wrapParagraph(
            paragraph,
            maxWidth: maxWidth,
            fontSize: fontSize,
            font: font,
            fontWeight: fontWeight,
          ),
        )
        .toList(growable: false);
  }

  static List<String> wrapParagraph(
    String paragraph, {
    required double maxWidth,
    required double fontSize,
    required StevessrFont font,
    required int fontWeight,
  }) {
    if (paragraph.isEmpty) return const [''];
    final lines = <String>[];
    var current = '';
    for (final grapheme in _segmentGraphemes(paragraph)) {
      final candidate = '$current$grapheme';
      if (current.isNotEmpty &&
          _measure(candidate, fontSize, font, fontWeight) > maxWidth) {
        lines.add(current.trimRight());
        current = grapheme.trimLeft();
      } else {
        current = candidate;
      }
    }
    if (current.isNotEmpty || lines.isEmpty) lines.add(current.trimRight());
    return lines;
  }

  static double _measure(
    String text,
    double fontSize,
    StevessrFont font,
    int fontWeight,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: _fontFamily(font),
          fontSize: fontSize,
          fontWeight: _fontWeight(fontWeight),
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    return painter.width;
  }

  /// 按常见组合标记和 ZWJ 组合成近似 grapheme，避免在 emoji 中间换行。
  static Iterable<String> _segmentGraphemes(String text) sync* {
    final runes = text.runes.toList(growable: false);
    var cluster = StringBuffer();
    for (var i = 0; i < runes.length; i++) {
      final rune = runes[i];
      final joinToPrevious =
          cluster.isNotEmpty &&
          (_isCombining(rune) ||
              _isVariationSelector(rune) ||
              _isSkinTone(rune));
      if (cluster.isEmpty || joinToPrevious || runes[i - 1] == 0x200d) {
        cluster.writeCharCode(rune);
      } else {
        yield cluster.toString();
        cluster = StringBuffer()..writeCharCode(rune);
      }
    }
    if (cluster.isNotEmpty) yield cluster.toString();
  }

  static bool _isCombining(int rune) {
    return (rune >= 0x300 && rune <= 0x36f) ||
        (rune >= 0x1ab0 && rune <= 0x1aff) ||
        (rune >= 0x1dc0 && rune <= 0x1dff) ||
        (rune >= 0x20d0 && rune <= 0x20ff) ||
        (rune >= 0xfe20 && rune <= 0xfe2f);
  }

  static bool _isVariationSelector(int rune) {
    return (rune >= 0xfe00 && rune <= 0xfe0f) ||
        (rune >= 0xe0100 && rune <= 0xe01ef);
  }

  static bool _isSkinTone(int rune) => rune >= 0x1f3fb && rune <= 0x1f3ff;

  static String? _fontFamily(StevessrFont font) {
    return switch (font) {
      StevessrFont.serif => 'Noto Serif CJK SC',
      StevessrFont.mono => 'Noto Sans Mono CJK SC',
      StevessrFont.rounded => 'MiSans',
      StevessrFont.sans => 'MiSans',
    };
  }

  static FontWeight _fontWeight(int value) {
    final index = ((value / 100).round().clamp(1, 9) - 1).toInt();
    return FontWeight.values[index];
  }

  /// 供 Painter 复用，避免复制字体族映射。
  static TextStyle styleFor({
    required StevessrFont font,
    required double fontSize,
    required int fontWeight,
    required Color color,
  }) {
    return TextStyle(
      fontFamily: _fontFamily(font),
      fontSize: fontSize,
      fontWeight: _fontWeight(fontWeight),
      color: color,
    );
  }
}
