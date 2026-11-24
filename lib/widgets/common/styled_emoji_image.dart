import 'package:emoji_extension/emoji_extension.dart' hide Emoji;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/preferences_provider.dart';
import '../../services/discourse_cache_manager.dart';
import '../../services/emoji_handler.dart';
import '../../services/fonts/emoji_font_service.dart';
import '../../services/fonts/offline_resource_pack.dart';
import 'package:common_ui/common_ui.dart' show UiShapesContext;
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
    if (!RegExp(r'^[a-z0-9_+-]+(?::t[1-6])?$').hasMatch(normalized)) return null;
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
class StyledEmojiImage extends StatelessWidget {
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
  Widget build(BuildContext context) {
    if (!usePostStyle) {
      return _buildImage(context, EmojiRenderStyle.normal, EmojiHandler.followSite);
    }
    return Consumer(
      builder: (context, ref, _) => _buildImage(
        context,
        ref.watch(preferencesProvider.select((p) => p.emojiRenderStyle)),
        ref.watch(preferencesProvider.select((p) => p.emojiStyle)),
      ),
    );
  }

  Widget _buildImage(BuildContext context, EmojiRenderStyle style, String set) {
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
        Widget onlineStatic() {
          if (staticUrl == null || staticUrl == regularUrl) return normalImage();
          final fallback = pinnedUrl == null
              ? normalImage()
              : _image(context, pinnedUrl, onError: normalImage());
          return _image(context, staticUrl, onError: fallback);
        }
        final localName = normalizeEmojiShortcodeName(name).toLowerCase();
        Widget systemGlyph() {
          final key = EmojiStyleAssets.unicodeFor(name);
          if (key == null) return errorFallback ?? Text(':$name:');
          final scalars = key.split('_').map((v) => int.parse(v, radix: 16));
          return _glyph(context, String.fromCharCodes(scalars));
        }
        Widget selectedStatic() {
          if (custom || !usePostStyle || staticUrl == null) return onlineStatic();
          return _packImage(context, localName, set,
              online: onlineStatic, missing: systemGlyph);
        }
        if (dynamicUrl != null) {
          final dynamicSet = style == EmojiRenderStyle.animated
              ? 'noto_animated' : 'noto_3d';
          return _packImage(context, localName, dynamicSet,
              online: () => _image(context, dynamicUrl, onError: selectedStatic()),
              missing: () => _packImage(context, localName,
                  staticUrl == null ? 'noto' : set,
                  online: systemGlyph, missing: systemGlyph));
        }
        if (custom || !usePostStyle || style != EmojiRenderStyle.normal) {
          return selectedStatic();
        }
        final unicode = EmojiStyleAssets.unicodeFor(name);
        final cp = EmojiFontFace.simpleScalar(unicode);
        if (set == 'unicode' && cp != null) {
          return _glyph(context, String.fromCharCodes([cp, 0xfe0f]));
        }
        if (cp == null || !EmojiFontSpec.bySet.containsKey(set)) {
          return selectedStatic();
        }
        final ready = EmojiFontService.instance.ready(set);
        if (ready != null) {
          final glyph = ready.glyphFor(unicode);
          return glyph == null ? selectedStatic() : _glyph(context, glyph, family: ready.family);
        }
        return FutureBuilder<EmojiFontFace?>(
          future: EmojiFontService.instance.ensure(set),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              // Temporarily use the system glyph without requesting one PNG
              // per emoji while the selected font is being downloaded.
              return _glyph(context, String.fromCharCodes([cp, 0xfe0f]));
            }
            final face = snapshot.data;
            final glyph = face?.glyphFor(unicode);
            return glyph == null ? selectedStatic() : _glyph(context, glyph, family: face!.family);
          },
        );
      },
    );
  }

  Widget _packImage(BuildContext context, String name, String set, {
    required Widget Function() online,
    required Widget Function() missing,
  }) {
    final path = OfflineResourcePack.emojiPath(name, set);
    if (path == null || !OfflineResourcePack.supported) return online();
    return FutureBuilder<PackEmojiAsset>(
      future: OfflineResourcePack.instance.emoji(path),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return SizedBox(width: width, height: height);
        }
        final asset = snapshot.data;
        if (asset == null || !asset.installed) return online();
        final bytes = asset.bytes;
        if (bytes == null) return missing();
        return Image.memory(
          bytes, width: width, height: height, fit: fit,
          gaplessPlayback: gaplessPlayback,
          cacheWidth: set == 'noto_animated' ? null : cacheWidth,
          errorBuilder: (_, _, _) => missing(),
        );
      },
    );
  }

  Widget _glyph(BuildContext context, String glyph, {String? family}) {
    final size = height ?? width ?? 18;
    return SizedBox(
      width: width ?? size,
      height: height ?? size,
      child: FittedBox(
        fit: BoxFit.contain,
        child: Text(
          glyph,
          maxLines: 1,
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            inherit: false,
            fontFamily: family,
            fontSize: size,
            height: 1,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
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
                borderRadius: context.shapes.borderRadius(8),
              ),
              child: SizedBox(width: width, height: height),
            );
          }
        : null,
    errorBuilder: (_, _, _) => onError,
  );
}
