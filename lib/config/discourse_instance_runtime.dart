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
  static const String instancesPrefKey =
      'experimental_discourse_instances_v1';
  static const String activeInstanceIdPrefKey =
      'experimental_discourse_active_instance_id_v1';
  static const String activeBaseUrlPrefKey =
      'experimental_discourse_active_base_url_v1';

  static String _instanceId = defaultInstanceId;
  static String _baseUrl = defaultBaseUrl;

  static String get instanceId => _instanceId;
  static String get baseUrl => _baseUrl;
  static bool get isDefaultInstance => _instanceId == defaultInstanceId;

  static void activate({required String instanceId, required String baseUrl}) {
    _instanceId = instanceId.trim().isEmpty ? defaultInstanceId : instanceId;
    _baseUrl = normalizeBaseUrl(baseUrl);
  }

  static void reset() {
    _instanceId = defaultInstanceId;
    _baseUrl = defaultBaseUrl;
  }

  /// 账号/缓存等已有持久化 key 的实例级 namespace。
  ///
  /// linux.do 返回原 key，保证升级兼容；其他实例才追加实例 id。
  static String scopedStorageKey(String legacyKey) {
    if (isDefaultInstance) return legacyKey;
    return '$legacyKey::discourse_instance::${Uri.encodeComponent(instanceId)}';
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
        (uri.scheme != 'https' && uri.scheme != 'http') ||
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
        .replace(path: path, query: null, fragment: null)
        .toString()
        .replaceFirst(RegExp(r'/+$'), '');
  }
}
