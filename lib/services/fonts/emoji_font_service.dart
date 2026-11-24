import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../network/discourse_dio.dart';

/// Color fonts are registered in private families, never in the app-wide
/// fallback list. Each file is pinned to a Git commit and verified by its
/// Git blob object ID and exact byte length before handing it to Flutter.
class EmojiFontSpec {
  const EmojiFontSpec(this.family, this.repo, this.revision, this.path,
      this.blob, this.size);
  final String family, repo, revision, path, blob;
  final int size;

  List<String> get urls => [
    'https://raw.githubusercontent.com/$repo/$revision/$path',
    'https://cdn.jsdelivr.net/gh/$repo@$revision/$path',
  ];

  static const bySet = <String, EmojiFontSpec>{
    'noto': EmojiFontSpec(
      'FluxdoEmojiNoto', 'googlefonts/noto-emoji',
      '99701e07d3d1fe1bdbcdb14964547f0fd592966f',
      '2D/fonts/Noto-COLRv1.ttf',
      'd1c82373d26e6949d81bbaefa4323f1e19f77262', 5038236,
    ),
    'twemoji': EmojiFontSpec(
      'FluxdoEmojiTwemoji', 'googlefonts/color-fonts',
      'e830e042b0e93fd5b0197a7fe9f0398f6d87f467',
      'fonts/twemoji-glyf_colr_1.ttf',
      'd59b98d3b39c64a0d55df7d481b334fac1c61e3b', 1301060,
    ),
    'openmoji': EmojiFontSpec(
      'FluxdoEmojiOpenMoji', 'hfg-gmuend/openmoji',
      '5acb7f049c45c57a98449122d470de9f09bb6794',
      'font/OpenMoji-color-glyf_colr_0/OpenMoji-color-glyf_colr_0.ttf',
      'b8fe4366a31141c57fd6fcb7b8cd477a5b7b7102', 2759076,
    ),
  };
}

/// Conservative coverage check: simple scalar emoji (optionally VS16).
/// Complex ligatures, flags, tones and keycaps stay on the image path until
/// their exact GSUB sequence coverage can be established.
class EmojiFontFace {
  const EmojiFontFace(this.family, this.coverage);
  final String family;
  final Set<int> coverage;

  static int? simpleScalar(String? unicode) {
    if (unicode == null) return null;
    final parts = unicode.split('_');
    if (parts.length > 2 || (parts.length == 2 && parts[1] != 'fe0f')) {
      return null;
    }
    final cp = int.tryParse(parts.first, radix: 16);
    if (cp == null || cp <= 0x7f || cp > 0x10ffff ||
        (cp >= 0xd800 && cp <= 0xdfff) ||
        (cp >= 0x1f1e6 && cp <= 0x1f1ff) ||
        (cp >= 0x1f3fb && cp <= 0x1f3ff)) return null;
    return cp;
  }

  String? glyphFor(String? unicode) {
    final cp = simpleScalar(unicode);
    return cp != null && coverage.contains(cp) ? String.fromCharCode(cp) : null;
  }
}

/// Read Unicode cmap formats 4 and 12; only non-zero glyph IDs count.
/// Fonts come from the pinned catalogue; malformed tables fail closed.
Set<int> emojiFontCoverage(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  int u16(int i) => data.getUint16(i);
  int u32(int i) => data.getUint32(i);
  bool fits(int start, int len, [int? end]) =>
      start >= 0 && len >= 0 && start + len <= (end ?? data.lengthInBytes);
  final result = <int>{};
  if (!fits(0, 12)) return result;
  final count = u16(4);
  if (!fits(12, count * 16)) return result;
  for (var i = 0; i < count; i++) {
    final record = 12 + i * 16;
    if (u32(record) != 0x636d6170) continue;
    final offset = u32(record + 8);
    final length = u32(record + 12);
    if (!fits(offset, length) || length < 4) return result;
    final end = offset + length;
    final tables = u16(offset + 2);
    if (!fits(offset + 4, tables * 8, end)) return result;
    final seen = <int>{};
    for (var t = 0; t < tables; t++) {
      final entry = offset + 4 + t * 8;
      final platform = u16(entry);
      final encoding = u16(entry + 2);
      if (platform != 0 && !(platform == 3 && (encoding == 1 || encoding == 10))) {
        continue;
      }
      final base = offset + u32(entry + 4);
      if (!fits(base, 2, end) || !seen.add(base)) continue;
      final format = u16(base);
      if (format == 12 && fits(base, 16, end)) {
        final len = u32(base + 4);
        final groups = u32(base + 12);
        if (len < 16 || !fits(base, len, end) || groups > (len - 16) ~/ 12) continue;
        for (var g = 0; g < groups; g++) {
          final pos = base + 16 + g * 12;
          final first = u32(pos), last = u32(pos + 4), glyph = u32(pos + 8);
          if (first > last || last > 0x10ffff || last - first > 65535) continue;
          for (var cp = first; cp <= last; cp++) {
            if (glyph + cp - first != 0) result.add(cp);
          }
        }
      } else if (format == 4 && fits(base, 16, end)) {
        final len = u16(base + 2);
        final segs = u16(base + 6) ~/ 2;
        if (segs == 0 || len < 16 || !fits(base, len, end) || 16 + segs * 8 > len) continue;
        final ends = base + 14;
        final starts = ends + segs * 2 + 2;
        final deltas = starts + segs * 2;
        final ranges = deltas + segs * 2;
        for (var g = 0; g < segs; g++) {
          final first = u16(starts + g * 2), last = u16(ends + g * 2);
          final delta = u16(deltas + g * 2), range = u16(ranges + g * 2);
          for (var cp = first; cp <= last && cp < 0xffff; cp++) {
            int glyph;
            if (range == 0) {
              glyph = (cp + delta) & 0xffff;
            } else {
              final pos = ranges + g * 2 + range + (cp - first) * 2;
              if (!fits(pos, 2, base + len)) continue;
              glyph = u16(pos);
              if (glyph != 0) glyph = (glyph + delta) & 0xffff;
            }
            if (glyph != 0) result.add(cp);
          }
        }
      }
    }
    break;
  }
  return result;
}

/// Git hashes include the object header, not only the file bytes.
Set<int>? _verifiedCoverage((EmojiFontSpec, Uint8List) input) {
  final (spec, bytes) = input;
  if (bytes.length != spec.size) return null;
  final hash = sha1.convert([
    ...'blob ${bytes.length}\u0000'.codeUnits,
    ...bytes,
  ]).toString();
  if (hash != spec.blob) return null;
  final coverage = emojiFontCoverage(bytes);
  return coverage.isEmpty ? null : coverage;
}

class EmojiFontService {
  EmojiFontService._();
  static final instance = EmojiFontService._();

  final _ready = <String, EmojiFontFace>{};
  final _loading = <String, Future<EmojiFontFace?>>{};
  final _retryAfter = <String, DateTime>{};

  // Keep the same external, cookie-free network policy as normal font downloads.
  late final Dio _dio = DiscourseDio.create(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 20),
    callTimeout: const Duration(seconds: 35),
    enableRetry: false,
    enableCfChallenge: false,
    enableCookies: false,
    enableNetworkLog: false,
  );

  EmojiFontFace? ready(String set) => _ready[set];

  Future<EmojiFontFace?> ensure(String set) {
    final spec = EmojiFontSpec.bySet[set];
    if (spec == null || kIsWeb) return Future.value(null);
    if (_ready.containsKey(set)) return Future.value(_ready[set]);
    final retry = _retryAfter[set];
    if (retry != null && DateTime.now().isBefore(retry)) return Future.value(null);
    return _loading.putIfAbsent(set, () async {
      try {
        final face = await _load(spec);
        if (face != null) {
          _ready[set] = face;
          _retryAfter.remove(set);
        } else {
          _retryAfter[set] = DateTime.now().add(const Duration(minutes: 5));
        }
        return face;
      } catch (error) {
        debugPrint('[EmojiFont] ${spec.family}: $error');
        _retryAfter[set] = DateTime.now().add(const Duration(minutes: 5));
        return null;
      } finally {
        _loading.remove(set);
      }
    });
  }

  Future<EmojiFontFace?> _load(EmojiFontSpec spec) async {
    final root = await getApplicationSupportDirectory();
    final dir = Directory('${root.path}/emoji_fonts');
    await dir.create(recursive: true);
    final file = File('${dir.path}/${spec.blob}.ttf');
    Uint8List? bytes;
    Set<int>? coverage;
    if (await file.exists()) {
      if (await file.length() == spec.size) {
        bytes = await file.readAsBytes();
        coverage = await compute(_verifiedCoverage, (spec, bytes));
      }
      if (coverage == null) {
        await file.delete();
        bytes = null;
      }
    }
    if (coverage == null) {
      for (final url in spec.urls) {
        try {
          final response = await _dio.get<ResponseBody>(url,
            options: Options(responseType: ResponseType.stream));
          if (response.statusCode != 200 || response.data == null) continue;
          final buffer = BytesBuilder(copy: false);
          await for (final chunk in response.data!.stream) {
            if (buffer.length + chunk.length > spec.size) {
              throw const FormatException('Emoji font exceeds pinned size');
            }
            buffer.add(chunk);
          }
          final downloaded = buffer.takeBytes();
          final verified = await compute(_verifiedCoverage, (spec, downloaded));
          if (verified == null) continue;
          final temporary = File('${file.path}.part');
          await temporary.writeAsBytes(downloaded, flush: true);
          await temporary.rename(file.path);
          bytes = downloaded;
          coverage = verified;
          break;
        } catch (error) {
          debugPrint('[EmojiFont] source failed: $error');
        }
      }
    }
    if (bytes == null || coverage == null) return null;
    final loader = FontLoader(spec.family)
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
    return EmojiFontFace(spec.family, coverage);
  }
}
