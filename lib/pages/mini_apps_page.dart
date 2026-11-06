import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../constants.dart';
import '../models/mini_app.dart';
import '../services/discourse/discourse_service.dart';
import '../services/mini_app_directory_repository.dart';
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
  final ScrollController _scrollController = ScrollController();
  late final MiniAppDirectoryRepository _repository = MiniAppDirectoryRepository(
    dio: DiscourseService().dio,
    site: Uri.parse(AppConstants.baseUrl),
  );

  bool _loading = false;
  bool _refreshing = false;
  bool _retryReset = false;
  bool _hasNext = true;
  int _page = 0;
  int _generation = 0;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_maybeLoadMore);
    if (widget.isActive) {
      unawaited(_loadPage(reset: true));
    }
  }

  @override
  void didUpdateWidget(covariant MiniAppsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive &&
        !oldWidget.isActive &&
        _apps.isEmpty &&
        !_loading &&
        _error == null) {
      unawaited(_loadPage(reset: true));
    }
  }

  @override
  void dispose() {
    _generation++;
    _scrollController.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (!mounted ||
        !widget.isActive ||
        _loading ||
        !_hasNext ||
        _error != null ||
        _apps.isEmpty ||
        !_scrollController.hasClients) {
      return;
    }
    if (_scrollController.position.extentAfter < 480) {
      unawaited(_loadPage());
    }
  }

  void _fillViewportIfNeeded() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeLoadMore());
  }

  Future<void> _loadPage({bool reset = false}) async {
    if (_loading && !reset) return;
    final generation = ++_generation;
    final requestedPage = reset ? 0 : _page;
    setState(() {
      _loading = true;
      _refreshing = reset && _apps.isNotEmpty;
      _retryReset = false;
      _error = null;
    });

    try {
      final directory = await _repository.fetchPage(requestedPage);
      if (!mounted || generation != _generation) return;
      setState(() {
        if (reset) _apps.clear();

        final existingIds = _apps.map((app) => app.id).toSet();
        var added = 0;
        for (final app in directory.apps) {
          if (existingIds.add(app.id)) {
            _apps.add(app);
            added++;
          }
        }
        _page = directory.nextPage;
        // Avoid refetching an endless duplicate page from a broken endpoint.
        _hasNext = directory.hasNext && (reset || added > 0);
        _loading = false;
        _refreshing = false;
      });
      _fillViewportIfNeeded();
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        // Keep the last successful list and cursor if a refresh failed.
        _loading = false;
        _refreshing = false;
        _retryReset = reset;
        _error = error;
      });
    }
  }

  String _errorMessage(bool zh) {
    final error = _error;
    if (error is FormatException) {
      return zh
          ? '应用目录返回了不支持的数据格式'
          : 'The app directory returned an unsupported format';
    }
    if (error is DioException) {
      final code = error.response?.statusCode;
      if (code == 401 || code == 403) {
        return zh ? '无法访问应用目录，请检查登录状态' : 'App directory access denied';
      }
      if (code == 429) {
        return zh ? '请求过于频繁，请稍后重试' : 'Too many requests. Try again later';
      }
      if (code == 404 || code == 405) {
        return zh ? '站点暂未提供可用的应用目录接口' : 'App directory API is unavailable';
      }
    }
    return zh ? '应用目录加载失败，请检查网络后重试' : 'Could not load apps. Try again';
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
    final zh = Localizations.localeOf(context).languageCode == 'zh';
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
            onPressed: () => unawaited(_loadPage(reset: true)),
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
                      _error != null
                          ? _errorMessage(zh)
                          : (zh ? '暂无可用的站内应用' : 'No mini apps available'),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    if (_error != null || _hasNext)
                      FilledButton.tonalIcon(
                        onPressed: () => unawaited(
                          _loadPage(reset: _retryReset),
                        ),
                        icon: const Icon(Icons.refresh_rounded),
                        label: Text(zh ? '重试' : 'Retry'),
                      ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _openDirectoryWebsite,
                      icon: const Icon(Icons.open_in_browser_rounded),
                      label: Text(zh ? '查看网页目录' : 'Open web directory'),
                    ),
                  ],
                ),
              ),
            )
          : Column(
              children: [
                if (_refreshing) const LinearProgressIndicator(minHeight: 2),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () => _loadPage(reset: true),
                    child: ListView.builder(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
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
                                      onPressed: () => unawaited(
                                        _loadPage(reset: _retryReset),
                                      ),
                                      child: Text(
                                        _error != null
                                            ? (zh ? '加载失败，重试' : 'Retry')
                                            : (zh ? '加载更多' : 'Load more'),
                                      ),
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
                                  zh
                                      ? '适用年龄 ${app.ageRating}+'
                                      : 'Age ${app.ageRating}+',
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
                ),
              ],
            ),
    );
  }
}
