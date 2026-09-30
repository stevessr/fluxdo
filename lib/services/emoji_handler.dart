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
/// - 自定义 emoji：与官方 enable-emoji initializer 一样，启动时直接使用
///   bootstrap 的 customEmoji；picker 按需加载 /emojis.json 后可补充目录。
/// - 标准 emoji：优先使用已加载目录里的真实 URL；目录尚未加载时按
///   siteSettings 的 emoji_set / external_emoji_url 构造官方兼容路径。
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

  /// /emojis.json 的按需完整目录。bootstrap customEmoji 是启动期权威来源；
  /// picker/SWR catalog 到达后用于补充标准表情与异常站点的兼容数据。
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

    // 对齐 Discourse enable-emoji initializer：启动期只注册
    // ApplicationLayoutPreloader 下发的 customEmoji，不额外请求 /emojis.json。
    // 完整 catalog 由 emoji picker 的 SWR provider 按需加载并通过
    // registerCatalog() 回灌；这样 reaction 首屏 URL 仍然准确，同时不让
    // 几百 KB 的表情目录与首页/用户请求争抢启动网络槽位。
  }

  /// 显式需要完整目录的调用方可复用同一个请求；启动初始化不会调用这里。
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

    return _buildStandardEmojiUrl(normalized);
  }

  String _buildStandardEmojiUrl(String normalized) {
    final settings = PreloadedDataService().siteSettingsSync;
    final configuredSet = settings?['emoji_set']?.toString().trim();
    final emojiSet = configuredSet == null || configuredSet.isEmpty
        ? 'twitter'
        : configuredSet;

    final external = settings?['external_emoji_url']?.toString().trim();
    final basePath = external == null || external.isEmpty
        ? '/images/emoji'
        : external.replaceFirst(RegExp(r'/+$'), '');

    final toneMatch = RegExp(r'^([^\s:]+):t([1-6])$').firstMatch(normalized);
    final path = toneMatch == null
        ? normalized
        : '${toneMatch.group(1)!}/t${toneMatch.group(2)!}';

    // Mirror Discourse buildEmojiUrl: respect the site's emoji_set and
    // external_emoji_url while the authoritative /emojis.json catalog is
    // still loading. The catalog URL replaces this fallback once available.
    return UrlHelper.resolveUrlWithCdn('$basePath/$emojiSet/$path.png');
  }
}
