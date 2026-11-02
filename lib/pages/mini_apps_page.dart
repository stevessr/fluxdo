import 'package:flutter/material.dart';

import '../constants.dart';
import '../models/mini_app.dart';
import '../services/discourse/discourse_service.dart';
import 'webview_page.dart';

/// Native directory for site-hosted mini apps. Execution stays in the website:
/// no JavaScript bridge or native privileges are granted to mini app code.
class MiniAppsPage extends StatefulWidget {
  const MiniAppsPage({super.key, this.isActive = true});

  final bool isActive;

  @override
  State<MiniAppsPage> createState() => _MiniAppsPageState();
}

class _MiniAppsPageState extends State<MiniAppsPage> {
  final List<MiniApp> _apps = [];
  bool _loading = false;
  bool _hasNext = true;
  int _page = 0;
  int _generation = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.isActive) {
      _loadPage(reset: true);
    }
  }

  @override
  void didUpdateWidget(covariant MiniAppsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive && _apps.isEmpty &&
        !_loading && _error == null) {
      _loadPage(reset: true);
    }
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  Future<void> _loadPage({bool reset = false}) async {
    if (_loading && !reset) return;
    final generation = ++_generation;
    final requestedPage = reset ? 0 : _page;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _apps.clear();
        _page = 0;
        _hasNext = true;
      }
    });
    try {
      final response = await DiscourseService().dio.get<Object?>(
        '${AppConstants.baseUrl}/apps/directory.json',
        queryParameters: {'page': requestedPage},
      );
      final directory = MiniAppDirectory.parse(
        response.data,
        site: Uri.parse(AppConstants.baseUrl),
        requestedPage: requestedPage,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        final existingIds = _apps.map((app) => app.id).toSet();
        for (final app in directory.apps) {
          if (existingIds.add(app.id)) _apps.add(app);
        }
        _page = directory.page + 1;
        _hasNext = directory.hasNext;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = '无法获取应用目录，站点可能尚未开放目录接口。';
      });
    }
  }

  void _openDirectoryWebsite() {
    WebViewPage.open(context, '${AppConstants.baseUrl}/apps', title: '应用');
  }

  Widget _buildIcon(MiniApp app) {
    if (app.iconUrl == null) {
      return const Icon(Icons.apps_rounded, size: 28);
    }
    return Image.network(
      app.iconUrl!,
      width: 44,
      height: 44,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => const Icon(Icons.apps_rounded, size: 28),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    final zh = locale == 'zh';
    return Scaffold(
      appBar: AppBar(
        title: Text(zh ? '站内应用' : 'Mini apps'),
        actions: [
          IconButton(
            tooltip: zh ? '网页目录' : 'Website directory',
            icon: const Icon(Icons.open_in_browser_rounded),
            onPressed: _openDirectoryWebsite,
          ),
          IconButton(
            tooltip: zh ? '刷新' : 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => _loadPage(reset: true),
          ),
        ],
      ),
      body: _apps.isEmpty && _loading
          ? const Center(child: CircularProgressIndicator())
          : _apps.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.apps_outage_rounded, size: 52),
                        const SizedBox(height: 12),
                        Text(
                          _error ??
                              (zh ? '暂无可用的站内应用' : 'No mini apps available'),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton.tonalIcon(
                          onPressed: _openDirectoryWebsite,
                          icon: const Icon(Icons.open_in_browser_rounded),
                          label: Text(zh ? '查看网页目录' : 'Open web directory'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => _loadPage(reset: true),
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                    itemCount: _apps.length + (_hasNext || _error != null ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _apps.length) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: _loading
                                ? const CircularProgressIndicator()
                                : TextButton(
                                    onPressed: () => _loadPage(),
                                    child: Text(_error != null
                                        ? (zh ? '加载失败，重试' : 'Retry')
                                        : (zh ? '加载更多' : 'Load more')),
                                  ),
                          ),
                        );
                      }
                      final app = _apps[index];
                      return Card(
                        clipBehavior: Clip.antiAlias,
                        child: ListTile(
                          leading: SizedBox(
                            width: 44,
                            height: 44,
                            child: Center(child: _buildIcon(app)),
                          ),
                          title: Text(app.name),
                          subtitle: Text(
                            [
                              if (app.description.isNotEmpty) app.description,
                              if (app.ageRating != null)
                                zh ? '适用年龄 ${app.ageRating}+' : 'Age ${app.ageRating}+',
                            ].join(' · '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => WebViewPage.open(
                            context,
                            app.url.toString(),
                            title: app.name,
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
