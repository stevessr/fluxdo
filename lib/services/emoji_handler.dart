import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/emoji.dart';
import '../utils/emoji_shortcodes.dart';
import '../utils/url_helper.dart';
import 'auth_session.dart';
import 'discourse/discourse_service.dart';
import 'preloaded_data_service.dart';

/// Emoji URL 解析器
///
/// 与 Discourse 官方逻辑一致：
/// - 自定义 emoji：优先使用当前 bootstrap 的 URL，补充从
///   `/emojis.json` 获取的站点完整目录（reaction 和 picker 共用）。
/// - 标准 emoji：优先使用服务端目录提供的真实 URL，仅无目录时
///   临时拼接 Twemoji 路径，等待异步目录就绪后刷新已挂载的图片。
class EmojiHandler extends ChangeNotifier {
  static final EmojiHandler _instance = EmojiHandler._internal();
  factory EmojiHandler() => _instance;
  EmojiHandler._internal() {
    // preload 可以在首屏放行后才完成；监听真实完成与重置，而不是把
    // 门禁超时时读到的空表情列表当成永久初始化结果。
    PreloadedDataService().emojiDataRevision.addListener(_onPreloadChanged);
    _onPreloadChanged();
  }

  /// 自定义 emoji 名称 -> URL 映射（对应 Discourse 的 extendedEmojiMap）
  Map<String, String> _customEmojiMap = {};

  /// /emojis.json exposes the actual URL of *all* server emoji, including
  /// custom reactions that may not be present in the home preload payload.
  Map<String, String> _catalogEmojiMap = {};
  Future<void>? _catalogInflight;
  bool _catalogLoaded = false;
  int _catalogRevision = 0;

  void _onPreloadChanged() {
    final preload = PreloadedDataService();
    init();

    // reset()/account switch publishes an emoji revision while preload is not
    // loaded. Drop every server URL from the previous session immediately so
    // the UI can never render a stale custom reaction while the new bootstrap
    // is still in flight.
    if (!preload.isLoaded) {
      final hadCatalog = _catalogEmojiMap.isNotEmpty || _catalogLoaded;
      _catalogEmojiMap = {};
      _catalogLoaded = false;
      _catalogRevision++;
      _catalogInflight = null;
      if (hadCatalog) notifyListeners();
      return;
    }

    // Bootstrap is allowed to finish after the startup gate opens. Populate
    // reaction URLs independently of whether the user opens the emoji picker.
    if (!_catalogLoaded) {
      unawaited(
        ensureCatalogLoaded().catchError((Object error) {
          debugPrint('[EmojiHandler] Failed to fetch emoji catalog: $error');
        }),
      );
    }
  }

  /// Share a single background request; a failed attempt can be retried by
  /// opening the picker or on the next successful bootstrap refresh.
  Future<void> ensureCatalogLoaded() {
    if (_catalogLoaded) return Future<void>.value();
    final inflight = _catalogInflight;
    if (inflight != null) return inflight;

    final revision = _catalogRevision;
    late final Future<void> request;
    request = _fetchCatalog(revision).whenComplete(() {
      if (identical(_catalogInflight, request)) {
        _catalogInflight = null;
      }
    });
    _catalogInflight = request;
    return request;
  }

  Future<void> _fetchCatalog(int revision) async {
    final generation = AuthSession().generation;
    final groups = await DiscourseService().getEmojis();
    if (!AuthSession().isValid(generation) || revision != _catalogRevision) {
      return;
    }
    registerCatalog(groups);
    if (groups.isNotEmpty) _catalogLoaded = true;
  }

  /// Also accept cached /emojis.json snapshots and subsequent SWR updates.
  /// Server URLs take precedence over generated Twemoji paths, while the
  /// current bootstrap's custom URLs take precedence over an older snapshot.
  void registerCatalog(Map<String, List<Emoji>> groups) {
    final updated = <String, String>{};
    for (final emojis in groups.values) {
      for (final emoji in emojis) {
        if (emoji.name.isNotEmpty && emoji.url.isNotEmpty) {
          updated[normalizeEmojiShortcodeName(emoji.name).toLowerCase()] =
              emoji.url;
        }
      }
    }
    if (updated.isEmpty || mapEquals(_catalogEmojiMap, updated)) return;
    _catalogEmojiMap = updated;
    notifyListeners();
  }

  /// 每次 preload 完成/失效时重新同步。空数据仅为当前临时状态，
  /// 不会阻止后续加载；切换站点时也不会沿用上一站点的自定义 URL。
  void init() {
    final updated = <String, String>{};
    try {
      final customEmojis =
          PreloadedDataService().customEmoji ?? const <Map<String, dynamic>>[];
      for (final emoji in customEmojis) {
        final name = emoji['name'];
        final url = emoji['url'];
        if (name is String &&
            url is String &&
            name.isNotEmpty &&
            url.isNotEmpty) {
          updated[normalizeEmojiShortcodeName(name).toLowerCase()] = url;
        }
      }
    } catch (e) {
      debugPrint('Failed to load custom emojis: $e');
      return;
    }
    if (mapEquals(_customEmojiMap, updated)) return;
    _customEmojiMap = updated;
    notifyListeners();
  }

  /// 将文本中的 :emoji: 替换为 HTML img 标签
  String replaceEmojis(String text) {
    return text.replaceAllMapped(emojiShortcodeRegex, (match) {
      final name = normalizeEmojiShortcodeName(match.group(1)!);
      final fullUrl = getEmojiUrl(name);
      return '<img src="$fullUrl" alt=":$name:" class="emoji" title=":$name:">';
    });
  }

  /// 获取 emoji 的完整 URL
  ///
  /// 优先查找自定义 emoji（有服务端提供的真实 URL），
  /// 未找到则使用标准 emoji 的确定性路径。
  String getEmojiUrl(String name, {String? serverUrl}) {
    final normalized = normalizeEmojiShortcodeName(name).toLowerCase();

    // 优先查自定义 emoji（如 bili_114、tsai 等）
    final customUrl =
        _customEmojiMap[normalized] ??
        _catalogEmojiMap[normalized] ??
        serverUrl;
    if (customUrl != null && customUrl.isNotEmpty) {
      return UrlHelper.resolveUrlWithCdn(customUrl);
    }

    final toneMatch = RegExp(r'^([^\s:]+):t([1-6])$').firstMatch(normalized);
    if (toneMatch != null) {
      final base = toneMatch.group(1)!;
      final tone = toneMatch.group(2)!;
      return UrlHelper.resolveUrlWithCdn(
        '/images/emoji/twitter/$base/t$tone.png?v=12',
      );
    }

    // 标准 emoji，URL 确定性拼接（与 Discourse buildEmojiUrl 一致）
    return UrlHelper.resolveUrlWithCdn(
      '/images/emoji/twitter/$normalized.png?v=12',
    );
  }
}
