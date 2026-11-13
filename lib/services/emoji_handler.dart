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
/// - 标准 emoji（如 heart、smile）：URL 确定性拼接
///   `/images/emoji/{表情集}/{name}.png`,肤色变体 `{name}/{tone}.png`；
///   站点配置了 external_emoji_url 时按其前缀拼接。
/// - 不依赖 `/emojis.json` API（该接口仅供 emoji picker 使用）
///
/// **展示表情集与站点表情集分离**:站点 `emoji_set` 只决定服务端 cooked
/// 里写哪套地址;展示用 [displaySet](用户在外观设置里选,默认 Noto)。
/// 回应面板的动态表情([animatedUrl])只有 Noto 一套,展示表情集是 Noto
/// 时才播放,避免动图与静态图两套画风来回切换。
///
/// 继承 [ChangeNotifier]：fork 的预加载/账号切换会在表情数据变化时通知监听者。
class EmojiHandler extends ChangeNotifier {
  static final EmojiHandler _instance = EmojiHandler._internal();
  factory EmojiHandler() => _instance;
  EmojiHandler._internal() {
    // preload 可以在首屏放行后才完成；监听真实完成与重置，而不是把
    // 门禁超时时读到的空表情列表当成永久初始化结果。
    PreloadedDataService().emojiDataRevision.addListener(_onPreloadChanged);
    _onPreloadChanged();
  }

  /// 偏好值:跟随站点 `emoji_set`。
  static const followSite = 'site';

  /// 可选表情集,取官方 EmojiSetSiteSetting 中未弃用的几项(apple/twitter/
  /// google/win10 等在官方文案里已标注 deprecated,分别并入下列表情集)。
  static const selectableSets = [
    'noto',
    'twemoji',
    'fluentui',
    'openmoji',
    'unicode',
  ];

  /// 默认偏好:Noto(与动态表情同一画风)。
  static const defaultPreference = 'noto';

  static String _preference = defaultPreference;

  /// 当前表情风格偏好:[followSite] 或 [selectableSets] 之一。
  static String get preference => _preference;

  /// 设置表情风格偏好(偏好层启动时与切换时调用),非法值回落默认。
  static void setPreference(String? value) {
    _preference = value == followSite || selectableSets.contains(value)
        ? value!
        : defaultPreference;
  }

  /// 站点表情集(服务端 cooked 里写的那套)。
  static String get siteSet =>
      PreloadedDataService().siteSettingsSync?['emoji_set'] as String? ??
      _defaultSiteSet;

  /// 展示用的标准 emoji 表情集。
  static String get displaySet =>
      _preference == followSite ? siteSet : _preference;

  /// 展示表情集与动态表情同属 Noto 画风时才播放动态表情。
  static bool get animationEnabled => displaySet == 'noto';

  /// 动态表情集:AVIF 动图序列,Noto 画风。
  static const _animatedSet = 'noto_animated';

  /// 图片版本参数(同官方 IMAGE_VERSION)。展示地址统一带同一版本,
  /// cooked 改写与按名拼接两路落到同一个缓存 key。
  static const _imageVersion = '16';

  /// 站点未下发 `emoji_set` 时的回退表情集(官方默认值)。
  static const _defaultSiteSet = 'twitter';

  /// 标准 emoji 图片路径:`/images/emoji/{set}/{name 或 name/tone}.png`。
  static final _standardPathRegex = RegExp(
    r'/images/emoji/([^/?#]+)/([^?#]+)\.png(?:[?#].*)?$',
  );

  static final _toneRegex = RegExp(r'^([^\s:]+):t([1-6])$');

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

  /// Explicit server-uploaded custom emojis must not be restyled or replaced.
  bool isCustomEmoji(String name) => _customEmojiMap.containsKey(
    normalizeEmojiShortcodeName(name).toLowerCase(),
  );

  /// 获取 emoji 的完整 URL
  ///
  /// 优先查找自定义 emoji（有服务端提供的真实 URL），
  /// 未找到则使用标准 emoji 的确定性路径（[displaySet] 表情集）。
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

  /// 标准 emoji 的确定性地址：展示表情集 + 站点 external_emoji_url 前缀。
  ///
  /// Mirror Discourse buildEmojiUrl：站点把表情图托管在别的域名时按其前缀
  /// 拼接，否则落到本站 `/images/emoji/{set}/…`。
  String _buildStandardEmojiUrl(String normalized) {
    final external = PreloadedDataService()
        .siteSettingsSync?['external_emoji_url']
        ?.toString()
        .trim();
    final path = _standardName(normalized);
    if (external == null || external.isEmpty) {
      return UrlHelper.resolveUrlWithCdn(_standardPath(displaySet, path));
    }
    final basePath = external.replaceFirst(RegExp(r'/+$'), '');
    return UrlHelper.resolveUrlWithCdn('$basePath/$displaySet/$path.png');
  }

  /// 指定表情集下标准 emoji 的地址(设置页预览各风格用,不做展示改写)。
  static String urlForSet(String name, String set) {
    final normalized = normalizeEmojiShortcodeName(name);
    return UrlHelper.resolveUrlWithCdn(
      _standardPath(set, _standardName(normalized)),
    );
  }

  /// 标准 emoji 的动态表情地址;自定义 emoji 没有动态版、展示表情集不是
  /// Noto 时不播放,均返回 null。肤色变体同官方 `+1/3.avif`。
  ///
  /// 动态表情集并非全量(国旗、区域字母等缺图 404),调用方须以 [getEmojiUrl]
  /// 的静态图兜底。
  String? animatedUrl(String name) {
    if (!animationEnabled) return null;
    final normalized = normalizeEmojiShortcodeName(name);
    if (_customEmojiMap.containsKey(normalized)) return null;
    return UrlHelper.resolveUrlWithCdn(
      '/images/emoji/$_animatedSet/${_standardName(normalized)}.avif'
      '?v=$_imageVersion',
    );
  }

  /// 肤色变体 `name:t3` → `name/3`(官方 code.replace(/:t/, "/"))。
  static String _standardName(String normalized) {
    final toneMatch = _toneRegex.firstMatch(normalized);
    return toneMatch != null
        ? '${toneMatch.group(1)}/${toneMatch.group(2)}'
        : normalized;
  }

  /// 把任意标准表情集的 emoji 地址改写到 [displaySet](cooked 里的
  /// `/images/emoji/twitter/…` 等)。非标准 emoji 地址原样返回。
  ///
  /// 只改取图地址、不改 cooked —— 编辑往返/序列化看到的仍是服务端原文。
  static String displayUrl(String url) {
    final match = _standardPathRegex.firstMatch(url);
    if (match == null || match.group(1) == displaySet) return url;
    return url.substring(0, match.start) +
        _standardPath(displaySet, match.group(2)!);
  }

  /// [displaySet] 地址缺图(404)时回退的站点表情集地址。
  ///
  /// 展示表情集按规范名存图,部分别名(`cn`/`jp` 等国旗别名)缺图;站点
  /// 表情集别名与规范名都有,回退后至多画风不同,不会裂图。
  static String? fallbackUrl(String url) {
    final match = _standardPathRegex.firstMatch(url);
    if (match == null || match.group(1) != displaySet) return null;
    final siteSet = EmojiHandler.siteSet;
    if (siteSet == displaySet) return null;
    return url.substring(0, match.start) +
        _standardPath(siteSet, match.group(2)!);
  }

  static String _standardPath(String set, String path) =>
      '/images/emoji/$set/$path.png?v=$_imageVersion';
}
