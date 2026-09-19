import 'package:enhanced_cookie_jar/enhanced_cookie_jar.dart';
import 'package:flutter/material.dart';

import '../services/network/cookie/site_cookie_manager_service.dart';

class WebViewCookieManagerPage extends StatefulWidget {
  const WebViewCookieManagerPage({
    super.key,
    required this.currentUrl,
  });

  final String currentUrl;

  static Future<void> open(BuildContext context, String currentUrl) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => WebViewCookieManagerPage(currentUrl: currentUrl),
      ),
    );
  }

  @override
  State<WebViewCookieManagerPage> createState() =>
      _WebViewCookieManagerPageState();
}

class _WebViewCookieManagerPageState
    extends State<WebViewCookieManagerPage> {
  final SiteCookieManagerService _service = SiteCookieManagerService.instance;

  List<ManagedSiteCookie> _cookies = const [];
  List<String> _hosts = const [];
  final Set<String> _selected = <String>{};

  bool _loading = true;
  String? _error;
  String _query = '';
  String? _hostFilter;

  String get _currentHost =>
      Uri.tryParse(widget.currentUrl)?.host.toLowerCase() ?? '';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final hosts = await _service.discoverRelatedHosts(widget.currentUrl);
      final cookies = await _service.listCookies(widget.currentUrl);
      if (!mounted) return;
      setState(() {
        _hosts = hosts;
        _cookies = cookies;
        _selected.removeWhere(
          (key) => !cookies.any((cookie) => cookie.identityKey == key),
        );
        if (_hostFilter != null && !hosts.contains(_hostFilter)) {
          _hostFilter = null;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<ManagedSiteCookie> get _visibleCookies {
    final query = _query.trim().toLowerCase();
    return _cookies.where((cookie) {
      if (_hostFilter != null && cookie.domain != _hostFilter) return false;
      if (query.isEmpty) return true;
      return cookie.name.toLowerCase().contains(query) ||
          cookie.value.toLowerCase().contains(query) ||
          cookie.domain.toLowerCase().contains(query) ||
          cookie.path.toLowerCase().contains(query);
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleCookies;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cookie 管理器'),
        actions: [
          IconButton(
            tooltip: '添加 Cookie',
            onPressed: _loading ? null : () => _showEditor(),
            icon: const Icon(Icons.add_rounded),
          ),
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : _reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'clear_current':
                  _clearHosts({_currentHost});
                case 'clear_filter':
                  final host = _hostFilter;
                  if (host != null) _clearHosts({host});
                case 'clear_all_related':
                  _clearHosts(_hosts.toSet());
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'clear_current',
                child: Text('清除当前站点 Cookie'),
              ),
              if (_hostFilter != null && _hostFilter != _currentHost)
                PopupMenuItem(
                  value: 'clear_filter',
                  child: Text('清除 $_hostFilter Cookie'),
                ),
              if (_hosts.length > 1)
                const PopupMenuItem(
                  value: 'clear_all_related',
                  child: Text('清除所有相关站点 Cookie'),
                ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SearchBar(
              leading: const Icon(Icons.search_rounded),
              hintText: '搜索名称、值、域名或路径',
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          if (_hosts.isNotEmpty)
            SizedBox(
              height: 48,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                scrollDirection: Axis.horizontal,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: FilterChip(
                      label: Text('全部 (${_cookies.length})'),
                      selected: _hostFilter == null,
                      onSelected: (_) => setState(() => _hostFilter = null),
                    ),
                  ),
                  for (final host in _hosts)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: FilterChip(
                        label: Text(
                          '$host (${_cookies.where((c) => c.domain == host).length})',
                        ),
                        selected: _hostFilter == host,
                        onSelected: (_) => setState(() => _hostFilter = host),
                      ),
                    ),
                ],
              ),
            ),
          if (_selected.isNotEmpty)
            Material(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('已选择 ${_selected.length} 项'),
                    ),
                    TextButton.icon(
                      onPressed: _deleteSelected,
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: const Text('删除'),
                    ),
                    TextButton(
                      onPressed: () => setState(_selected.clear),
                      child: const Text('取消选择'),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(child: _buildContent(visible)),
        ],
      ),
    );
  }

  Widget _buildContent(List<ManagedSiteCookie> visible) {
    if (_loading && _cookies.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _cookies.isEmpty) {
      return _EmptyState(
        icon: Icons.error_outline_rounded,
        title: '无法读取 Cookie',
        message: _error!,
        action: FilledButton(
          onPressed: _reload,
          child: const Text('重试'),
        ),
      );
    }
    if (visible.isEmpty) {
      return _EmptyState(
        icon: Icons.cookie_outlined,
        title: _cookies.isEmpty ? '当前站点没有 Cookie' : '没有匹配项',
        message: _cookies.isEmpty
            ? '可以使用右上角 + 手动添加 Cookie。'
            : '尝试修改搜索词或域名筛选。',
      );
    }

    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        itemCount: visible.length,
        separatorBuilder: (_, __) => const SizedBox(height: 6),
        itemBuilder: (context, index) {
          final cookie = visible[index];
          final selected = _selected.contains(cookie.identityKey);
          return Card(
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              leading: Checkbox(
                value: selected,
                onChanged: (value) {
                  setState(() {
                    if (value == true) {
                      _selected.add(cookie.identityKey);
                    } else {
                      _selected.remove(cookie.identityKey);
                    }
                  });
                },
              ),
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      cookie.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (cookie.httpOnly) const _CookieFlag(label: 'HttpOnly'),
                  if (cookie.secure) const _CookieFlag(label: 'Secure'),
                  if (cookie.partitioned)
                    const _CookieFlag(label: 'Partitioned'),
                ],
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cookie.value.isEmpty ? '(空值)' : cookie.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${cookie.hostOnly ? 'Host-only · ' : ''}'
                      '${cookie.domain}${cookie.path} · '
                      '${_sourceLabel(cookie)}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (!cookie.fieldsComplete)
                      Text(
                        '平台仅提供部分字段；domain/path 可能由 CookieJar 补全。',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.tertiary,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              onTap: () => _showEditor(cookie),
              trailing: PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'edit') _showEditor(cookie);
                  if (value == 'delete') _deleteOne(cookie);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('编辑')),
                  PopupMenuItem(value: 'delete', child: Text('删除')),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _sourceLabel(ManagedSiteCookie cookie) {
    if (cookie.inWebView && cookie.inJar) return 'WebView + CookieJar';
    if (cookie.inWebView) return 'WebView';
    if (cookie.inJar) return 'CookieJar';
    return '未知来源';
  }

  Future<void> _showEditor([ManagedSiteCookie? cookie]) async {
    if (_hosts.isEmpty && _currentHost.isEmpty) return;

    final nameController = TextEditingController(text: cookie?.name ?? '');
    final valueController = TextEditingController(text: cookie?.value ?? '');
    final domainController = TextEditingController(
      text: cookie == null || cookie.hostOnly ? '' : cookie.domain,
    );
    final pathController = TextEditingController(text: cookie?.path ?? '/');
    final expiresController = TextEditingController(
      text: cookie?.expiresAt?.toUtc().toIso8601String() ?? '',
    );

    var selectedHost = cookie?.host ??
        (_hosts.contains(_currentHost) ? _currentHost : _hosts.first);
    var secure = cookie?.secure ?? true;
    var httpOnly = cookie?.httpOnly ?? false;
    var partitioned = cookie?.partitioned ?? false;
    var sameSite = cookie?.sameSite ?? CookieSameSite.unspecified;
    var saving = false;
    String? error;

    try {
      final changed = await showModalBottomSheet<bool>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheetContext) {
          return StatefulBuilder(
            builder: (context, setSheetState) {
              Future<void> save() async {
                final expiryText = expiresController.text.trim();
                DateTime? expiresAt;
                if (expiryText.isNotEmpty) {
                  expiresAt = DateTime.tryParse(expiryText);
                  if (expiresAt == null) {
                    setSheetState(
                      () => error = 'Expires 格式无效，请使用 ISO 8601 时间。',
                    );
                    return;
                  }
                }

                setSheetState(() {
                  saving = true;
                  error = null;
                });
                try {
                  await _service.saveCookie(
                    widget.currentUrl,
                    SiteCookieDraft(
                      host: selectedHost,
                      name: nameController.text,
                      value: valueController.text,
                      domain: domainController.text.trim().isEmpty
                          ? null
                          : domainController.text.trim(),
                      path: pathController.text,
                      expiresAt: expiresAt,
                      secure: secure,
                      httpOnly: httpOnly,
                      sameSite: sameSite,
                      partitioned: partitioned,
                    ),
                    original: cookie,
                  );
                  if (sheetContext.mounted) {
                    Navigator.of(sheetContext).pop(true);
                  }
                } catch (e) {
                  setSheetState(() {
                    saving = false;
                    error = e.toString();
                  });
                }
              }

              return Padding(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        cookie == null ? '添加 Cookie' : '编辑 Cookie',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: selectedHost,
                        decoration: const InputDecoration(
                          labelText: 'Host',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final host in _hosts)
                            DropdownMenuItem(value: host, child: Text(host)),
                          if (_hosts.isEmpty && _currentHost.isNotEmpty)
                            DropdownMenuItem(
                              value: _currentHost,
                              child: Text(_currentHost),
                            ),
                        ],
                        onChanged: saving
                            ? null
                            : (value) {
                                if (value != null) {
                                  setSheetState(() => selectedHost = value);
                                }
                              },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: nameController,
                        enabled: !saving,
                        decoration: const InputDecoration(
                          labelText: 'Name',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: valueController,
                        enabled: !saving,
                        minLines: 2,
                        maxLines: 5,
                        decoration: const InputDecoration(
                          labelText: 'Value',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: domainController,
                        enabled: !saving,
                        decoration: const InputDecoration(
                          labelText: 'Domain',
                          helperText: '留空表示 Host-only Cookie',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: pathController,
                        enabled: !saving,
                        decoration: const InputDecoration(
                          labelText: 'Path',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: expiresController,
                        enabled: !saving,
                        decoration: const InputDecoration(
                          labelText: 'Expires',
                          helperText: '留空表示 Session；支持 ISO 8601',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<CookieSameSite>(
                        initialValue: sameSite,
                        decoration: const InputDecoration(
                          labelText: 'SameSite',
                          border: OutlineInputBorder(),
                        ),
                        items: CookieSameSite.values
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(_sameSiteLabel(value)),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: saving
                            ? null
                            : (value) {
                                if (value == null) return;
                                setSheetState(() {
                                  sameSite = value;
                                  if (sameSite == CookieSameSite.none) {
                                    secure = true;
                                  }
                                });
                              },
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Secure'),
                        value: secure,
                        onChanged: saving ||
                                sameSite == CookieSameSite.none ||
                                partitioned
                            ? null
                            : (value) => setSheetState(() => secure = value),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('HttpOnly'),
                        value: httpOnly,
                        onChanged: saving
                            ? null
                            : (value) =>
                                setSheetState(() => httpOnly = value),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Partitioned (CHIPS)'),
                        subtitle: const Text('启用后会自动要求 Secure'),
                        value: partitioned,
                        onChanged: saving
                            ? null
                            : (value) {
                                setSheetState(() {
                                  partitioned = value;
                                  if (value) secure = true;
                                });
                              },
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: saving
                                ? null
                                : () => Navigator.of(sheetContext).pop(false),
                            child: const Text('取消'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: saving ? null : save,
                            icon: saving
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.save_rounded),
                            label: const Text('保存'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );

      if (changed == true) {
        await _reload();
      }
    } finally {
      nameController.dispose();
      valueController.dispose();
      domainController.dispose();
      pathController.dispose();
      expiresController.dispose();
    }
  }

  Future<void> _deleteOne(ManagedSiteCookie cookie) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除 Cookie'),
        content: Text('确定删除 ${cookie.name}？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _runMutation(
      () => _service.deleteCookie(widget.currentUrl, cookie),
      success: '已删除 ${cookie.name}',
    );
  }

  Future<void> _deleteSelected() async {
    final targets = _cookies
        .where((cookie) => _selected.contains(cookie.identityKey))
        .toList(growable: false);
    if (targets.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('批量删除 Cookie'),
        content: Text('确定删除 ${targets.length} 个 Cookie？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _runMutation(
      () => _service.deleteCookies(widget.currentUrl, targets),
      success: '已删除 ${targets.length} 个 Cookie',
    );
  }

  Future<void> _clearHosts(Set<String> hosts) async {
    if (hosts.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除站点 Cookie'),
        content: Text(
          hosts.length == 1
              ? '确定清除 ${hosts.first} 的全部 Cookie？'
              : '确定清除 ${hosts.length} 个相关站点的全部 Cookie？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _runMutation(
      () => _service.clearHosts(widget.currentUrl, hosts),
      success: '站点 Cookie 已清除',
    );
  }

  Future<void> _runMutation(
    Future<void> Function() action, {
    required String success,
  }) async {
    try {
      await action();
      _selected.clear();
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(success)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('操作失败：$e')),
      );
      await _reload();
    }
  }

  static String _sameSiteLabel(CookieSameSite value) {
    switch (value) {
      case CookieSameSite.unspecified:
        return 'Unspecified';
      case CookieSameSite.lax:
        return 'Lax';
      case CookieSameSite.strict:
        return 'Strict';
      case CookieSameSite.none:
        return 'None';
    }
  }
}

class _CookieFlag extends StatelessWidget {
  const _CookieFlag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48),
            const SizedBox(height: 12),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[
              const SizedBox(height: 16),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
