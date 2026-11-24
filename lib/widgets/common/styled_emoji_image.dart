import 'package:emoji_extension/emoji_extension.dart' hide Emoji;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/preferences_provider.dart';
import '../../services/discourse_cache_manager.dart';
import '../../services/emoji_handler.dart';
import '../../utils/emoji_shortcodes.dart';

/// Maps standard emoji shortcodes to Google Noto Emoji artwork without changing the
/// original Discourse shortcode or replacing site-uploaded custom emoji.
///
/// Assets are fetched lazily via the existing shared emoji cache; the selected
/// style is never downloaded until the user explicitly opts in.
class EmojiStyleAssets {
  EmojiStyleAssets._();

  static final Map<String, String?> _unicodeCache = <String, String?>{};

  /// Only cooked floor/post content may use the optional dynamic/3D artwork.
  static EmojiRenderStyle effectiveStyle(
    EmojiRenderStyle requested, {
    required bool usePostStyle,
  }) => usePostStyle ? requested : EmojiRenderStyle.normal;

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
    final unicode = glyph.runes.map((r) => r.toRadixString(16)).join('_');
    // Keep the bounded cache small even if a server sends unique emoji names.
    if (_unicodeCache.length >= 4096) _unicodeCache.clear();
    _unicodeCache[normalized] = unicode;
    return unicode;
  }

  /// Discourse's own generated artwork sets include shortcode aliases and
  /// tone variants. Pin the source commit for reproducible fallback downloads.
  static const _artworkRevision = 'b805eda63e1768ea861ff2fe00cf30c2ce2c504b';

  static String? staticUrlFor(String name, String set, {bool pinned = false}) {
    if (!EmojiHandler.selectableSets.contains(set)) return null;
    final normalized = normalizeEmojiShortcodeName(name).toLowerCase();
    if (!RegExp(r'^[a-z0-9_+-]+(?::t[1-6])?String name, EmojiRenderStyle style) {
    if (style == EmojiRenderStyle.normal) return null;
    if (EmojiHandler().isCustomEmoji(name)) return null;
    final unicode = unicodeFor(name);
    if (unicode == null) return null;
    return urlForUnicode(unicode, style);
  }

  /// A separate, pure URL builder makes source style routing testable.
  static String? urlForUnicode(String unicode, EmojiRenderStyle style) {
    if (style == EmojiRenderStyle.normal || unicode.isEmpty) return null;
    // Official Google Fonts Emoji CDN:
    // Animated Noto Emoji: https://googlefonts.github.io/noto-emoji-animation/
    // Noto 3D: https://googlefonts.github.io/noto-emoji-files/
    // Both use underscore-separated Unicode scalar values, including ZWJ
    // and variation selectors where present.
    if (!RegExp(r'^[0-9a-f]+(?:_[0-9a-f]+)*$').hasMatch(unicode)) {
      return null;
    }
    return switch (style) {
      EmojiRenderStyle.normal => null,
      EmojiRenderStyle.animated =>
        'https://fonts.gstatic.com/s/e/notoemoji/latest/$unicode/512.webp',
      EmojiRenderStyle.threeD =>
        'https://fonts.gstatic.com/s/e/noto3demoji/latest/$unicode/512.png',
    };
  }
}

/// One widget for post HTML, chat reactions, editor/picker and inline text.
/// Any unsupported/missing Google Noto asset falls back to the server's real emoji.
class StyledEmojiImage extends ConsumerWidget {
  const StyledEmojiImage({
    super.key,
    required this.name,
    this.serverUrl,
    this.usePostStyle = false,
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

  /// Opt-in only for actual floor/post body HTML. Picker, composer, reactions,
  /// notifications, profile pages and chat always use the site's normal emoji.
  final bool usePostStyle;
  final double? width;
  final double? height;
  final int? cacheWidth;
  final BoxFit fit;
  final bool gaplessPlayback;
  final bool showPlaceholder;
  final Widget? errorFallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestedStyle = usePostStyle
        ? ref.watch(preferencesProvider.select((p) => p.emojiRenderStyle))
        : EmojiRenderStyle.normal;
    final style = EmojiStyleAssets.effectiveStyle(
      requestedStyle,
      usePostStyle: usePostStyle,
    );
    final set = usePostStyle
        ? ref.watch(preferencesProvider.select((p) => p.emojiStyle))
        : EmojiHandler.followSite;
    return AnimatedBuilder(
      animation: EmojiHandler(),
      builder: (context, _) {
        final regularUrl = EmojiHandler().getEmojiUrl(name, serverUrl: serverUrl);
        final custom = EmojiHandler().isCustomEmoji(name);
        final dynamicUrl = custom || !usePostStyle
            ? null : EmojiStyleAssets.urlFor(name, style);
        final staticUrl = custom || !usePostStyle
            ? null : EmojiStyleAssets.staticUrlFor(name, set);
        final pinnedUrl = staticUrl == null ? null :
            EmojiStyleAssets.staticUrlFor(name, set, pinned: true);
        Widget normalImage() => _image(
          context,
          regularUrl,
          onError: errorFallback ?? Text(
            name.isEmpty ? ':?:' : ':$name:',
            maxLines: 1,
            overflow: TextOverflow.clip,
          ),
        );
        Widget selectedStatic() {
          if (staticUrl == null || staticUrl == regularUrl) return normalImage();
          final fallback = pinnedUrl == null
              ? normalImage()
              : _image(context, pinnedUrl, onError: normalImage());
          return _image(context, staticUrl, onError: fallback);
        }
        if (dynamicUrl == null) return selectedStatic();
        return _image(context, dynamicUrl, onError: selectedStatic());
      },
    );
  }

  Widget _image(BuildContext context, String url, {required Widget onError}) => Image(
    image: ResizeImage.resizeIfNeeded(
      // The native multi-frame WebP/GIF/APNG provider has its own decode path.
      // ResizeImage would wrap it in the static image resize pipeline, which
      // the shared image router deliberately skips for animated sources.
      isNativeAnimatedUrl(url) ? null : cacheWidth,
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
).hasMatch(normalized)) return null;
    final path = normalized.replaceFirst(':t', '/');
    final encoded = path.split('/').map(Uri.encodeComponent).join('/');
    return pinned
        ? 'https://raw.githubusercontent.com/discourse/discourse-emojis/$_artworkRevision/dist/emoji/$set/$encoded.png'
        : 'https://emoji.discourse-cdn.com/$set/$encoded.png?v=16';
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
    // Official Google Fonts Emoji CDN:
    // Animated Noto Emoji: https://googlefonts.github.io/noto-emoji-animation/
    // Noto 3D: https://googlefonts.github.io/noto-emoji-files/
    // Both use underscore-separated Unicode scalar values, including ZWJ
    // and variation selectors where present.
    if (!RegExp(r'^[0-9a-f]+(?:_[0-9a-f]+)*$').hasMatch(unicode)) {
      return null;
    }
    return switch (style) {
      EmojiRenderStyle.normal => null,
      EmojiRenderStyle.animated =>
        'https://fonts.gstatic.com/s/e/notoemoji/latest/$unicode/512.webp',
      EmojiRenderStyle.threeD =>
        'https://fonts.gstatic.com/s/e/noto3demoji/latest/$unicode/512.png',
    };
  }
}

/// One widget for post HTML, chat reactions, editor/picker and inline text.
/// Any unsupported/missing Google Noto asset falls back to the server's real emoji.
class StyledEmojiImage extends ConsumerWidget {
  const StyledEmojiImage({
    super.key,
    required this.name,
    this.serverUrl,
    this.usePostStyle = false,
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

  /// Opt-in only for actual floor/post body HTML. Picker, composer, reactions,
  /// notifications, profile pages and chat always use the site's normal emoji.
  final bool usePostStyle;
  final double? width;
  final double? height;
  final int? cacheWidth;
  final BoxFit fit;
  final bool gaplessPlayback;
  final bool showPlaceholder;
  final Widget? errorFallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestedStyle = usePostStyle
        ? ref.watch(preferencesProvider.select((p) => p.emojiRenderStyle))
        : EmojiRenderStyle.normal;
    final style = EmojiStyleAssets.effectiveStyle(
      requestedStyle,
      usePostStyle: usePostStyle,
    );
    final set = usePostStyle
        ? ref.watch(preferencesProvider.select((p) => p.emojiStyle))
        : EmojiHandler.followSite;
    return AnimatedBuilder(
      animation: EmojiHandler(),
      builder: (context, _) {
        final regularUrl = EmojiHandler().getEmojiUrl(name, serverUrl: serverUrl);
        final custom = EmojiHandler().isCustomEmoji(name);
        final styledUrl = custom || !usePostStyle ? null :
            EmojiStyleAssets.urlFor(name, style) ??
            EmojiStyleAssets.staticUrlFor(name, set) ??
            (set == EmojiHandler.followSite || set == 'unicode'
                ? null : EmojiHandler.displayUrl(regularUrl));
        if (!custom && usePostStyle && set == 'unicode' &&
            style == EmojiRenderStyle.normal) {
          final unicode = EmojiStyleAssets.unicodeFor(name);
          if (unicode != null) {
            final glyph = String.fromCharCodes(
              unicode.split('_').map((part) => int.parse(part, radix: 16)),
            );
            return Text(glyph, style: TextStyle(fontSize: height ?? width));
          }
        }
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
      // The native multi-frame WebP/GIF/APNG provider has its own decode path.
      // ResizeImage would wrap it in the static image resize pipeline, which
      // the shared image router deliberately skips for animated sources.
      isNativeAnimatedUrl(url) ? null : cacheWidth,
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
