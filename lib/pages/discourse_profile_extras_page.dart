import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/discourse_providers.dart';
import '../services/discourse/user_preferences_api.dart';
import '../services/discourse/user_profile_extras_api.dart';
import '../services/preloaded_data_service.dart';
import '../services/toast_service.dart';
import '../utils/url_helper.dart';

/// Native counterpart of the remaining media/topic controls in Discourse's
/// preferences/profile page.
class DiscourseProfileExtrasPage extends ConsumerStatefulWidget {
  final String username;

  const DiscourseProfileExtrasPage({super.key, required this.username});

  @override
  ConsumerState<DiscourseProfileExtrasPage> createState() =>
      _DiscourseProfileExtrasPageState();
}

class _DiscourseProfileExtrasPageState
    extends ConsumerState<DiscourseProfileExtrasPage> {
  Map<String, dynamic>? _user;
  Map<String, dynamic> _siteSettings = const {};
  bool _loading = true;
  bool _busy = false;
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
      final results = await Future.wait<dynamic>([
        ref.read(discourseServiceProvider).getUserPreferences(widget.username),
        PreloadedDataService().getSiteSettings(),
      ]);
      if (!mounted) return;
      setState(() {
        _user = Map<String, dynamic>.from(results[0] as Map);
        _siteSettings = results[1] is Map
            ? Map<String, dynamic>.from(results[1] as Map)
            : <String, dynamic>{};
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

  bool _capability(String key) => _user?[key] == true;

  Future<void> _pickAndUpload({
    required String field,
    required String uploadType,
  }) async {
    if (_busy) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: kIsWeb,
    );
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.single;

    setState(() => _busy = true);
    try {
      final service = ref.read(discourseServiceProvider);
      Map<String, dynamic> upload;
      if (picked.path != null && picked.path!.isNotEmpty) {
        upload = await service.uploadUserProfileImage(
          picked.path!,
          uploadType: uploadType,
        );
      } else if (picked.bytes != null) {
        upload = await service.uploadUserProfileImageBytes(
          picked.bytes!,
          fileName: picked.name,
          uploadType: uploadType,
        );
      } else {
        throw Exception(_tr('无法读取所选文件', 'Unable to read the selected file'));
      }

      final url = upload['url']?.toString();
      if (url == null || url.isEmpty) {
        throw Exception(_tr('上传成功但没有返回 URL', 'Upload returned no URL'));
      }
      await service.updateUserPreferences(widget.username, {field: url});
      await ref.read(currentUserProvider.notifier).refreshSilently(force: true);
      if (!mounted) return;
      ToastService.showSuccess(_tr('背景图已更新', 'Background image updated'));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ToastService.showError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearImage(String field) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(discourseServiceProvider)
          .updateUserPreferences(widget.username, {field: null});
      await ref.read(currentUserProvider.notifier).refreshSilently(force: true);
      if (!mounted) return;
      ToastService.showSuccess(_tr('背景图已移除', 'Background image removed'));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ToastService.showError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _chooseFeaturedTopic() async {
    final selected = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _FeaturedTopicSearchDialog(
        username: widget.username,
        zh: _isZh,
      ),
    );
    if (selected == null || !mounted || _busy) return;
    final id = selected['id'];
    if (id is! int) return;

    setState(() => _busy = true);
    try {
      await ref
          .read(discourseServiceProvider)
          .setFeaturedProfileTopic(widget.username, id);
      await ref.read(currentUserProvider.notifier).refreshSilently(force: true);
      if (!mounted) return;
      ToastService.showSuccess(_tr('精选话题已更新', 'Featured topic updated'));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ToastService.showError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearFeaturedTopic() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(discourseServiceProvider)
          .clearFeaturedProfileTopic(widget.username);
      await ref.read(currentUserProvider.notifier).refreshSilently(force: true);
      if (!mounted) return;
      ToastService.showSuccess(_tr('精选话题已清除', 'Featured topic cleared'));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ToastService.showError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_tr('个人资料扩展', 'Profile extras')),
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

    final allowBackgrounds = _siteSettings['allow_profile_backgrounds'] == true;
    final allowFeatured =
        _siteSettings['allow_featured_topic_on_user_profiles'] == true;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        if (allowBackgrounds) ...[
          if (_capability('can_upload_profile_header'))
            _imageSection(
              title: _tr('个人资料背景图', 'Profile background'),
              field: 'profile_background_upload_url',
              uploadType: 'profile_background',
            ),
          if (_capability('can_upload_user_card_background'))
            _imageSection(
              title: _tr('用户卡片背景图', 'User card background'),
              field: 'card_background_upload_url',
              uploadType: 'card_background',
            ),
        ],
        if (allowFeatured) _featuredTopicSection(),
        if (!allowBackgrounds && !allowFeatured)
          Card(
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(
                _tr(
                  '当前站点没有开放这些个人资料扩展功能',
                  'This site has not enabled these profile extras',
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _imageSection({
    required String title,
    required String field,
    required String uploadType,
  }) {
    final raw = _user?[field]?.toString() ?? '';
    final resolved = raw.isEmpty ? null : UrlHelper.resolveUrlWithCdn(raw);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(title, style: Theme.of(context).textTheme.titleMedium),
            ),
            if (resolved != null)
              AspectRatio(
                aspectRatio: 3,
                child: Image.network(
                  resolved,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Center(
                    child: Icon(Icons.broken_image_outlined, size: 36),
                  ),
                ),
              )
            else
              const SizedBox(
                height: 120,
                child: Center(child: Icon(Icons.image_outlined, size: 42)),
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: _busy
                        ? null
                        : () => _pickAndUpload(
                              field: field,
                              uploadType: uploadType,
                            ),
                    icon: const Icon(Icons.upload_outlined),
                    label: Text(
                      raw.isEmpty ? _tr('选择图片', 'Choose image') : _tr('更换', 'Change'),
                    ),
                  ),
                  if (raw.isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () => _clearImage(field),
                      icon: const Icon(Icons.delete_outline),
                      label: Text(_tr('移除', 'Remove')),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _featuredTopicSection() {
    final featured = _user?['featured_topic'];
    final topic = featured is Map
        ? Map<String, dynamic>.from(featured)
        : <String, dynamic>{};
    final id = topic['id'];
    final title = topic['fancy_title']?.toString() ??
        topic['title']?.toString() ??
        (id == null ? '' : '#$id');

    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.push_pin_outlined),
            title: Text(_tr('个人资料精选话题', 'Featured profile topic')),
            subtitle: Text(
              title.isEmpty
                  ? _tr('尚未设置', 'Not set')
                  : title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _busy ? null : _chooseFeaturedTopic,
                    icon: const Icon(Icons.search),
                    label: Text(
                      title.isEmpty ? _tr('选择话题', 'Choose topic') : _tr('更换话题', 'Change topic'),
                    ),
                  ),
                ),
                if (title.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  IconButton.outlined(
                    tooltip: _tr('清除', 'Clear'),
                    onPressed: _busy ? null : _clearFeaturedTopic,
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FeaturedTopicSearchDialog extends ConsumerStatefulWidget {
  final String username;
  final bool zh;

  const _FeaturedTopicSearchDialog({
    required this.username,
    required this.zh,
  });

  @override
  ConsumerState<_FeaturedTopicSearchDialog> createState() =>
      _FeaturedTopicSearchDialogState();
}

class _FeaturedTopicSearchDialogState
    extends ConsumerState<_FeaturedTopicSearchDialog> {
  final TextEditingController _controller = TextEditingController();
  List<Map<String, dynamic>> _topics = const [];
  bool _searching = false;
  Object? _error;

  String _tr(String zh, String en) => widget.zh ? zh : en;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.isEmpty || _searching) return;
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final topics = await ref
          .read(discourseServiceProvider)
          .searchPublicTopicsForProfile(query);
      if (!mounted) return;
      setState(() => _topics = topics);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_tr('选择精选话题', 'Choose featured topic')),
      content: SizedBox(
        width: 520,
        height: 430,
        child: Column(
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                labelText: _tr('搜索公开话题', 'Search public topics'),
                suffixIcon: IconButton(
                  onPressed: _searching ? null : _search,
                  icon: const Icon(Icons.search),
                ),
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _search(),
            ),
            const SizedBox(height: 12),
            if (_searching) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  _error.toString(),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Expanded(
              child: _topics.isEmpty
                  ? Center(
                      child: Text(
                        _tr(
                          '输入关键词后搜索；仅返回公开话题。',
                          'Search by keyword; only public topics are returned.',
                        ),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.builder(
                      itemCount: _topics.length,
                      itemBuilder: (context, index) {
                        final topic = _topics[index];
                        final id = topic['id'];
                        final title = topic['fancy_title']?.toString() ??
                            topic['title']?.toString() ??
                            '#$id';
                        return ListTile(
                          leading: const Icon(Icons.forum_outlined),
                          title: Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: id == null ? null : Text('#$id'),
                          onTap: () => Navigator.pop(context, topic),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
      ],
    );
  }
}
