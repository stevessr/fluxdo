import 'package:emoji_extension/emoji_extension.dart' hide Emoji;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/preferences_provider.dart';
import '../../services/discourse_cache_manager.dart';
import '../../services/emoji_handler.dart';

/// Maps standard emoji shortcodes to Fluent artwork without changing the
/// original Discourse shortcode or replacing site-uploaded custom emoji.
///
/// Assets are fetched lazily via the existing shared emoji cache; the selected
/// style is never downloaded until the user explicitly opts in.
class EmojiStyleAssets {
  EmojiStyleAssets._();

  static final Map<String, String?> _unicodeCache = <String, String?>{};

  static String? unicodeFor(String name) {
    final normalized = name.trim().replaceAll(RegExp(r'^:+|:+$'), '').toLowerCase();
    if (normalized.isEmpty) return null;
    if (_unicodeCache.containsKey(normalized)) return _unicodeCache[normalized];

    // Emoji runs normally carry a Discourse shortcode. Literal Unicode glyphs
    // may also reach this builder through generated previews.
    final String glyph;
    if (name.trim().emojis.onlyOne) {
      glyph = name.trim();
    } else {
      final shortcode = ':$normalized:';
      glyph = shortcode.emojis.fromShortcodes();
      if (glyph == shortcode || !glyph.emojis.onlyOne) {
        _unicodeCache[normalized] = null;
        return null;
      }
    }
    final unicode = glyph.runes.map((r) => r.toRadixString(16)).join('-');
    // Keep the bounded cache small even if a server sends unique emoji names.
    if (_unicodeCache.length >= 4096) _unicodeCache.clear();
    _unicodeCache[normalized] = unicode;
    return unicode;
  }

  static String? urlFor(String name, EmojiRenderStyle style) {
    if (style == EmojiRenderStyle.normal) return null;
    if (EmojiHandler().isCustomEmoji(name)) return null;
    final unicode = unicodeFor(name);
    if (unicode == null) return null;
    return urlForUnicode(unicode, style);
  }

  /// A separate, pure URL builder makes source style routing testable.
  static String? urlForUnicode(String unicode, EmojiRenderStyle style) {
    if (style == EmojiRenderStyle.normal || unicode.isEmpty) return null;
    final pkg = switch (style) {
      EmojiRenderStyle.normal => null,
      EmojiRenderStyle.threeD => 'fluent-emoji-3d',
      EmojiRenderStyle.animated => _animatedPackage(unicode),
    };
    if (pkg == null) return null;
    return 'https://registry.npmmirror.com/@lobehub/$pkg/latest/files/assets/$unicode.webp';
  }

  static String _animatedPackage(String unicode) {
    final first = int.tryParse(unicode.split('-').first, radix: 16) ?? 0;
    if (first < 0x1f469) return 'fluent-emoji-anim-1';
    if (first < 0x1f620) return 'fluent-emoji-anim-2';
    if (first < 0x1f9a0) return 'fluent-emoji-anim-3';
    return 'fluent-emoji-anim-4';
  }
}

/// One widget for post HTML, chat reactions, editor/picker and inline text.
/// Any unsupported/missing Fluent asset falls back to the server's real emoji.
class StyledEmojiImage extends ConsumerWidget {
  const StyledEmojiImage({
    super.key,
    required this.name,
    this.serverUrl,
    this.width,
    this.height,
    this.cacheWidth,
    this.fit = BoxFit.contain,
    this.gaplessPlayback = true,
    this.showPlaceholder = false,
    this.errorFallback,
  });

  final String name;
  final String? serverUrl;
  final double? width;
  final double? height;
  final int? cacheWidth;
  final BoxFit fit;
  final bool gaplessPlayback;
  final bool showPlaceholder;
  final Widget? errorFallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = ref.watch(
      preferencesProvider.select((p) => p.emojiRenderStyle),
    );
    return AnimatedBuilder(
      animation: EmojiHandler(),
      builder: (context, _) {
        final regularUrl = EmojiHandler().getEmojiUrl(name, serverUrl: serverUrl);
        final styledUrl = EmojiStyleAssets.urlFor(name, style);
        Widget normalImage() => _image(
          context,
          regularUrl,
          onError: errorFallback ?? Text(
            name.isEmpty ? ':?:' : ':$name:',
            maxLines: 1,
            overflow: TextOverflow.clip,
          ),
        );
        if (styledUrl == null || styledUrl == regularUrl) {
          return normalImage();
        }
        return _image(context, styledUrl, onError: normalImage());
      },
    );
  }

  Widget _image(BuildContext context, String url, {required Widget onError}) => Image(
    image: ResizeImage.resizeIfNeeded(
      cacheWidth,
      null,
      emojiImageProvider(url),
    ),
    width: width,
    height: height,
    fit: fit,
    gaplessPlayback: gaplessPlayback,
    frameBuilder: showPlaceholder
        ? (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded || frame != null) return child;
            return DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.onSurfaceVariant
                    .withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SizedBox(width: width, height: height),
            );
          }
        : null,
    errorBuilder: (_, _, _) => onError,
  );
}
