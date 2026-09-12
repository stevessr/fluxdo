import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/discourse_providers.dart';
import '../services/discourse/user_preferences_api.dart';
import '../services/preloaded_data_service.dart';
import '../services/toast_service.dart';

class DiscourseLanguagePage extends ConsumerStatefulWidget {
  final String username;

  const DiscourseLanguagePage({super.key, required this.username});

  @override
  ConsumerState<DiscourseLanguagePage> createState() =>
      _DiscourseLanguagePageState();
}

class _DiscourseLanguagePageState
    extends ConsumerState<DiscourseLanguagePage> {
  bool _loading = true;
  bool _saving = false;
  bool _allowUserLocale = false;
  Object? _error;
  String? _selectedLocale;
  List<_LocaleOption> _locales = const [];

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
      final service = ref.read(discourseServiceProvider);
      final settings =
          await PreloadedDataService().getSiteSettings() ?? <String, dynamic>{};
      final user = await service.getUserPreferences(widget.username);

      final allowUserLocale = settings['allow_user_locale'] == true ||
          settings['allow_user_locale']?.toString() == 'true';
      final locales = _parseLocales(settings['available_locales']);
      final currentLocale = user['locale']?.toString();

      if (currentLocale != null &&
          currentLocale.isNotEmpty &&
          !locales.any((item) => item.value == currentLocale)) {
        locales.add(_LocaleOption(currentLocale, currentLocale));
      }

      if (!mounted) return;
      setState(() {
        _allowUserLocale = allowUserLocale;
        _locales = locales;
        _selectedLocale = currentLocale ??
            (locales.isNotEmpty ? locales.first.value : null);
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

  List<_LocaleOption> _parseLocales(dynamic raw) {
    dynamic decoded = raw;
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        decoded = jsonDecode(raw);
      } catch (_) {
        return const [];
      }
    }

    final result = <_LocaleOption>[];
    if (decoded is! List) return result;

    for (final entry in decoded) {
      if (entry is Map) {
        final value = entry['value']?.toString() ?? entry['id']?.toString();
        if (value == null || value.isEmpty) continue;
        final label = entry['native_name']?.toString() ??
            entry['label']?.toString() ??
            entry['name']?.toString() ??
            value;
        result.add(_LocaleOption(value, label));
      } else if (entry != null) {
        final value = entry.toString();
        if (value.isNotEmpty) result.add(_LocaleOption(value, value));
      }
    }

    return result;
  }

  Future<void> _save() async {
    final locale = _selectedLocale;
    if (!_allowUserLocale || locale == null || locale.isEmpty || _saving) {
      return;
    }

    setState(() => _saving = true);
    try {
      await ref
          .read(discourseServiceProvider)
          .updateUserPreferences(widget.username, {'locale': locale});
      await ref.read(currentUserProvider.notifier).refreshSilently(force: true);
      if (!mounted) return;
      ToastService.showSuccess(
        _tr('Discourse 界面语言已更新', 'Discourse language updated'),
      );
    } catch (e) {
      if (!mounted) return;
      ToastService.showError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_tr('Discourse 语言', 'Discourse language')),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 18),
              child: Center(
                child: SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            TextButton.icon(
              onPressed: _loading || !_allowUserLocale ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(_tr('保存', 'Save')),
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
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _tr('论坛界面语言', 'Forum interface language'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  _allowUserLocale
                      ? _tr(
                          '此设置直接修改 Discourse 账户的 locale，不会修改 Fluxdo 自身语言。',
                          'This changes your Discourse account locale and does not change the Fluxdo app language.',
                        )
                      : _tr(
                          '当前 Discourse 站点未允许用户自行修改界面语言。',
                          'This Discourse site does not allow users to change their locale.',
                        ),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 20),
                DropdownButtonFormField<String>(
                  value: _locales.any((item) => item.value == _selectedLocale)
                      ? _selectedLocale
                      : null,
                  decoration: InputDecoration(
                    labelText: _tr('语言', 'Language'),
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    for (final locale in _locales)
                      DropdownMenuItem(
                        value: locale.value,
                        child: Text('${locale.label} (${locale.value})'),
                      ),
                  ],
                  onChanged: _allowUserLocale
                      ? (value) => setState(() => _selectedLocale = value)
                      : null,
                ),
                if (_locales.isEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    _tr(
                      '站点没有返回可用语言列表，无法安全地提供语言选择。',
                      'The site did not return an available locale list.',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _LocaleOption {
  final String value;
  final String label;

  const _LocaleOption(this.value, this.label);
}
