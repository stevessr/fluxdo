import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/discourse_providers.dart';
import '../services/discourse/user_calendar_subscriptions_api.dart';
import '../services/toast_service.dart';

class DiscourseCalendarSubscriptionsPage extends ConsumerStatefulWidget {
  final String username;

  const DiscourseCalendarSubscriptionsPage({
    super.key,
    required this.username,
  });

  @override
  ConsumerState<DiscourseCalendarSubscriptionsPage> createState() =>
      _DiscourseCalendarSubscriptionsPageState();
}

class _DiscourseCalendarSubscriptionsPageState
    extends ConsumerState<DiscourseCalendarSubscriptionsPage> {
  bool _loading = true;
  bool _busy = false;
  bool? _hasSubscription;
  Map<String, String> _urls = const {};
  List<String> _feeds = const [];
  Object? _error;

  bool get _isZh => Localizations.localeOf(context).languageCode == 'zh';
  String _tr(String zh, String en) => _isZh ? zh : en;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(discourseServiceProvider)
          .getPreferenceCalendarSubscriptions();
      if (!mounted) return;
      final feeds = result['feeds'] is List
          ? (result['feeds'] as List).map((e) => e.toString()).toList()
          : const <String>[];
      setState(() {
        _hasSubscription = result['has_subscription'] == true;
        _feeds = feeds;
        _urls = const {};
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<bool> _confirm(String title, String message, {bool danger = false}) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
            ),
            FilledButton(
              style: danger
                  ? FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error,
                      foregroundColor: Theme.of(context).colorScheme.onError,
                    )
                  : null,
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(_tr('确定', 'Confirm')),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _generate({required bool regenerate}) async {
    if (_busy) return;
    if (regenerate) {
      final ok = await _confirm(
        _tr('重新生成订阅链接？', 'Regenerate subscription links?'),
        _tr(
          '旧的日历订阅链接会立即失效。已经添加到日历应用中的旧地址必须替换。',
          'Existing calendar subscription URLs will stop working immediately. Replace old URLs already added to calendar apps.',
        ),
      );
      if (!ok || !mounted) return;
    }

    setState(() => _busy = true);
    try {
      final result = await ref
          .read(discourseServiceProvider)
          .createPreferenceCalendarSubscriptions();
      final rawUrls = result['urls'];
      final urls = <String, String>{};
      if (rawUrls is Map) {
        for (final entry in rawUrls.entries) {
          final value = entry.value?.toString();
          if (value != null && value.isNotEmpty) {
            urls[entry.key.toString()] = value;
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _hasSubscription = true;
        _urls = urls;
      });
      ToastService.showSuccess(
        regenerate
            ? _tr('订阅链接已重新生成', 'Subscription links regenerated')
            : _tr('订阅链接已生成', 'Subscription links generated'),
      );
    } catch (e) {
      if (mounted) {
        ToastService.showError(e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revoke() async {
    if (_busy || _hasSubscription != true) return;
    final ok = await _confirm(
      _tr('撤销日历订阅？', 'Revoke calendar subscription?'),
      _tr(
        '所有当前私密订阅链接都会失效。之后可以重新生成新的链接。',
        'All current private subscription URLs will stop working. You can generate new URLs later.',
      ),
      danger: true,
    );
    if (!ok || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref
          .read(discourseServiceProvider)
          .revokePreferenceCalendarSubscriptions();
      if (!mounted) return;
      setState(() {
        _hasSubscription = false;
        _urls = const {};
      });
      ToastService.showSuccess(_tr('日历订阅已撤销', 'Calendar subscription revoked'));
    } catch (e) {
      if (mounted) {
        ToastService.showError(e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _copy(String value) {
    Clipboard.setData(ClipboardData(text: value));
    ToastService.showSuccess(_tr('订阅链接已复制', 'Subscription URL copied'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_tr('日历订阅', 'Calendar subscriptions')),
        actions: [
          if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 18),
              child: Center(
                child: SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 42),
              const SizedBox(height: 12),
              Text(_error.toString(), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: Text(_tr('重试', 'Retry')),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _tr(
                    '将 Discourse 中可导出的日历内容订阅到外部日历应用。默认包含书签提醒；站点插件还可以注册其它订阅源。',
                    'Subscribe supported Discourse calendar data in an external calendar app. Bookmark reminders are included by default and plugins may register additional feeds.',
                  ),
                ),
                if (_feeds.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final feed in _feeds) Chip(label: Text(_feedLabel(feed))),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (_urls.isNotEmpty) ...[
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _tr(
                        '这些 URL 包含私密 User API Key。任何拿到链接的人都可能读取对应订阅内容，请像密码一样保护它们。',
                        'These URLs contain a private User API key. Anyone with a URL may read the corresponding feed, so treat it like a password.',
                      ),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          for (final entry in _urls.entries) ...[
            _urlCard(entry.key, entry.value),
            const SizedBox(height: 12),
          ],
          OutlinedButton.icon(
            onPressed: _busy ? null : _revoke,
            icon: const Icon(Icons.delete_outline),
            label: Text(_tr('撤销订阅', 'Revoke subscription')),
          ),
        ] else if (_hasSubscription == true) ...[
          Card(
            child: ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: Text(_tr('已有有效日历订阅', 'Calendar subscription is active')),
              subtitle: Text(
                _tr(
                  '出于安全原因，Discourse 不会再次返回现有私密 URL。重新生成后旧链接会失效。',
                  'For security, Discourse does not reveal existing private URLs again. Regenerating them invalidates the old URLs.',
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : () => _generate(regenerate: true),
            icon: const Icon(Icons.refresh),
            label: Text(_tr('重新生成订阅链接', 'Regenerate subscription links')),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _revoke,
            icon: const Icon(Icons.delete_outline),
            label: Text(_tr('撤销订阅', 'Revoke subscription')),
          ),
        ] else ...[
          FilledButton.icon(
            onPressed: _busy ? null : () => _generate(regenerate: false),
            icon: const Icon(Icons.calendar_month_outlined),
            label: Text(_tr('生成订阅链接', 'Generate subscription links')),
          ),
        ],
      ],
    );
  }

  Widget _urlCard(String feed, String url) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _feedLabel(feed),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              SelectableText(url),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _copy(url),
                  icon: const Icon(Icons.copy_outlined),
                  label: Text(_tr('复制', 'Copy')),
                ),
              ),
            ],
          ),
        ),
      );

  String _feedLabel(String feed) {
    if (feed == 'bookmarks') return _tr('书签提醒', 'Bookmark reminders');
    return feed
        .replaceAll('_', ' ')
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }
}
