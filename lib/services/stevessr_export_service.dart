import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import '../models/stevessr_render_params.dart';
import '../utils/image_save_utils.dart';
import '../utils/screenshot_utils.dart';
import '../utils/share_utils.dart';
import 'stevessr_text_layout.dart';

/// StevesSR 导出结果。
class StevessrExportedImage {
  const StevessrExportedImage({
    required this.bytes,
    required this.extension,
    required this.mimeType,
  });

  final Uint8List bytes;
  final String extension;
  final String mimeType;
}

/// 将预览画布导出为 PNG、WebP 或 SVG。
abstract final class StevessrExportService {
  static const _assetPrefix = 'assets/images/stevessr/';

  static Future<StevessrExportedImage> render({
    required StevessrRenderParams params,
    required GlobalKey repaintBoundaryKey,
  }) async {
    final p = params.normalized();
    switch (p.format) {
      case StevessrFormat.png:
        return StevessrExportedImage(
          bytes: await _capturePng(p, repaintBoundaryKey),
          extension: 'png',
          mimeType: 'image/png',
        );
      case StevessrFormat.webp:
        final png = await _capturePng(p, repaintBoundaryKey);
        final webp = await FlutterImageCompress.compressWithList(
          png,
          quality: p.quality,
          format: CompressFormat.webp,
        );
        if (webp.isEmpty) {
          throw StateError('WebP 编码失败');
        }
        return StevessrExportedImage(
          bytes: webp,
          extension: 'webp',
          mimeType: 'image/webp',
        );
      case StevessrFormat.svg:
        return StevessrExportedImage(
          bytes: Uint8List.fromList(await _buildSvg(p)),
          extension: 'svg',
          mimeType: 'image/svg+xml',
        );
    }
  }

  static Future<Uint8List> _capturePng(
    StevessrRenderParams params,
    GlobalKey key,
  ) async {
    final boundary = key.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary || boundary.size.width <= 0) {
      throw StateError('StevesSR 预览尚未完成布局');
    }
    final pixelRatio = params.width / boundary.size.width;
    final bytes = await ScreenshotUtils.captureWidget(
      key,
      pixelRatio: pixelRatio,
    );
    if (bytes == null || bytes.isEmpty) throw StateError('截图失败');
    return bytes;
  }

  /// 保存到相册/文件选择器，沿用 FluxDO 的平台适配和提示。
  static Future<bool> save(StevessrExportedImage image) {
    return ImageSaveUtils.saveBytes(
      image.bytes,
      fileName: 'stevessr.${image.extension}',
    );
  }

  /// 分享给系统分享面板。Linux 不支持文件分享，由页面决定是否隐藏入口。
  static Future<ShareOutcome> share(StevessrExportedImage image) async {
    final file = await ShareUtils.createOutboxFile(
      'stevessr.${image.extension}',
    );
    await file.writeAsBytes(image.bytes, flush: true);
    return ShareUtils.shareFile(
      XFile(file.path, mimeType: image.mimeType),
      subject: 'StevesSR',
    );
  }

  static Future<List<int>> _buildSvg(StevessrRenderParams p) async {
    final asset = await rootBundle.load('$_assetPrefix${p.expression.key}.png');
    final imageBase64 = base64Encode(
      asset.buffer.asUint8List(asset.offsetInBytes, asset.lengthInBytes),
    );
    final bubble = _bubbleMarkup(p);
    final text = _textMarkup(p);
    final c = p.characterRect;
    final background = p.transparent
        ? ''
        : '<rect width="${p.width}" height="${p.height}" fill="${_color(p.background)}" fill-opacity="${_opacity(p.background)}"/>';
    final svg =
        '''<svg xmlns="http://www.w3.org/2000/svg" width="${p.width}" height="${p.height}" viewBox="0 0 ${p.width} ${p.height}">
$background
$bubble
$text
<image x="${c.x}" y="${c.y}" width="${c.width}" height="${c.height}" preserveAspectRatio="none" href="data:image/png;base64,$imageBase64"/>
</svg>''';
    return utf8.encode(svg);
  }

  static String _bubbleMarkup(StevessrRenderParams p) {
    final r = p.bubbleRect;
    final fill = _color(p.bubbleFill);
    final stroke = _color(p.bubbleStroke);
    final sw = _number(p.bubbleStrokeWidth);
    final attrs =
        'fill="$fill" fill-opacity="${_opacity(p.bubbleFill)}" stroke="$stroke" stroke-opacity="${_opacity(p.bubbleStroke)}" stroke-width="$sw" stroke-linejoin="round"';
    switch (p.bubble) {
      case StevessrBubble.thought:
        final d = _thoughtPath(r);
        final tail = _bubbleTailCircles(r, p, cloud: false);
        return '<path d="$d" $attrs/>$tail';
      case StevessrBubble.speech:
        final rx = mathMin(r.width, r.height) * .16;
        final tail = _speechTail(r, p, fill, stroke, sw);
        return '$tail<rect x="${r.x}" y="${r.y}" width="${r.width}" height="${r.height}" rx="$rx" $attrs/>';
      case StevessrBubble.cloud:
        final d = _cloudPath(r);
        final tail = _bubbleTailCircles(r, p, cloud: true);
        return '<path d="$d" $attrs/>$tail';
      case StevessrBubble.shout:
        return '<polygon points="${_shoutPoints(r)}" $attrs/>';
      case StevessrBubble.rounded:
        final rx = mathMin(r.width, r.height) * .22;
        return '<rect x="${r.x}" y="${r.y}" width="${r.width}" height="${r.height}" rx="$rx" $attrs/>';
      case StevessrBubble.caption:
        final rx = mathMin(r.width, r.height) * .08;
        final lineWidth = mathMax(2, p.bubbleStrokeWidth * .4);
        return '<rect x="${r.x}" y="${r.y}" width="${r.width}" height="${r.height}" rx="$rx" fill="$fill" fill-opacity="${mathMax(0, p.bubbleFill.a * .94)}" stroke="$stroke" stroke-opacity="${_opacity(p.bubbleStroke)}" stroke-width="$sw"/>'
            '<path d="M ${r.x + r.width * .08} ${r.y + r.height * .12} H ${r.x + r.width * .92}" stroke="$stroke" stroke-opacity="${mathMin(1, p.bubbleStroke.a * .25)}" stroke-width="$lineWidth" stroke-linecap="round"/>';
    }
  }

  static String _textMarkup(StevessrRenderParams p) {
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
    final firstY =
        box.y + (box.height - layout.totalHeight) / 2 + layout.fontSize * .80;
    final family = switch (p.font) {
      StevessrFont.serif => 'Noto Serif CJK SC, serif',
      StevessrFont.mono => 'Noto Sans Mono CJK SC, monospace',
      StevessrFont.rounded || StevessrFont.sans => 'MiSans, sans-serif',
    };
    final (anchor, x) = switch (p.align) {
      StevessrTextAlign.left => ('start', box.x + p.padding),
      StevessrTextAlign.center => ('middle', box.x + box.width / 2),
      StevessrTextAlign.right => ('end', box.x + box.width - p.padding),
    };
    final tspans = <String>[];
    for (var i = 0; i < layout.lines.length; i++) {
      final line = _xmlEscape(layout.lines[i]);
      final y = firstY + i * layout.fontSize * layout.lineHeight;
      tspans.add('<tspan x="$x" y="$y">$line</tspan>');
    }
    return '<text x="$x" y="$firstY" text-anchor="$anchor" fill="${_color(p.textColor)}" fill-opacity="${_opacity(p.textColor)}" font-family="${_xmlEscape(family)}" font-size="${layout.fontSize}" font-weight="${p.fontWeight}">${tspans.join()}</text>';
  }

  static String _thoughtPath(StevessrRect r) =>
      'M ${r.x + r.width * .18} ${r.y} C ${r.x + r.width * .07} ${r.y}, ${r.x} ${r.y + r.height * .22}, ${r.x} ${r.y + r.height * .50} C ${r.x} ${r.y + r.height * .79}, ${r.x + r.width * .13} ${r.y + r.height}, ${r.x + r.width * .34} ${r.y + r.height} C ${r.x + r.width * .53} ${r.y + r.height * 1.02}, ${r.x + r.width * .79} ${r.y + r.height * .96}, ${r.x + r.width} ${r.y + r.height * .72} C ${r.x + r.width * 1.04} ${r.y + r.height * .45}, ${r.x + r.width * .95} ${r.y + r.height * .17}, ${r.x + r.width * .79} ${r.y + r.height * .07} C ${r.x + r.width * .64} ${r.y - r.height * .02}, ${r.x + r.width * .36} ${r.y - r.height * .02}, ${r.x + r.width * .18} ${r.y} Z';

  static String _cloudPath(StevessrRect r) =>
      'M ${r.x + r.width * .14} ${r.y + r.height * .24} C ${r.x + r.width * .08} ${r.y + r.height * .02}, ${r.x + r.width * .34} ${r.y - r.height * .04}, ${r.x + r.width * .39} ${r.y + r.height * .12} C ${r.x + r.width * .50} ${r.y - r.height * .08}, ${r.x + r.width * .72} ${r.y - r.height * .01}, ${r.x + r.width * .72} ${r.y + r.height * .15} C ${r.x + r.width * .94} ${r.y + r.height * .08}, ${r.x + r.width * 1.03} ${r.y + r.height * .34}, ${r.x + r.width * .92} ${r.y + r.height * .47} C ${r.x + r.width * 1.05} ${r.y + r.height * .68}, ${r.x + r.width * .88} ${r.y + r.height * .93}, ${r.x + r.width * .72} ${r.y + r.height * .84} C ${r.x + r.width * .61} ${r.y + r.height * 1.04}, ${r.x + r.width * .38} ${r.y + r.height * .98}, ${r.x + r.width * .35} ${r.y + r.height * .85} C ${r.x + r.width * .16} ${r.y + r.height * .98}, ${r.x - r.width * .02} ${r.y + r.height * .73}, ${r.x + r.width * .08} ${r.y + r.height * .57} C ${r.x - r.width * .04} ${r.y + r.height * .42}, ${r.x + r.width * .01} ${r.y + r.height * .26}, ${r.x + r.width * .14} ${r.y + r.height * .24} Z';

  static String _shoutPoints(StevessrRect r) {
    final points = <String>[];
    final cx = r.x + r.width / 2;
    final cy = r.y + r.height / 2;
    for (var i = 0; i < 20; i++) {
      final angle = -3.141592653589793 / 2 + 3.141592653589793 * 2 * i / 20;
      final outer = i.isEven;
      final rx = r.width / 2 * (outer ? 1 : .80);
      final ry = r.height / 2 * (outer ? 1 : .80);
      points.add('${cx + math.cos(angle) * rx},${cy + math.sin(angle) * ry}');
    }
    return points.join(' ');
  }

  static String _bubbleTailCircles(
    StevessrRect r,
    StevessrRenderParams p, {
    required bool cloud,
  }) {
    if (p.tail == StevessrTail.none) return '';
    final anchor = p.tail == StevessrTail.right
        ? r.x + r.width * (cloud ? .72 : .74)
        : r.x + r.width * (cloud ? .27 : .31);
    final direction = p.tail == StevessrTail.right ? 1 : -1;
    final firstY = r.y + r.height + (cloud ? 34 : 42);
    final secondY = r.y + r.height + (cloud ? 73 : 82);
    final firstRadius = mathMax(10, r.height * (cloud ? .055 : .065));
    final secondRadius = mathMax(7, r.height * (cloud ? .035 : .040));
    final fill = _color(p.bubbleFill);
    final stroke = _color(p.bubbleStroke);
    final sw = _number(p.bubbleStrokeWidth);
    final fillOpacity = _opacity(p.bubbleFill);
    final strokeOpacity = _opacity(p.bubbleStroke);
    return '<circle cx="$anchor" cy="$firstY" r="$firstRadius" fill="$fill" fill-opacity="$fillOpacity" stroke="$stroke" stroke-opacity="$strokeOpacity" stroke-width="$sw"/>'
        '<circle cx="${anchor + direction * r.width * (cloud ? .075 : .085)}" cy="$secondY" r="$secondRadius" fill="$fill" fill-opacity="$fillOpacity" stroke="$stroke" stroke-opacity="$strokeOpacity" stroke-width="$sw"/>';
  }

  static String _speechTail(
    StevessrRect r,
    StevessrRenderParams p,
    String fill,
    String stroke,
    String sw,
  ) {
    if (p.tail == StevessrTail.none) return '';
    final points = p.tail == StevessrTail.right
        ? 'M ${r.x + r.width * .70} ${r.y + r.height * .90} L ${r.x + r.width * .88} ${r.y + r.height * 1.14} L ${r.x + r.width * .84} ${r.y + r.height * .82} Z'
        : 'M ${r.x + r.width * .30} ${r.y + r.height * .90} L ${r.x + r.width * .12} ${r.y + r.height * 1.14} L ${r.x + r.width * .16} ${r.y + r.height * .82} Z';
    return '<path d="$points" fill="$fill" fill-opacity="${_opacity(p.bubbleFill)}" stroke="$stroke" stroke-opacity="${_opacity(p.bubbleStroke)}" stroke-width="$sw" stroke-linejoin="round"/>';
  }

  static String _color(ui.Color color) {
    int channel(double value) => (value * 255).round().clamp(0, 255).toInt();
    String hex(int value) => value.toRadixString(16).padLeft(2, '0');
    return '#${hex(channel(color.r))}${hex(channel(color.g))}${hex(channel(color.b))}';
  }

  static String _opacity(ui.Color color) => color.a.toStringAsFixed(4);

  static String _number(double value) => value.toStringAsFixed(3);
  static double mathMin(double a, double b) => math.min(a, b);
  static double mathMax(double a, double b) => math.max(a, b);

  static String _xmlEscape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}
