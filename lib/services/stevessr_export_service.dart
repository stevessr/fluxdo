import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_avif/flutter_avif.dart' as avif;
import 'package:image/image.dart' as img;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
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
    this.containsTransparency,
  });

  final Uint8List bytes;
  final String extension;
  final String mimeType;

  /// Useful for AVIF uploads: the pure-Dart image package cannot decode AVIF.
  /// null means that the upload layer must inspect the encoded image instead.
  final bool? containsTransparency;
}

/// 将预览画布导出为 PNG、WebP、AVIF、JPEG 或 SVG。
abstract final class StevessrExportService {
  static const _assetPrefix = 'assets/images/stevessr/';
  static const _touhouAssetPrefix = 'assets/images/touhou/';

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
        final webp = await encodeWebpPng(png, quality: p.quality);
        return StevessrExportedImage(
          bytes: webp,
          extension: 'webp',
          mimeType: 'image/webp',
        );
      case StevessrFormat.avif:
        final png = await _capturePng(p, repaintBoundaryKey);
        final encoded = await encodeAvifPng(png, quality: p.quality);
        return StevessrExportedImage(
          bytes: encoded,
          extension: 'avif',
          mimeType: 'image/avif',
          containsTransparency: p.transparent,
        );
      case StevessrFormat.jpeg:
        if (p.transparent || p.background.a < 1) {
          throw StateError('JPEG 不支持透明背景，请选择 PNG、WebP 或 AVIF');
        }
        final png = await _capturePng(p, repaintBoundaryKey);
        final encoded = await encodeJpegPng(png, quality: p.quality);
        return StevessrExportedImage(
          bytes: encoded,
          extension: 'jpg',
          mimeType: 'image/jpeg',
          containsTransparency: false,
        );
      case StevessrFormat.svg:
        return StevessrExportedImage(
          bytes: Uint8List.fromList(await _buildSvg(p)),
          extension: 'svg',
          mimeType: 'image/svg+xml',
        );
    }
  }

  /// WebP 编码不能依赖 flutter_image_compress：它没有 Linux/Windows
  /// 实现，macOS 也不支持 WebP。统一在 isolate 中编码，以免桌面端保存失败，
  /// 或在大画布转换时阻塞预览。质量 100 使用无损 WebP；有损编码的 alpha
  /// 仍以 100% 质量保存，避免透明边缘出现白边/黑边。
  @visibleForTesting
  static Future<Uint8List> encodeWebpPng(
    Uint8List png, {
    required int quality,
  }) async {
    if (png.isEmpty) throw StateError('待编码 PNG 数据为空');
    final webp = await compute(
      _encodeWebpBytes,
      (png: png, quality: quality.clamp(20, 100).toInt()),
    );
    if (webp.length < 16 ||
        webp[0] != 0x52 || webp[1] != 0x49 ||
        webp[2] != 0x46 || webp[3] != 0x46 ||
        webp[8] != 0x57 || webp[9] != 0x45 ||
        webp[10] != 0x42 || webp[11] != 0x50) {
      throw StateError('WebP 编码失败：输出格式无效');
    }
    return webp;
  }

  /// Use the AVIF encoder already bundled with FluxDO. Quality maps onto
  /// libavif's 0..63 quantizer scale (smaller is better). Keep the alpha
  /// quantizer at zero even for lossy images so transparent edges stay intact.
  @visibleForTesting
  static Future<Uint8List> encodeAvifPng(
    Uint8List png, {
    required int quality,
  }) async {
    if (png.isEmpty) throw StateError('待编码 PNG 数据为空');
    final safeQuality = quality.clamp(20, 100).toInt();
    final quantizer = ((100 - safeQuality) * 0.55).round().clamp(0, 63);
    final encoded = await avif.encodeAvif(
      png,
      speed: 8,
      minQuantizer: quantizer,
      maxQuantizer: quantizer,
      minQuantizerAlpha: 0,
      maxQuantizerAlpha: 0,
    );
    // ISO BMFF: [box size][ftyp][major/compatible brands].
    // Reject empty/PNG output rather than handing a mislabeled file to save.
    if (encoded.length < 20 ||
        encoded[4] != 0x66 || encoded[5] != 0x74 ||
        encoded[6] != 0x79 || encoded[7] != 0x70 ||
        !_hasAvifBrand(encoded)) {
      throw StateError('AVIF 编码失败：输出格式无效');
    }
    return encoded;
  }

  static bool _hasAvifBrand(Uint8List bytes) {
    final limit = math.min(bytes.length - 3, 40);
    for (var i = 8; i < limit; i += 4) {
      if (bytes[i] == 0x61 && bytes[i + 1] == 0x76 &&
          bytes[i + 2] == 0x69 && bytes[i + 3] == 0x66) {
        return true; // avif
      }
    }
    return false;
  }

  @visibleForTesting
  static Future<Uint8List> encodeJpegPng(
    Uint8List png, {
    required int quality,
  }) async {
    if (png.isEmpty) throw StateError('待编码 PNG 数据为空');
    final jpeg = await compute(
      _encodeJpegBytes,
      (png: png, quality: quality.clamp(20, 100).toInt()),
    );
    if (jpeg.length < 4 ||
        jpeg[0] != 0xff || jpeg[1] != 0xd8 ||
        jpeg[jpeg.length - 2] != 0xff || jpeg.last != 0xd9) {
      throw StateError('JPEG 编码失败：输出格式无效');
    }
    return jpeg;
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
      subject: '表情包',
    );
  }

  static Future<List<int>> _buildSvg(StevessrRenderParams p) async {
    final characterAsset = p.character == StevessrCharacter.original
        ? '$_assetPrefix${p.expression.key}.png'
        : '$_touhouAssetPrefix${p.character.key}.png';
    final asset = await rootBundle.load(characterAsset);
    final imageBase64 = base64Encode(
      asset.buffer.asUint8List(asset.offsetInBytes, asset.lengthInBytes),
    );
    final usesBubbleImage = p.usesBubbleImage;
    final bubble = _bubbleMarkup(
      p,
      drawFill: true,
      drawStroke: !usesBubbleImage,
    );
    final bubbleImage = usesBubbleImage ? _bubbleImageMarkup(p) : '';
    final bubbleStroke = usesBubbleImage
        ? _bubbleMarkup(p, drawFill: false, drawStroke: true)
        : '';
    final text = usesBubbleImage ? '' : _textMarkup(p);
    final c = p.characterRect;
    final background = p.transparent
        ? ''
        : '<rect width="${p.width}" height="${p.height}" fill="${_color(p.background)}" fill-opacity="${_opacity(p.background)}"/>';
    final svg =
        '''<svg xmlns="http://www.w3.org/2000/svg" width="${p.width}" height="${p.height}" viewBox="0 0 ${p.width} ${p.height}">
$background
$bubble
$bubbleImage
$bubbleStroke
$text
<image x="${c.x}" y="${c.y}" width="${c.width}" height="${c.height}" preserveAspectRatio="none" href="data:image/png;base64,$imageBase64"/>
</svg>''';
    return utf8.encode(svg);
  }

  static String _bubbleMarkup(
    StevessrRenderParams p, {
    required bool drawFill,
    required bool drawStroke,
  }) {
    final r = p.bubbleRect;
    final fill = _color(p.bubbleFill);
    final stroke = _color(p.bubbleStroke);
    final sw = _number(p.bubbleStrokeWidth);
    final attrs = _paintAttrs(p, drawFill: drawFill, drawStroke: drawStroke);
    switch (p.bubble) {
      case StevessrBubble.thought:
        final d = _thoughtPath(r);
        final tail = _bubbleTailCircles(
          r,
          p,
          cloud: false,
          drawFill: drawFill,
          drawStroke: drawStroke,
        );
        return '<path d="$d" $attrs/>$tail';
      case StevessrBubble.speech:
        final rx = mathMin(r.width, r.height) * .16;
        final tail = _speechTail(
          r,
          p,
          fill,
          stroke,
          sw,
          drawFill: drawFill,
          drawStroke: drawStroke,
        );
        return '$tail<rect x="${r.x}" y="${r.y}" width="${r.width}" height="${r.height}" rx="$rx" $attrs/>';
      case StevessrBubble.cloud:
        final d = _cloudPath(r);
        final tail = _bubbleTailCircles(
          r,
          p,
          cloud: true,
          drawFill: drawFill,
          drawStroke: drawStroke,
        );
        return '<path d="$d" $attrs/>$tail';
      case StevessrBubble.shout:
        return '<polygon points="${_shoutPoints(r)}" $attrs/>';
      case StevessrBubble.rounded:
        final rx = mathMin(r.width, r.height) * .22;
        return '<rect x="${r.x}" y="${r.y}" width="${r.width}" height="${r.height}" rx="$rx" $attrs/>';
      case StevessrBubble.caption:
        final rx = mathMin(r.width, r.height) * .08;
        final lineWidth = mathMax(2, p.bubbleStrokeWidth * .4);
        final captionAttrs = [
          drawFill
              ? 'fill="$fill" fill-opacity="${p.bubbleFill.a * .94}"'
              : 'fill="none"',
          drawStroke
              ? 'stroke="$stroke" stroke-opacity="${_opacity(p.bubbleStroke)}" stroke-width="$sw" stroke-linejoin="round"'
              : 'stroke="none"',
        ].join(' ');
        final line = drawStroke
            ? '<path d="M ${r.x + r.width * .08} ${r.y + r.height * .12} H ${r.x + r.width * .92}" stroke="$stroke" stroke-opacity="${mathMin(1, p.bubbleStroke.a * .25)}" stroke-width="$lineWidth" stroke-linecap="round"/>'
            : '';
        return '<rect x="${r.x}" y="${r.y}" width="${r.width}" height="${r.height}" rx="$rx" $captionAttrs/>$line';
    }
  }

  static String _paintAttrs(
    StevessrRenderParams p, {
    required bool drawFill,
    required bool drawStroke,
  }) {
    final fill = _color(p.bubbleFill);
    final stroke = _color(p.bubbleStroke);
    final fillAttrs = drawFill
        ? 'fill="$fill" fill-opacity="${_opacity(p.bubbleFill)}"'
        : 'fill="none"';
    final strokeAttrs = drawStroke
        ? 'stroke="$stroke" stroke-opacity="${_opacity(p.bubbleStroke)}" stroke-width="${_number(p.bubbleStrokeWidth)}" stroke-linejoin="round"'
        : 'stroke="none"';
    return '$fillAttrs $strokeAttrs';
  }

  static String _bubbleImageMarkup(StevessrRenderParams p) {
    final bytes = p.bubbleImageBytes;
    if (bytes == null || bytes.isEmpty) return '';

    final r = p.bubbleRect;
    final inset = mathMax(8, p.bubbleStrokeWidth * 1.25);
    final imageRect = StevessrRect(
      x: r.x + inset,
      y: r.y + inset,
      width: mathMax(1, r.width - inset * 2),
      height: mathMax(1, r.height - inset * 2),
    );
    final clip = _bubbleImageClipPath(p.bubble, imageRect);
    final mimeType = _xmlEscape(p.bubbleImageMimeType ?? 'image/png');
    final imageBase64 = base64Encode(bytes);
    const clipId = 'stevessr-bubble-image-clip';
    return '<defs><clipPath id="$clipId">$clip</clipPath></defs>'
        '<image x="${imageRect.x}" y="${imageRect.y}" width="${imageRect.width}" height="${imageRect.height}" preserveAspectRatio="xMidYMid meet" clip-path="url(#$clipId)" href="data:$mimeType;base64,$imageBase64"/>';
  }

  static String _bubbleImageClipPath(StevessrBubble bubble, StevessrRect rect) {
    return switch (bubble) {
      StevessrBubble.thought => '<path d="${_thoughtPath(rect)}"/>',
      StevessrBubble.speech =>
        '<rect x="${rect.x}" y="${rect.y}" width="${rect.width}" height="${rect.height}" rx="${mathMin(rect.width, rect.height) * .16}"/>',
      StevessrBubble.cloud => '<path d="${_cloudPath(rect)}"/>',
      StevessrBubble.shout => '<polygon points="${_shoutPoints(rect)}"/>',
      StevessrBubble.rounded =>
        '<rect x="${rect.x}" y="${rect.y}" width="${rect.width}" height="${rect.height}" rx="${mathMin(rect.width, rect.height) * .22}"/>',
      StevessrBubble.caption =>
        '<rect x="${rect.x}" y="${rect.y}" width="${rect.width}" height="${rect.height}" rx="${mathMin(rect.width, rect.height) * .08}"/>',
    };
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
    required bool drawFill,
    required bool drawStroke,
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
    final attrs = _paintAttrs(p, drawFill: drawFill, drawStroke: drawStroke);
    return '<circle cx="$anchor" cy="$firstY" r="$firstRadius" $attrs/>'
        '<circle cx="${anchor + direction * r.width * (cloud ? .075 : .085)}" cy="$secondY" r="$secondRadius" $attrs/>';
  }

  static String _speechTail(
    StevessrRect r,
    StevessrRenderParams p,
    String fill,
    String stroke,
    String sw, {
    required bool drawFill,
    required bool drawStroke,
  }) {
    if (p.tail == StevessrTail.none) return '';
    final points = p.tail == StevessrTail.right
        ? 'M ${r.x + r.width * .70} ${r.y + r.height * .90} L ${r.x + r.width * .88} ${r.y + r.height * 1.14} L ${r.x + r.width * .84} ${r.y + r.height * .82} Z'
        : 'M ${r.x + r.width * .30} ${r.y + r.height * .90} L ${r.x + r.width * .12} ${r.y + r.height * 1.14} L ${r.x + r.width * .16} ${r.y + r.height * .82} Z';
    final fillAttrs = drawFill
        ? 'fill="$fill" fill-opacity="${_opacity(p.bubbleFill)}"'
        : 'fill="none"';
    final strokeAttrs = drawStroke
        ? 'stroke="$stroke" stroke-opacity="${_opacity(p.bubbleStroke)}" stroke-width="$sw" stroke-linejoin="round"'
        : 'stroke="none"';
    return '<path d="$points" $fillAttrs $strokeAttrs/>';
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

/// 顶层函数才能被 compute 移入后台 isolate。
Uint8List _encodeWebpBytes(({Uint8List png, int quality}) request) {
  final image = img.decodePng(request.png);
  if (image == null) throw FormatException('无法解码画布 PNG');
  return img.encodeWebP(
    image,
    singleFrame: true,
    lossless: request.quality == 100,
    quality: request.quality,
    alphaQuality: 100,
    exact: true,
  );
}

/// JPEG has no alpha channel. Guard against accidental transparency in source
/// PNG as well as the form-level transparency check: never discard user pixels.
Uint8List _encodeJpegBytes(({Uint8List png, int quality}) request) {
  final image = img.decodePng(request.png);
  if (image == null) throw FormatException('无法解码画布 PNG');
  if (image.hasAlpha && image.any((pixel) => pixel.aNormalized < 1.0)) {
    throw StateError('JPEG 不支持透明像素，请选择 PNG、WebP 或 AVIF');
  }
  return img.encodeJpg(image, quality: request.quality);
}
