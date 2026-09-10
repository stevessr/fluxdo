import 'dart:convert';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart'
    show ValueListenable, ValueNotifier, compute, immutable, visibleForTesting;
import 'package:flutter/material.dart';
import '../constants.dart';
import '../models/topic.dart';
import '../models/category.dart';
import 'auth_session.dart';
import 'preloaded_data_decoder.dart';
import 'network/discourse_dio.dart';
import 'network/cookie/csrf_token_service.dart';
import 'cf_challenge_service.dart';
import 'cf_clearance_refresh_service.dart';

enum PreloadPhase {
  idle,
  requesting,
  decoding,
  parsingTopics,
  complete,
  failed,
}

@immutable
class PreloadProgress {
  const PreloadProgress({
    required this.phase,
    this.parsedTopics = 0,
    this.totalTopics = 0,
  });

  const PreloadProgress.idle()
    : phase = PreloadPhase.idle,
      parsedTopics = 0,
      totalTopics = 0;

  final PreloadPhase phase;
  final int parsedTopics;
  final int totalTopics;

  bool get isActive =>
      phase == PreloadPhase.requesting ||
      phase == PreloadPhase.decoding ||
      phase == PreloadPhase.parsingTopics;

  double? get fraction {
    if (phase == PreloadPhase.complete) return 1.0;
    if (phase != PreloadPhase.parsingTopics || totalTopics <= 0) return null;
    return (parsedTopics / totalTopics).clamp(0.0, 1.0).toDouble();
  }

  String get semanticsLabel {
    switch (phase) {
      case PreloadPhase.idle:
        return '预加载未开始';
      case PreloadPhase.requesting:
        return '正在获取预加载数据';
      case PreloadPhase.decoding:
        return '正在解析预加载数据';
      case PreloadPhase.parsingTopics:
        return totalTopics > 0
            ? '正在解析话题 $parsedTopics / $totalTopics'
            : '正在解析话题';
      case PreloadPhase.complete:
        return '预加载完成';
      case PreloadPhase.failed:
        return '预加载失败';
    }
  }
}

/// 预加载数据服务
/// 从首页 HTML 中提取 Discourse 预加载数据，避免额外 API 请求。
/// 新版站点为 `<script type="application/json" id="data-preloaded">` 标签
/// （内容是原始 JSON），旧版为元素属性 `data-preloaded="..."`（HTML 实体转义），
/// 两种形态都支持。
class PreloadedDataService {
  static final PreloadedDataService _instance =
      PreloadedDataService._internal();
  factory PreloadedDataService() => _instance;

  static const int _topicParseBatchSize = 24;

  final Dio _dio;
  final CsrfTokenService _cookieSync = CsrfTokenService();
  final CfChallengeService _cfChallenge = CfChallengeService();
  final ValueNotifier<PreloadProgress> _preloadProgress =
      ValueNotifier<PreloadProgress>(const PreloadProgress.idle());
  final ValueNotifier<TopicListResponse?> _progressiveTopicList =
      ValueNotifier<TopicListResponse?>(null);

  // 缓存的预加载数据
  Map<String, dynamic>? _currentUser;
  Map<String, dynamic>? _siteSettings;
  Map<String, dynamic>? _site; // 站点信息（包含 categories）
  Map<String, dynamic>? _topicTrackingStateMeta;
  Map<String, dynamic>? _topicListData; // 首页话题列表原始数据
  TopicListResponse? _cachedTopicListResponse; // 缓存的已解析话题列表
  Completer<TopicListResponse?>? _topicListResponseCompleter;
  Completer<TopicListResponse?>? _firstTopicListBatchCompleter;
  List<Map<String, dynamic>>? _customEmoji; // 自定义 emoji
  List<Map<String, dynamic>>? _topicTrackingStates; // 话题追踪状态
  String? _topicTrackingStatesRawJson;
  Completer<List<Map<String, dynamic>>?>? _topicTrackingStatesCompleter;
  List<String>? _enabledReactions;
  String? _sharedSessionKey; // MessageBus 跨域认证 key
  String? _longPollingBaseUrl; // MessageBus 独立域名
  String _baseUri = ''; // Discourse 子路径前缀（如 /forum）
  String? _cdnUrl; // CDN 域名（从 data-discourse-setup 提取）
  String? _s3CdnUrl; // S3 CDN 域名（如 https://cdn3.linux.do）
  String? _s3BaseUrl; // S3 基础 URL（如 //linuxdo-uploads.s3.linux.do）
  List<String>? _pluginCandidates; // 首页 HTML 中扫到的 plugin js url 列表
  bool _hasDiscourseSetup = false; // 是否提取到 data-discourse-setup 标签
  bool _loaded = false;
  int _dataRevision = 0;
  Future<void>? _loadingFuture;

  PreloadedDataService._internal()
    : _dio = DiscourseDio.create(
        defaultHeaders: {
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        },
      );

  /// 是否已加载数据
  bool get isLoaded => _loaded;
  Map<String, dynamic>? get currentUserSync => _currentUser;
  Map<String, dynamic>? get siteSettingsSync => _siteSettings;
  Map<String, dynamic>? get siteSync => _site;

  /// 允许使用话题精选链接的分类 ID 白名单。
  ///
  /// 由 SiteSerializer 下发在 site.json 顶层（仅当 `topic_featured_link_enabled`
  /// 为真时才包含该字段）；分类对象自身的 `topic_featured_link_allowed` 只在
  /// CategorySerializer 里，不会出现在 site.json 的分类列表中。
  ///
  /// 返回 null 表示站点未下发该字段（等价于「无分类限制」，对齐官方
  /// `categoryIds === undefined` 分支）。
  List<int>? get topicFeaturedLinkAllowedCategoryIdsSync {
    final raw = _site?['topic_featured_link_allowed_category_ids'];
    if (raw is! List) return null;
    return raw
        .map((e) => e is int ? e : int.tryParse(e.toString()))
        .whereType<int>()
        .toList(growable: false);
  }

  /// 未分类分类的 ID（官方 `uncategorized_category_id`）
  int? get uncategorizedCategoryIdSync {
    final raw = _site?['uncategorized_category_id'];
    return raw is int ? raw : int.tryParse(raw?.toString() ?? '');
  }

  /// 启动预加载的真实阶段/话题解析进度。
  ValueListenable<PreloadProgress> get preloadProgressListenable =>
      _preloadProgress;
  PreloadProgress get preloadProgress => _preloadProgress.value;

  /// 首页 topic_list 的累计解析快照。每完成一批就替换一次快照，
  /// 消费方可以在最终 TopicListResponse 产生前先展示已完成的话题。
  ValueListenable<TopicListResponse?> get progressiveTopicListListenable =>
      _progressiveTopicList;
  TopicListResponse? get progressiveTopicListSync =>
      _progressiveTopicList.value;

  void _setPreloadProgress(PreloadProgress progress) {
    _preloadProgress.value = progress;
  }

  /// 从首页 HTML 扫出的 plugin js url 列表（供 WebView session bootstrap 复用,
  /// 避免重复 fetch 首页）。未加载或没扫到时返回 null。
  List<String>? get pluginCandidatesSync => _pluginCandidates;

  /// 废弃插件候选列表(bootstrap 的 fingerprint 端点 404 时调用)。
  ///
  /// 站点会随构建轮换 fingerprint 插件的混淆端点;端点 404 说明本快照
  /// 已过期,继续提供只会让所有调用方拿同一份旧弹药反复 404。清空后
  /// bootstrap 脚本降级到自己的新鲜 discover,下次首页解析自然重建。
  void invalidatePluginCandidates() {
    if (_pluginCandidates == null) return;
    _pluginCandidates = null;
    debugPrint('[PreloadedData] pluginCandidates 已废弃(端点过期)');
  }

  List<Map<String, dynamic>>? get topicTrackingStatesSync =>
      _topicTrackingStates;

  /// 设置导航 context（用于弹出 CF 验证页面）
  void setNavigatorContext(BuildContext context) {
    _cfChallenge.setContext(context);
  }

  /// 确保预加载数据已准备好
  Future<void> ensureLoaded() async {
    await _ensureLoaded();
  }

  /// 获取 currentUser 数据（包含通知计数等）
  Future<Map<String, dynamic>?> getCurrentUser() async {
    final revision = _dataRevision;
    final generation = AuthSession().generation;
    await _ensureLoaded();
    if (!_isCurrent(revision, generation)) return null;
    return _currentUser;
  }

  /// 获取站点设置
  Future<Map<String, dynamic>?> getSiteSettings() async {
    await _ensureLoaded();
    return _siteSettings;
  }

  /// 获取站点信息（包含 categories、top_tags 等）
  Future<Map<String, dynamic>?> getSite() async {
    await _ensureLoaded();
    return _site;
  }

  /// 获取系统用户头像模板
  /// 用于通知列表中没有 acting_user 时的默认头像
  Future<String?> getSystemUserAvatarTemplate() async {
    await _ensureLoaded();
    return _site?['system_user_avatar_template'] as String?;
  }

  /// 同步获取分类 ID 集合（预加载数据已加载后可用，用于 Tab 过滤）
  Set<int>? get categoryIdsSync {
    if (_site == null) return null;
    try {
      final categoriesJson = _site!['categories'] as List?;
      if (categoriesJson != null) {
        return categoriesJson
            .map(
              (c) =>
                  int.tryParse(
                    (c as Map<String, dynamic>)['id']?.toString() ?? '0',
                  ) ??
                  0,
            )
            .where((id) => id != 0)
            .toSet();
      }
    } catch (_) {}
    return null;
  }

  /// 获取分类列表（从预加载的 site 数据中提取）
  Future<List<Category>?> getCategories() async {
    await _ensureLoaded();
    if (_site == null) return null;

    try {
      final categoriesJson = _site!['categories'] as List?;
      if (categoriesJson != null) {
        return categoriesJson
            .map((c) => Category.fromJson(c as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint('[PreloadedData] 解析 categories 失败: $e');
    }
    return null;
  }

  /// 获取热门标签（从预加载的 site 数据中提取）
  Future<List<String>?> getTopTags() async {
    await _ensureLoaded();
    if (_site == null) return null;

    final topTags = _site!['top_tags'] as List?;
    if (topTags != null) {
      // 兼容新旧格式：如果是对象则取 name 字段，如果是字符串则直接用
      return topTags
          .map((t) {
            if (t is Map<String, dynamic>) {
              return t['name'] as String? ?? '';
            }
            return t.toString();
          })
          .where((name) => name.isNotEmpty)
          .toList();
    }
    return null;
  }

  /// 获取帖子操作类型（举报类型等）
  Future<List<Map<String, dynamic>>?> getPostActionTypes() async {
    await _ensureLoaded();
    if (_site == null) return null;

    final types = _site!['post_action_types'] as List?;
    if (types != null) {
      return types.cast<Map<String, dynamic>>();
    }
    return null;
  }

  /// 检查站点是否支持标签功能
  Future<bool?> canTagTopics() async {
    await _ensureLoaded();
    if (_site == null) return null;
    return _site!['can_tag_topics'] as bool?;
  }

  /// 获取默认发帖分类 ID
  /// 从 siteSettings 的 default_composer_category 获取
  Future<int?> getDefaultComposerCategoryId() async {
    await _ensureLoaded();
    if (_siteSettings == null) return null;
    final value = _siteSettings!['default_composer_category'];
    if (value == null) return null;
    if (value is int) {
      // 忽略无效值（-1 或 0 表示未设置）
      if (value <= 0) return null;
      return value;
    }
    if (value is String && value.isNotEmpty) {
      final parsed = int.tryParse(value);
      if (parsed != null && parsed > 0) return parsed;
    }
    return null;
  }

  /// 获取话题标题最小长度
  Future<int> getMinTopicTitleLength() async {
    await _ensureLoaded();
    final value = _siteSettings?['min_topic_title_length'];
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 15;
    return 15; // Discourse 默认值
  }

  /// 话题标题最大长度（官方 `max_topic_title_length`，默认 255）
  int get maxTopicTitleLengthSync {
    final value = _siteSettings?['max_topic_title_length'];
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 255;
    return 255; // Discourse 默认值
  }

  /// 获取私信标题最小长度
  Future<int> getMinPmTitleLength() async {
    await _ensureLoaded();
    final value = _siteSettings?['min_personal_message_title_length'];
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 2;
    return 2; // Discourse 默认值
  }

  /// 获取回复内容最小长度
  Future<int> getMinPostLength() async {
    await _ensureLoaded();
    final premiumValue = _currentUser?['premium_min_post_length'];
    if (premiumValue is int && premiumValue > 0) return premiumValue;
    if (premiumValue is String) {
      final parsed = int.tryParse(premiumValue);
      if (parsed != null && parsed > 0) return parsed;
    }

    final value = _siteSettings?['min_post_length'];
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 8;
    return 8; // Discourse 默认值
  }

  /// 获取首贴内容最小长度
  Future<int> getMinFirstPostLength() async {
    await _ensureLoaded();
    final value = _siteSettings?['min_first_post_length'];
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 20;
    return 20; // Discourse 默认值
  }

  /// 获取帖子最大长度
  ///
  /// warden 等插件抬高最小字数时需要用它封顶,避免管理员误配出
  /// 一个永远满足不了的下限。
  Future<int> getMaxPostLength() async {
    await _ensureLoaded();
    final value = _siteSettings?['max_post_length'];
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 32000;
    return 32000; // Discourse 默认值
  }

  /// 获取私信内容最小长度
  Future<int> getMinPmPostLength() async {
    await _ensureLoaded();
    final value = _siteSettings?['min_personal_message_post_length'];
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 10;
    return 10; // Discourse 默认值
  }

  /// 检查站点是否开启了 AI 语义搜索
  Future<bool> isAiSemanticSearchEnabled() async {
    await _ensureLoaded();
    return _siteSettings?['ai_embeddings_semantic_search_enabled'] == true;
  }

  // ---- discourse-chat 插件开关 ----

  /// 仅依赖启动/预加载时的 siteSettings 快照，不在运行期反复探测。
  /// preload 未就绪或无该字段时按未开启处理。
  bool get chatEnabled => _siteSettings?['chat_enabled'] == true;

  /// 异步确保预加载完成后读取 [chatEnabled]。
  Future<bool> isChatEnabled() async {
    await _ensureLoaded();
    return chatEnabled;
  }

  // ---- discourse-signatures 插件开关（均为 client:true，preload 可读）----
  // 同步读取：签名渲染在 build 中门禁，preload 未就绪时按插件未启用处理。

  /// 服务端签名总开关（signatures_enabled）。未加载/无插件时为 false。
  bool get signaturesEnabled => _siteSettings?['signatures_enabled'] == true;

  /// advanced 模式：user_signature 为 cooked HTML；否则为图片 URL。
  bool get signaturesAdvancedMode =>
      _siteSettings?['signatures_advanced_mode'] == true;

  /// 图片签名（URL 模式）的最大显示高度，默认 150。
  double get signaturesMaxImageHeight =>
      (_siteSettings?['signatures_max_image_height'] as num?)?.toDouble() ??
      150;

  /// 仅在每层主楼（post_number == 1）显示签名。
  bool get signaturesFirstPostOnly =>
      _siteSettings?['signatures_first_post_only'] == true;

  /// 限定显示签名的分类 id 列表；空列表 = 不限分类。
  List<int> get signaturesShowInCategories {
    final raw = _siteSettings?['signatures_show_in_categories'] as String?;
    if (raw == null || raw.isEmpty) return const [];
    return raw.split('|').map(int.tryParse).whereType<int>().toList();
  }

  // ---- discourse-assign 插件开关（均为 client:true，preload 可读）----

  /// 指定功能总开关(assign_enabled)。站点未装插件时该键不存在,
  /// 视为未启用——入口显隐以「assignEnabled && can_assign」为准。
  bool get assignEnabled => _siteSettings?['assign_enabled'] == true;

  /// 指定状态字段开关(enable_assign_status)。关闭时官方 Web 端弹窗
  /// 不显示状态下拉。
  bool get assignStatusEnabled =>
      _siteSettings?['enable_assign_status'] == true;

  /// 指定状态可选值(assign_statuses,竖线分隔;首项为默认状态)。
  List<String> get assignStatuses {
    final raw = _siteSettings?['assign_statuses'] as String?;
    if (raw == null || raw.isEmpty) return const [];
    return raw.split('|').where((s) => s.isNotEmpty).toList();
  }

  /// 获取可用的回应表情列表
  Future<List<String>> getEnabledReactions() async {
    await _ensureLoaded();
    return _enabledReactions ?? ['heart', '+1', 'laughing', 'open_mouth'];
  }

  /// 同步获取可用回应表情列表（仅返回已 preload 结果，未 preload 时返回兜底）
  /// 用于"按下立即弹出"等零延迟场景
  List<String> get enabledReactionsSync =>
      _enabledReactions ?? const ['heart', '+1', 'laughing', 'open_mouth'];

  /// 获取 MessageBus 跨域认证 key（仅独立域名时有值）
  String? get sharedSessionKey => _sharedSessionKey;

  /// 获取 MessageBus 长轮询 base URL（独立域名，如 https://ping.linux.do）
  String? get longPollingBaseUrl => _longPollingBaseUrl;

  /// 获取 Discourse 子路径前缀（如 /forum，根部署时为空字符串）
  String get baseUri => _baseUri;

  /// 获取 CDN URL（如 https://cdn.linux.do）
  String? get cdnUrl => _cdnUrl;

  /// 获取 S3 CDN URL（如 https://cdn3.linux.do）
  String? get s3CdnUrl => _s3CdnUrl;

  /// 获取 S3 基础 URL（如 //linuxdo-uploads.s3.linux.do）
  String? get s3BaseUrl => _s3BaseUrl;

  /// 获取 MessageBus 频道的初始 message ID
  /// 返回格式: {'/latest': 6855147, '/new': 104155, ...}
  Future<Map<String, dynamic>?> getTopicTrackingStateMeta() async {
    await _ensureLoaded();
    return _topicTrackingStateMeta;
  }

  /// 获取话题追踪状态列表（未读、新话题等）
  /// 用于初始化侧边栏的未读计数
  Future<List<Map<String, dynamic>>?> getTopicTrackingStates() async {
    await _ensureLoaded();
    if (_topicTrackingStates != null) return _topicTrackingStates;
    if (_topicTrackingStatesRawJson == null &&
        _topicTrackingStatesCompleter == null) {
      return null;
    }
    await _decodeTopicTrackingStatesAsync();
    return _topicTrackingStates;
  }

  /// 获取自定义 emoji 列表（同步访问，需确保已调用 ensureLoaded）
  /// 返回格式: [{name: "emoji_name", url: "emoji_url"}, ...]
  List<Map<String, dynamic>>? get customEmoji => _customEmoji;

  /// 获取自定义 emoji 列表（异步版本，自动确保数据已加载）
  /// 返回格式: [{name: "emoji_name", url: "emoji_url"}, ...]
  Future<List<Map<String, dynamic>>?> getCustomEmoji() async {
    await _ensureLoaded();
    return _customEmoji;
  }

  /// 等到 topic_list 的第一批完成，而不是等待整份列表。
  /// 后续批次通过 [progressiveTopicListListenable] 继续推送累计快照。
  Future<TopicListResponse?> getInitialTopicListFirstBatch() async {
    await _ensureLoaded();
    final progressive = _progressiveTopicList.value;
    if (progressive != null) return progressive;
    if (_cachedTopicListResponse != null) return _cachedTopicListResponse;
    final firstBatch = _firstTopicListBatchCompleter;
    if (firstBatch == null) return null;
    return firstBatch.future;
  }

  /// 获取预加载的首页话题列表（仅首次加载时有效）
  /// 返回 TopicListResponse 或 null
  Future<TopicListResponse?> getInitialTopicList() async {
    await _ensureLoaded();
    if (_cachedTopicListResponse != null) {
      final response = _cachedTopicListResponse;
      _cachedTopicListResponse = null;
      _topicListData = null;
      _topicListResponseCompleter = null;
      _firstTopicListBatchCompleter = null;
      _progressiveTopicList.value = null;
      return response;
    }
    if (_topicListData == null && _topicListResponseCompleter == null) {
      return null;
    }

    try {
      if (_cachedTopicListResponse == null &&
          _topicListResponseCompleter != null) {
        await _topicListResponseCompleter!.future;
      }
      if (_cachedTopicListResponse == null) return null;
      final response = _cachedTopicListResponse;
      _cachedTopicListResponse = null;
      _topicListData = null;
      _topicListResponseCompleter = null;
      _firstTopicListBatchCompleter = null;
      _progressiveTopicList.value = null;
      return response;
    } catch (e) {
      debugPrint('[PreloadedData] 解析 topic_list 失败: $e');
      _topicListData = null;
      _topicListResponseCompleter = null;
      _firstTopicListBatchCompleter = null;
      return null;
    }
  }

  /// 检查是否有预加载的话题列表可用
  bool get hasInitialTopicList =>
      _cachedTopicListResponse != null ||
      _progressiveTopicList.value != null ||
      _topicListData != null ||
      _topicListResponseCompleter != null ||
      _firstTopicListBatchCompleter != null;

  /// 同步获取预加载的话题列表（如果已加载）
  /// 返回 TopicListResponse 或 null
  /// 注意：此方法会消费数据，只能调用一次
  TopicListResponse? getInitialTopicListSync() {
    if (_cachedTopicListResponse == null) return null;
    final response = _cachedTopicListResponse;
    _cachedTopicListResponse = null; // 消费后清除
    _topicListData = null;
    _topicListResponseCompleter = null;
    _firstTopicListBatchCompleter = null;
    _progressiveTopicList.value = null;
    return response;
  }

  /// 强制刷新预加载数据
  Future<void> refresh() async {
    final oldLoading = _loadingFuture;
    _invalidateCachedData();
    if (oldLoading != null) {
      try {
        await oldLoading;
      } catch (_) {
        // 旧会话的加载失败不应阻塞新会话重新加载。
      }
    }
    await _loadPreloadedData(
      revision: _dataRevision,
      generation: AuthSession().generation,
    );
  }

  /// 直接从已有 HTML 快照恢复预加载数据。
  ///
  /// 适用于登录 WebView 已经拿到完整页面的场景，避免重复请求首页。
  /// 返回是否成功解析到 data-preloaded。
  Future<bool> hydrateFromHtml(String html) async {
    final oldLoading = _loadingFuture;
    _invalidateCachedData();
    if (oldLoading != null) {
      try {
        await oldLoading;
      } catch (_) {
        // 当前 HTML 快照仍可独立尝试解析。
      }
    }
    final revision = _dataRevision;
    final generation = AuthSession().generation;
    final parsed = await _parsePreloadedDataFromHtml(
      html,
      revision: revision,
      generation: generation,
    );
    if (!_isCurrent(revision, generation)) return false;
    if (!parsed) {
      debugPrint('[PreloadedData] HTML 快照不包含可用的 data-preloaded');
      _setPreloadProgress(const PreloadProgress(phase: PreloadPhase.failed));
      return false;
    }

    if (!_hasReusableBootstrapData()) {
      debugPrint(
        '[PreloadedData] HTML 快照缺少完整引导数据: '
        'hasSetup=$_hasDiscourseSetup, '
        'hasCurrentUser=${_currentUser != null}, '
        'hasSiteSettings=${_siteSettings != null}, '
        'hasSite=${_site != null}',
      );
      _clearCachedData();
      return false;
    }

    _loaded = true;
    debugPrint('[PreloadedData] 已从 HTML 快照恢复数据');
    return true;
  }

  void _clearCachedData() {
    _loaded = false;
    _currentUser = null;
    _siteSettings = null;
    _site = null;
    _topicListData = null;
    _cachedTopicListResponse = null;
    final pendingTopicList = _topicListResponseCompleter;
    if (pendingTopicList != null && !pendingTopicList.isCompleted) {
      pendingTopicList.complete(null);
    }
    _topicListResponseCompleter = null;
    final pendingFirstBatch = _firstTopicListBatchCompleter;
    if (pendingFirstBatch != null && !pendingFirstBatch.isCompleted) {
      pendingFirstBatch.complete(null);
    }
    _firstTopicListBatchCompleter = null;
    _progressiveTopicList.value = null;
    _setPreloadProgress(const PreloadProgress.idle());
    _customEmoji = null;
    _topicTrackingStates = null;
    _topicTrackingStatesRawJson = null;
    _topicTrackingStatesCompleter = null;
    _enabledReactions = null;
    _topicTrackingStateMeta = null;
    _hasDiscourseSetup = false;
    // 以下为站点级基础设施数据，不随用户登录状态变化。
    // 下次 HTML 解析时会自然更新，refresh 窗口期内保留可避免
    // UrlHelper CDN 降级和 MessageBus 连接中断。
    // _cdnUrl, _s3CdnUrl, _s3BaseUrl, _baseUri
    // _longPollingBaseUrl, _sharedSessionKey
  }

  void _invalidateCachedData() {
    _dataRevision++;
    _clearCachedData();
  }

  /// 仅供测试：直接注入当前用户与站点设置
  ///
  /// 静音过滤等逻辑依赖这两份预加载数据，而本类是单例、真实加载路径要发
  /// 网络请求。给测试开一个最小口子，好过把那些判定写成不可测。
  @visibleForTesting
  void debugSeed({
    Map<String, dynamic>? currentUser,
    Map<String, dynamic>? siteSettings,
  }) {
    _currentUser = currentUser;
    _siteSettings = siteSettings;
  }

  /// 重置缓存（登出时调用）
  void reset() {
    _invalidateCachedData();
    _baseUri = '';
    _cdnUrl = null;
    _s3CdnUrl = null;
    _s3BaseUrl = null;
    _sharedSessionKey = null;
    _longPollingBaseUrl = null;
    _pluginCandidates = null;
  }

  /// 确保数据已加载
  Future<void> _ensureLoaded() async {
    while (true) {
      if (_loaded) return;
      final loading = _loadingFuture;
      if (loading != null) {
        final revision = _dataRevision;
        final generation = AuthSession().generation;
        try {
          await loading;
        } catch (_) {
          // 同一 revision 的调用者应看到这次加载错误；只有会话/缓存
          // 已切换时才继续等待新 revision。
          if (_isCurrent(revision, generation)) rethrow;
        }
        if (_isCurrent(revision, generation)) return;
        continue;
      }
      await _loadPreloadedData(
        revision: _dataRevision,
        generation: AuthSession().generation,
      );
      return;
    }
  }

  /// 加载预加载数据
  Future<void> _loadPreloadedData({
    required int revision,
    required int generation,
  }) {
    final active = _loadingFuture;
    if (active != null) return active;

    late final Future<void> future;
    future =
        _loadPreloadedDataInternal(
          revision: revision,
          generation: generation,
        ).whenComplete(() {
          if (identical(_loadingFuture, future)) _loadingFuture = null;
        });
    _loadingFuture = future;
    return future;
  }

  Future<void> _loadPreloadedDataInternal({
    required int revision,
    required int generation,
  }) async {
    try {
      // 发起 HTTP 请求获取数据
      _setPreloadProgress(
        const PreloadProgress(phase: PreloadPhase.requesting),
      );
      debugPrint('[PreloadedData] 发起 HTTP 请求');
      final response = await _dio.get(
        AppConstants.baseUrl,
        options: Options(
          headers: {'Accept': 'text/html'},
          extra: {
            if (AppConstants.skipCsrfForHomeRequest) 'skipCsrf': true,
            // 诊断标注:首页 HTML 是 CF 盾高发路径,日志里需可辨识
            'requestTag': 'preload-home',
          },
        ),
      );

      final html = response.data as String;
      if (!_isCurrent(revision, generation)) return;
      final parsed = await _parsePreloadedDataFromHtml(
        html,
        revision: revision,
        generation: generation,
      );
      if (!_isCurrent(revision, generation)) return;
      if (!parsed) {
        // 解析失败不可标记成功:置 _loaded 会让所有消费方拿到空数据并
        // 静默降级到接口兜底(站点改版时曾无声潜伏)。抛错让调用方走
        // BrowserTrustCoordinator 的降级链(启动 WebView 补水/重试)。
        throw const FormatException('首页 HTML 未解析出 data-preloaded 数据');
      }
      debugPrint('[PreloadedData] 数据加载成功');
      _loaded = true;
      // 预热完成后仅更新站点基础数据和 sitekey。cf_clearance 自动续期
      // 由 BrowserTrustCoordinator 统一判断启动，避免预加载服务绕过生命周期门禁。
    } catch (e) {
      if (_isCurrent(revision, generation)) {
        _setPreloadProgress(const PreloadProgress(phase: PreloadPhase.failed));
      }
      debugPrint('[PreloadedData] 加载失败: $e');
      rethrow;
    }
  }

  bool _isCurrent(int revision, int generation) {
    return revision == _dataRevision && AuthSession().isValid(generation);
  }

  /// 从 HTML 中解析预加载数据（兼容新旧两种形态）
  Future<bool> _parsePreloadedDataFromHtml(
    String html, {
    required int revision,
    required int generation,
  }) async {
    if (!_isCurrent(revision, generation)) return false;

    // Locate the preload payload first and launch its isolate decode immediately.
    // Metadata extraction below then overlaps with JSON decoding instead of delaying it.
    String? dataString;
    var htmlEntityEncoded = false;

    // 新版形态：<script type="application/json" id="data-preloaded">{...}</script>
    // 内容是原始 JSON，不做 HTML 实体解码（否则正文中字面的 &quot; 会被误还原）
    final scriptTag = RegExp(
      '''<script[^>]*id=["']data-preloaded["'][^>]*>''',
      caseSensitive: false,
    ).firstMatch(html);
    if (scriptTag != null) {
      final start = scriptTag.end;
      final end = html.indexOf('</script>', start);
      if (end > start) {
        dataString = html.substring(start, end);
      }
    }

    // 旧版形态：元素属性 data-preloaded="..."（HTML 实体转义，Isolate 中解码）
    if (dataString == null) {
      final match = RegExp(r'data-preloaded="([^"]*)"').firstMatch(html);
      if (match == null) {
        debugPrint('[PreloadedData] 未找到 data-preloaded 数据');
        return false;
      }
      dataString = match.group(1)!;
      htmlEntityEncoded = true;
    }

    _setPreloadProgress(const PreloadProgress(phase: PreloadPhase.decoding));
    final parseFuture = _parsePreloadedDataString(
      dataString,
      htmlEntityEncoded: htmlEntityEncoded,
      revision: revision,
      generation: generation,
    );

    // These small HTML metadata scans run while the preload isolate is decoding.
    _extractCsrfTokenFromHtml(html);
    _extractSharedSessionKeyFromHtml(html);
    _extractTurnstileSitekeyFromHtml(html);
    _extractBaseUriFromHtml(html);
    _extractCdnUrlFromHtml(html);

    final parsed = await parseFuture;
    if (!_isCurrent(revision, generation)) return false;

    // Plugin discovery is useful for later browser bootstrap, but must not compete
    // with the startup-critical preload JSON decode for CPU/memory bandwidth.
    if (parsed) {
      _extractPluginCandidatesInBackground(
        html,
        revision: revision,
        generation: generation,
      );
    }
    return parsed;
  }

  void _extractCsrfTokenFromHtml(String html) {
    final match = RegExp(
      "<meta[^>]+name=[\"']csrf-token[\"'][^>]+content=[\"']([^\"']+)[\"']",
      caseSensitive: false,
    ).firstMatch(html);
    if (match == null) return;
    final raw = match.group(1);
    if (raw == null || raw.isEmpty) return;
    final decoded = raw
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&#39;', "'");
    _cookieSync.setCsrfToken(decoded);
  }

  /// 从 HTML 中提取 shared_session_key（MessageBus 跨域认证）
  void _extractSharedSessionKeyFromHtml(String html) {
    final match = RegExp(
      "<meta[^>]+name=[\"']shared_session_key[\"'][^>]+content=[\"']([^\"']+)[\"']",
      caseSensitive: false,
    ).firstMatch(html);
    if (match == null) return;
    final raw = match.group(1);
    if (raw == null || raw.isEmpty) return;
    _sharedSessionKey = raw
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&#39;', "'");
    debugPrint('[PreloadedData] sharedSessionKey 提取成功');
  }

  /// 从 HTML 中提取 Turnstile sitekey（cf_clearance 自动续期用）
  void _extractTurnstileSitekeyFromHtml(String html) {
    final match = RegExp(r'data-sitekey="([0-9a-zA-Zx_-]+)"').firstMatch(html);
    if (match == null) return;
    final sitekey = match.group(1);
    if (sitekey != null && sitekey.isNotEmpty) {
      CfClearanceRefreshService().updateSitekey(sitekey);
    }
  }

  /// 从 HTML 中提取 CDN 配置（data-discourse-setup meta 标签）
  void _extractCdnUrlFromHtml(String html) {
    // 找到 data-discourse-setup 标签的完整内容
    final tagMatch = RegExp(
      r'''id=["']data-discourse-setup["'][^>]*>''',
      caseSensitive: false,
    ).firstMatch(html);
    if (tagMatch == null) return;
    _hasDiscourseSetup = true;
    final tag = tagMatch.group(0)!;

    String? extractAttr(String attrName) {
      final m = RegExp('''data-$attrName=["']([^"']+)["']''').firstMatch(tag);
      if (m == null) return null;
      final v = m.group(1);
      if (v == null || v.isEmpty) return null;
      return v.endsWith('/') ? v.substring(0, v.length - 1) : v;
    }

    _cdnUrl = extractAttr('cdn');
    _s3CdnUrl = extractAttr('s3-cdn');
    _s3BaseUrl = extractAttr('s3-base-url');

    if (_cdnUrl != null) {
      debugPrint('[PreloadedData] cdnUrl: $_cdnUrl');
    }
    if (_s3CdnUrl != null) {
      debugPrint(
        '[PreloadedData] s3CdnUrl: $_s3CdnUrl, s3BaseUrl: $_s3BaseUrl',
      );
    }
  }

  /// 从首页 HTML 扫出 plugin js url 列表。
  ///
  /// 这是 WebView session bootstrap 的优化数据，不是启动页展示的必要数据。
  /// 全 HTML 正则扫描可能较重，因此放到后台 isolate 异步填充，避免阻塞
  /// PreheatLogo 动画和预加载关键路径。未及时产出时 bootstrap 会降级为
  /// 自己 fetch 首页扫描，功能不受影响。
  void _extractPluginCandidatesInBackground(
    String html, {
    required int revision,
    required int generation,
  }) {
    final baseUrl = AppConstants.baseUrl;
    unawaited(() async {
      try {
        // 让当前解析流程先归还事件循环，避免在同一帧继续抢 UI isolate。
        await Future<void>.delayed(Duration.zero);
        final ordered = await compute<List<String>, List<String>>(
          _extractPluginCandidatesInIsolate,
          [html, baseUrl],
        );
        if (!_isCurrent(revision, generation)) return;
        _pluginCandidates = ordered.isEmpty ? null : List.unmodifiable(ordered);
        if (ordered.isNotEmpty) {
          debugPrint(
            '[PreloadedData] pluginCandidates: ${ordered.length} items',
          );
        }
      } catch (e) {
        debugPrint('[PreloadedData] pluginCandidates 提取失败: $e');
      }
    }());
  }

  bool _hasReusableBootstrapData() {
    return _hasDiscourseSetup &&
        _currentUser != null &&
        _siteSettings != null &&
        _site != null;
  }

  /// 从 HTML 中提取 discourse-base-uri（子路径部署前缀）
  void _extractBaseUriFromHtml(String html) {
    final match = RegExp(
      "<meta[^>]+name=[\"']discourse-base-uri[\"'][^>]+content=[\"']([^\"']*)[\"']",
      caseSensitive: false,
    ).firstMatch(html);

    final raw = match?.group(1) ?? '';
    if (raw.isEmpty || raw == '/') {
      _baseUri = '';
      return;
    }

    final normalized = raw.startsWith('/') ? raw : '/$raw';
    _baseUri = normalized.endsWith('/')
        ? normalized.substring(0, normalized.length - 1)
        : normalized;
    debugPrint('[PreloadedData] baseUri: $_baseUri');
  }

  /// 解析预加载数据字符串
  ///
  /// [htmlEntityEncoded] 为 true 时（旧版属性形态）先做 HTML 实体解码。
  Future<bool> _parsePreloadedDataString(
    String dataString, {
    required bool htmlEntityEncoded,
    required int revision,
    required int generation,
  }) async {
    try {
      // Phase 1: scan the outer preload object once. Nested JSON strings stay
      // raw so the large independent inner payloads can use multiple CPU cores.
      final preloaded = await compute(_scanPreloadedJsonInIsolate, [
        dataString,
        if (htmlEntityEncoded) 'entity',
      ]);
      if (preloaded == null) {
        debugPrint('[PreloadedData] 预加载 JSON 解析为空');
        return false;
      }
      if (!_isCurrent(revision, generation)) return false;

      final userSettingsRaw = <String, dynamic>{
        if (preloaded.containsKey('currentUser'))
          'currentUser': preloaded['currentUser'],
        if (preloaded.containsKey('siteSettings'))
          'siteSettings': preloaded['siteSettings'],
        if (preloaded.containsKey('topicTrackingStateMeta'))
          'topicTrackingStateMeta': preloaded['topicTrackingStateMeta'],
      };
      final siteRaw = <String, dynamic>{
        if (preloaded.containsKey('site')) 'site': preloaded['site'],
        if (preloaded.containsKey('customEmoji'))
          'customEmoji': preloaded['customEmoji'],
      };

      // Phase 2: use two coarse-grained workers instead of one long decoder.
      // This exposes real multicore parallelism without spawning one isolate
      // per tiny field and paying excessive isolate/copy overhead.
      final groups = await Future.wait<Map<String, dynamic>>([
        compute(_decodePreloadedGroupInIsolate, userSettingsRaw),
        compute(_decodePreloadedGroupInIsolate, siteRaw),
      ]);
      if (!_isCurrent(revision, generation)) return false;

      final hydrated = <String, dynamic>{};
      for (final group in groups) {
        hydrated.addAll(group);
      }

      if (hydrated.containsKey('currentUser')) {
        _currentUser = hydrated['currentUser'] as Map<String, dynamic>;
        debugPrint(
          '[PreloadedData] currentUser 解析成功: id=${_currentUser?['id']}, '
          'unread_notifications=${_currentUser?['unread_notifications']}, '
          'all_unread=${_currentUser?['all_unread_notifications_count']}',
        );
      }

      if (hydrated.containsKey('siteSettings')) {
        _siteSettings = hydrated['siteSettings'] as Map<String, dynamic>;

        final reactionsStr =
            _siteSettings?['discourse_reactions_enabled_reactions'] as String?;
        if (reactionsStr != null && reactionsStr.isNotEmpty) {
          _enabledReactions = reactionsStr.split('|');
          debugPrint('[PreloadedData] reactions: $_enabledReactions');
        }

        final pollingUrl = _siteSettings?['long_polling_base_url'] as String?;
        if (pollingUrl != null && pollingUrl.isNotEmpty && pollingUrl != '/') {
          _longPollingBaseUrl = pollingUrl.endsWith('/')
              ? pollingUrl.substring(0, pollingUrl.length - 1)
              : pollingUrl;
          debugPrint(
            '[PreloadedData] longPollingBaseUrl: $_longPollingBaseUrl',
          );
        }
      }

      if (hydrated.containsKey('site')) {
        _site = hydrated['site'] as Map<String, dynamic>;
        debugPrint(
          '[PreloadedData] site 解析成功, categories=${(_site?['categories'] as List?)?.length ?? 0}',
        );
      }

      if (hydrated.containsKey('topicTrackingStateMeta')) {
        _topicTrackingStateMeta =
            hydrated['topicTrackingStateMeta'] as Map<String, dynamic>;
        debugPrint(
          '[PreloadedData] topicTrackingStateMeta: $_topicTrackingStateMeta',
        );
      }

      if (preloaded.containsKey('topicTrackingStates')) {
        final value = preloaded['topicTrackingStates'];
        if (value is List) {
          _topicTrackingStates = value.cast<Map<String, dynamic>>();
          _topicTrackingStatesRawJson = null;
          debugPrint(
            '[PreloadedData] topicTrackingStates: ${_topicTrackingStates?.length ?? 0} items',
          );
        } else if (value is String && value.isNotEmpty) {
          _topicTrackingStatesRawJson = value;
          _topicTrackingStates = null;
          debugPrint('[PreloadedData] topicTrackingStates 后台预热');
        }
      }

      if (hydrated.containsKey('customEmoji')) {
        _customEmoji = (hydrated['customEmoji'] as List)
            .cast<Map<String, dynamic>>();
        debugPrint(
          '[PreloadedData] customEmoji: ${_customEmoji?.length ?? 0} items',
        );
      }

      // Phase 3: non-critical heavy data continues warming concurrently after
      // core hydration. Existing completers let early callers reuse the work.
      final hasTopicList = _parseTopicListFromPreloaded(
        preloaded,
        revision: revision,
        generation: generation,
      );
      if (!hasTopicList) {
        _setPreloadProgress(
          const PreloadProgress(phase: PreloadPhase.complete),
        );
      }
      if (_topicTrackingStatesRawJson != null) {
        unawaited(_decodeTopicTrackingStatesAsync());
      }
      return true;
    } catch (e) {
      debugPrint('[PreloadedData] JSON 解析失败: $e');
      if (_isCurrent(revision, generation)) {
        _setPreloadProgress(const PreloadProgress(phase: PreloadPhase.failed));
      }
      return false;
    }
  }

  /// 从预加载数据中解析话题列表
  bool _parseTopicListFromPreloaded(
    Map<String, dynamic> preloaded, {
    required int revision,
    required int generation,
  }) {
    // 尝试多个可能的 key
    final possibleKeys = ['topicList', 'topic_list', 'latest'];

    for (final key in possibleKeys) {
      if (preloaded.containsKey(key)) {
        try {
          final value = preloaded[key];
          if (value is String) {
            _decodeTopicListAsync(
              value,
              revision: revision,
              generation: generation,
            );
            return true;
          } else if (value is Map) {
            _topicListData = Map<String, dynamic>.from(value);
          }

          if (_topicListData != null) {
            final topicsCount =
                (_topicListData?['topic_list']?['topics'] as List?)?.length ??
                (_topicListData?['topics'] as List?)?.length ??
                0;
            debugPrint(
              '[PreloadedData] topic_list 解析成功 (key=$key), topics=$topicsCount',
            );
            _parseTopicListResponseAsync(
              _topicListData!,
              revision: revision,
              generation: generation,
            );
            return true;
          }
        } catch (e) {
          debugPrint('[PreloadedData] 解析 $key 失败: $e');
        }
      }
    }
    return false;
  }

  void _prepareTopicListCompleters() {
    _topicListResponseCompleter ??= Completer<TopicListResponse?>();
    _firstTopicListBatchCompleter ??= Completer<TopicListResponse?>();
  }

  void _decodeTopicListAsync(
    String rawJson, {
    required int revision,
    required int generation,
  }) {
    _prepareTopicListCompleters();
    unawaited(() async {
      try {
        final data = await compute(_decodeTopicListJsonInIsolate, rawJson);
        if (!_isCurrent(revision, generation)) return;
        if (data == null) {
          _setPreloadProgress(
            const PreloadProgress(phase: PreloadPhase.failed),
          );
          _completeTopicListWithNull();
          return;
        }
        _topicListData = data;
        await _parseTopicListResponseInBatches(
          data,
          revision: revision,
          generation: generation,
        );
      } catch (e) {
        debugPrint('[PreloadedData] 异步解析 topic_list 失败: $e');
        if (_isCurrent(revision, generation)) {
          _setPreloadProgress(
            const PreloadProgress(phase: PreloadPhase.failed),
          );
          _completeTopicListWithNull();
        }
      }
    }());
  }

  void _parseTopicListResponseAsync(
    Map<String, dynamic> data, {
    required int revision,
    required int generation,
  }) {
    _prepareTopicListCompleters();
    unawaited(
      _parseTopicListResponseInBatches(
        data,
        revision: revision,
        generation: generation,
      ),
    );
  }

  Future<void> _parseTopicListResponseInBatches(
    Map<String, dynamic> data, {
    required int revision,
    required int generation,
  }) async {
    try {
      final rawTopicList = data['topic_list'];
      if (rawTopicList is! Map) {
        final result = await compute(_parseTopicListInIsolate, data);
        if (!_isCurrent(revision, generation)) return;
        _publishTopicListSnapshot(result, finalSnapshot: true);
        _setPreloadProgress(
          const PreloadProgress(phase: PreloadPhase.complete),
        );
        return;
      }

      final topicList = Map<String, dynamic>.from(rawTopicList);
      final rawUsers = data['users'] as List<dynamic>? ?? const <dynamic>[];
      final rawTopics =
          topicList['topics'] as List<dynamic>? ?? const <dynamic>[];
      final moreTopicsUrl = topicList['more_topics_url'] as String?;
      final total = rawTopics.length;
      final accumulated = <Topic>[];
      final seenTopicIds = <int>{};

      _setPreloadProgress(
        PreloadProgress(
          phase: PreloadPhase.parsingTopics,
          parsedTopics: 0,
          totalTopics: total,
        ),
      );

      if (total == 0) {
        _publishTopicListSnapshot(
          TopicListResponse(
            topics: const <Topic>[],
            moreTopicsUrl: moreTopicsUrl,
          ),
          finalSnapshot: true,
        );
        _setPreloadProgress(
          const PreloadProgress(phase: PreloadPhase.complete),
        );
        return;
      }

      for (var start = 0; start < total; start += _topicParseBatchSize) {
        final requestedEnd = start + _topicParseBatchSize;
        final end = requestedEnd < total ? requestedEnd : total;
        final batch = await compute(
          _parseTopicBatchInIsolate,
          <String, dynamic>{
            'users': rawUsers,
            'topics': rawTopics.sublist(start, end),
          },
        );
        if (!_isCurrent(revision, generation)) return;

        for (final topic in batch) {
          if (seenTopicIds.add(topic.id)) accumulated.add(topic);
        }

        final snapshot = TopicListResponse(
          topics: List<Topic>.unmodifiable(accumulated),
          moreTopicsUrl: moreTopicsUrl,
        );
        final isFinal = end >= total;
        _publishTopicListSnapshot(snapshot, finalSnapshot: isFinal);
        _setPreloadProgress(
          PreloadProgress(
            phase: isFinal ? PreloadPhase.complete : PreloadPhase.parsingTopics,
            parsedTopics: end,
            totalTopics: total,
          ),
        );

        if (!isFinal) {
          // 给 UI isolate 一个调度点，让刚完成的一批能立即绘制出来，
          // 再继续复制下一批输入到后台 isolate。
          await Future<void>.delayed(Duration.zero);
        }
      }
    } catch (e) {
      debugPrint('[PreloadedData] 分批解析 TopicListResponse 失败: $e');
      if (_isCurrent(revision, generation)) {
        _setPreloadProgress(const PreloadProgress(phase: PreloadPhase.failed));
        _completeTopicListWithNull();
      }
    }
  }

  void _publishTopicListSnapshot(
    TopicListResponse response, {
    required bool finalSnapshot,
  }) {
    _progressiveTopicList.value = response;
    final firstBatch = _firstTopicListBatchCompleter;
    if (firstBatch != null && !firstBatch.isCompleted) {
      firstBatch.complete(response);
    }
    if (!finalSnapshot) {
      debugPrint(
        '[PreloadedData] topic_list 分批解析: ${response.topics.length} items ready',
      );
      return;
    }

    _cachedTopicListResponse = response;
    _topicListData = null;
    final complete = _topicListResponseCompleter;
    if (complete != null && !complete.isCompleted) complete.complete(response);
    debugPrint(
      '[PreloadedData] TopicListResponse 分批解析完成: ${response.topics.length} items',
    );
  }

  void _completeTopicListWithNull() {
    final firstBatch = _firstTopicListBatchCompleter;
    if (firstBatch != null && !firstBatch.isCompleted) {
      firstBatch.complete(null);
    }
    final complete = _topicListResponseCompleter;
    if (complete != null && !complete.isCompleted) complete.complete(null);
  }

  Future<void> _decodeTopicTrackingStatesAsync() async {
    if (_topicTrackingStates != null) return;
    final pending = _topicTrackingStatesCompleter;
    if (pending != null) {
      await pending.future;
      return;
    }

    final rawJson = _topicTrackingStatesRawJson;
    if (rawJson == null || rawJson.isEmpty) return;

    final completer = Completer<List<Map<String, dynamic>>?>();
    _topicTrackingStatesCompleter = completer;
    final revision = _dataRevision;
    final generation = AuthSession().generation;
    try {
      final decoded = await compute(
        _decodeTopicTrackingStatesInIsolate,
        rawJson,
      );
      if (!_isCurrent(revision, generation)) {
        completer.complete(null);
        return;
      }
      _topicTrackingStates = decoded;
      _topicTrackingStatesRawJson = null;
      debugPrint(
        '[PreloadedData] topicTrackingStates 异步解析成功: ${decoded?.length ?? 0} items',
      );
      completer.complete(decoded);
    } catch (e) {
      debugPrint('[PreloadedData] 异步解析 topicTrackingStates 失败: $e');
      completer.complete(null);
    } finally {
      if (identical(_topicTrackingStatesCompleter, completer)) {
        _topicTrackingStatesCompleter = null;
      }
    }
  }
}

Map<String, dynamic>? _decodeTopicListJsonInIsolate(String rawJson) {
  final decoded = jsonDecode(rawJson);
  if (decoded is Map<String, dynamic>) return decoded;
  if (decoded is Map) return decoded.cast<String, dynamic>();
  return null;
}

List<Topic> _parseTopicBatchInIsolate(Map<String, dynamic> input) {
  final usersJson = input['users'] as List<dynamic>? ?? const <dynamic>[];
  final userMap = <int, TopicUser>{};
  for (final rawUser in usersJson) {
    if (rawUser is! Map) continue;
    final user = TopicUser.fromJson(Map<String, dynamic>.from(rawUser));
    userMap[user.id] = user;
  }

  final topicsJson = input['topics'] as List<dynamic>? ?? const <dynamic>[];
  return topicsJson
      .whereType<Map>()
      .map(
        (rawTopic) => Topic.fromJson(
          Map<String, dynamic>.from(rawTopic),
          userMap: userMap,
        ),
      )
      .toList(growable: false);
}

List<Map<String, dynamic>>? _decodeTopicTrackingStatesInIsolate(
  String rawJson,
) {
  final decoded = jsonDecode(rawJson);
  if (decoded is! List) return null;
  return decoded.cast<Map<String, dynamic>>();
}

Map<String, dynamic>? _scanPreloadedJsonInIsolate(List<String> input) {
  return PreloadedDataDecoder.scan(
    input[0],
    htmlEntityEncoded: input.length > 1 && input[1] == 'entity',
  );
}

Map<String, dynamic> _decodePreloadedGroupInIsolate(
  Map<String, dynamic> rawGroup,
) {
  final result = <String, dynamic>{};
  for (final entry in rawGroup.entries) {
    final value = entry.value;
    if (value is String) {
      try {
        result[entry.key] = jsonDecode(value);
        continue;
      } catch (_) {
        // Preserve unusual non-JSON strings for compatibility.
      }
    }
    result[entry.key] = value;
  }
  return result;
}

List<String> _extractPluginCandidatesInIsolate(List<String> input) {
  final html = input[0];
  final baseUrl = input[1];
  final seen = <String>{};
  final ordered = <String>[];
  var index = 0;
  while (true) {
    final pluginIndex = html.indexOf('/plugins/', index);
    if (pluginIndex < 0) break;

    final raw = _extractPluginCandidateAround(html, pluginIndex);
    index = pluginIndex + '/plugins/'.length;
    if (raw == null) continue;

    final normalized = _normalizePluginCandidateUrl(raw, baseUrl);
    if (normalized == null) continue;
    if (seen.add(normalized)) {
      ordered.add(normalized);
    }
  }
  return ordered;
}

String? _extractPluginCandidateAround(String html, int pluginIndex) {
  var start = pluginIndex;
  while (start > 0 && !_isPluginCandidateBoundary(html.codeUnitAt(start - 1))) {
    start--;
  }

  var end = pluginIndex + '/plugins/'.length;
  while (end < html.length &&
      !_isPluginCandidateBoundary(html.codeUnitAt(end))) {
    end++;
  }

  var raw = html.substring(start, end);
  if (!raw.contains('/assets/')) return null;
  if (!raw.startsWith('http://') &&
      !raw.startsWith('https://') &&
      !raw.startsWith('/assets/')) {
    return null;
  }

  final jsIndex = raw.indexOf('.js', raw.indexOf('/plugins/'));
  if (jsIndex < 0) return null;
  final afterJs = jsIndex + '.js'.length;
  if (afterJs >= raw.length || raw.codeUnitAt(afterJs) != 0x3f) {
    raw = raw.substring(0, afterJs);
  }
  if (raw.isEmpty) return null;
  return raw;
}

bool _isPluginCandidateBoundary(int codeUnit) {
  return codeUnit == 0x22 || // "
      codeUnit == 0x27 || // '
      codeUnit == 0x3c || // <
      codeUnit == 0x3e || // >
      codeUnit == 0x20 ||
      codeUnit == 0x09 ||
      codeUnit == 0x0a ||
      codeUnit == 0x0d;
}

String? _normalizePluginCandidateUrl(String raw, String baseUrl) {
  final cleaned = raw.replaceAll('&amp;', '&');
  try {
    final base = Uri.parse(baseUrl);
    return base.resolve(cleaned).toString();
  } catch (_) {
    return null;
  }
}

TopicListResponse _parseTopicListInIsolate(Map<String, dynamic> json) =>
    TopicListResponse.fromJson(json);
