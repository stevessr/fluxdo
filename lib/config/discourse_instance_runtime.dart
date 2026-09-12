/// 运行时 Discourse 实例配置。
///
/// 默认实例必须继续使用旧 key，确保现有 linux.do 安装无需迁移；只有自定义
/// 实例才附加 namespace。持久化注册表由 DiscourseInstanceManager 负责。
class DiscourseInstanceRuntime {
  DiscourseInstanceRuntime._();

  static const String defaultInstanceId = 'linux-do';
  static const String defaultBaseUrl = 'https://linux.do';

  static const String enabledPrefKey =
      'experimental_multi_discourse_enabled_v1';
  static const String instancesPrefKey = 'experimental_discourse_instances_v1';
  static const String activeInstanceIdPrefKey =
      'experimental_discourse_active_instance_id_v1';
  static const String activeBaseUrlPrefKey =
      'experimental_discourse_active_base_url_v1';

  static String _instanceId = defaultInstanceId;
  static String _baseUrl = defaultBaseUrl;

  static String get instanceId => _instanceId;
  static String get baseUrl => _baseUrl;
  static bool get isDefaultInstance => _instanceId == defaultInstanceId;
  static Uri get baseUri => Uri.parse(_baseUrl);

  static void activate({required String instanceId, required String baseUrl}) {
    final normalizedBaseUrl = normalizeBaseUrl(baseUrl);
    final canonicalId = instanceIdForBaseUrl(normalizedBaseUrl);
    final requestedId = instanceId.trim();

    // 自定义实例的 namespace 绝不能信任可损坏/可篡改的持久化 id；它必须
    // 由规范化 URL 唯一决定，否则两个不同站点可以被错误地映射到同一个
    // Secure Storage namespace。正常历史数据本来就使用 canonicalId，因此
    // 这里不会迁移现有有效配置。
    _instanceId = requestedId == canonicalId ? requestedId : canonicalId;
    _baseUrl = normalizedBaseUrl;
  }

  static void reset() {
    _instanceId = defaultInstanceId;
    _baseUrl = defaultBaseUrl;
  }

  /// 从规范化后的站点 URL 派生稳定实例 ID。
  ///
  /// 默认 linux.do 固定沿用历史 ID；自定义实例的 ID 与 URL 一一对应，避免
  /// 注册表损坏时出现跨实例凭证 namespace 碰撞。scheme/host 已在
  /// [normalizeBaseUrl] 中标准化为小写，但 path 必须保留大小写：HTTP path
  /// 可以区分 `/Forum` 与 `/forum`，不能再次对整个 URL 调用 toLowerCase()。
  static String instanceIdForBaseUrl(String baseUrl) {
    final normalized = normalizeBaseUrl(baseUrl);
    if (normalized == defaultBaseUrl) return defaultInstanceId;
    return 'site-${Uri.encodeComponent(normalized)}';
  }

  /// 账号/缓存等已有持久化 key 的实例级 namespace。
  ///
  /// linux.do 返回原 key，保证升级兼容；其他实例才追加实例 id。
  static String scopedStorageKey(String legacyKey) {
    if (isDefaultInstance) return legacyKey;
    return '$legacyKey::discourse_instance::${Uri.encodeComponent(instanceId)}';
  }

  /// 当前 URI 是否属于活动 Discourse 实例。
  ///
  /// 自定义实例严格限制为同 scheme / host / port，并且路径必须位于配置的
  /// relative-url-root 下。默认 linux.do 为保持既有深链/WebView 行为，允许
  /// linux.do 的子域；默认实例没有 relative-url-root，因此不会扩大路径边界。
  static bool containsUri(Uri uri, {bool allowDefaultSubdomains = true}) {
    final base = baseUri;
    if (uri.scheme.toLowerCase() != base.scheme.toLowerCase()) return false;

    final host = uri.host.toLowerCase();
    final baseHost = base.host.toLowerCase();
    final hostMatches =
        host == baseHost ||
        (isDefaultInstance &&
            allowDefaultSubdomains &&
            host.endsWith('.$baseHost'));
    if (!hostMatches) return false;

    if (_effectivePort(uri) != _effectivePort(base)) return false;

    // linux.do 的子域各自是独立服务，不把主站 path 约束套到它们身上。
    if (host != baseHost) return true;

    final root = _normalizeBasePath(base.path);
    if (root.isEmpty) return true;
    final path = uri.path.isEmpty ? '/' : uri.path;
    return path == root || path.startsWith('$root/');
  }

  /// 把活动实例内的绝对 path 转为 Discourse 自身的 root-relative path。
  /// 不属于当前实例时返回 null，避免 `/forum` 外的 `/other/t/1` 被误识别。
  static String? pathWithinInstance(Uri uri) {
    if (!containsUri(uri, allowDefaultSubdomains: false)) return null;
    final root = _normalizeBasePath(baseUri.path);
    final path = uri.path.isEmpty ? '/' : uri.path;
    if (root.isEmpty) return path;
    if (path == root) return '/';
    return path.substring(root.length);
  }

  static int _effectivePort(Uri uri) {
    if (uri.hasPort) return uri.port;
    return uri.scheme.toLowerCase() == 'https' ? 443 : 80;
  }

  static String _normalizeBasePath(String path) {
    if (path.isEmpty || path == '/') return '';
    final withLeadingSlash = path.startsWith('/') ? path : '/$path';
    return withLeadingSlash.replaceFirst(RegExp(r'/+$'), '');
  }

  /// 标准化为 origin + 可选 Discourse 子目录，不保留 query/fragment。
  static String normalizeBaseUrl(String input) {
    var value = input.trim();
    if (value.isEmpty) {
      throw const FormatException('Discourse 地址不能为空');
    }
    if (!value.contains('://')) value = 'https://$value';

    final uri = Uri.tryParse(value);
    if (uri == null ||
        (uri.scheme.toLowerCase() != 'https' &&
            uri.scheme.toLowerCase() != 'http') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException('请输入有效的 http/https Discourse 地址');
    }

    var path = uri.path;
    if (path == '/') {
      path = '';
    } else {
      path = path.replaceFirst(RegExp(r'/+$'), '');
      if (path.isNotEmpty && !path.startsWith('/')) path = '/$path';
    }

    return uri
        .replace(
          scheme: uri.scheme.toLowerCase(),
          host: uri.host.toLowerCase(),
          path: path,
          // Uri.replace 的 null 表示“保留原字段”，不是删除。显式空字符串
          // 才能把用户粘贴进来的 query/fragment 从实例身份中彻底移除。
          query: '',
          fragment: '',
        )
        .toString()
        .replaceFirst(RegExp(r'/+$'), '');
  }
}
