import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/discourse_providers.dart';
import '../services/discourse/user_avatar_api.dart';
import '../services/discourse/user_preferences_api.dart';
import '../services/preloaded_data_service.dart';
import '../services/toast_service.dart';
import '../utils/url_helper.dart';

class DiscourseAvatarPage extends ConsumerStatefulWidget {
  final String username;

  const DiscourseAvatarPage({super.key, required this.username});

  @override
  ConsumerState<DiscourseAvatarPage> createState() => _DiscourseAvatarPageState();
}

class _DiscourseAvatarPageState extends ConsumerState<DiscourseAvatarPage> {
  Map<String, dynamic>? _user;
  Map<String, dynamic> _settings = const {};
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
        _settings = results[1] is Map
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

  bool get _avatarOverridden =>
      _settings['discourse_connect_overrides_avatar'] == true ||
      _settings['auth_overrides_avatar'] == true;

  bool get _canUseCustomSelector {
    final mode = _settings['selectable_avatars_mode']?.toString() ?? 'disabled';
    final trustLevel = (_user?['trust_level'] as num?)?.toInt() ?? 0;
    final staff = _user?['admin'] == true || _user?['moderator'] == true;
    if (mode == 'no_one') return false;
    if (mode == 'staff') return staff;
    final match = RegExp(r'^tl([1-4])$').firstMatch(mode);
    if (match != null) {
      final required = int.parse(match.group(1)!);
      return staff || trustLevel >= required;
    }
    return true;
  }

  List<String> get _selectableAvatars {
    final mode = _settings['selectable_avatars_mode']?.toString() ?? 'disabled';
    if (mode == 'disabled') return const [];
    final raw = _settings['selectable_avatars'];
    if (raw is List) {
      return raw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
    }
    if (raw is String && raw.isNotEmpty) {
      return raw.split('|').where((e) => e.isNotEmpty).toList();
    }
    return const [];
  }

  String _avatarUrl(dynamic template, {int size = 240}) {
    final raw = template?.toString() ?? '';
    if (raw.isEmpty) return '';
    return UrlHelper.resolveUrlWithCdn(raw.replaceAll('{size}', '$size'));
  }

  Future<void> _afterChanged(String message) async {
    await ref.read(currentUserProvider.notifier).refreshSilently(force: true);
    if (!mounted) return;
    ToastService.showSuccess(message);
    await _load();
  }

  Future<void> _pickAvatar(int? uploadId, String type) async {
    if (uploadId == null || _busy) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(discourseServiceProvider)
          .pickPreferenceAvatar(widget.username, uploadId: uploadId, type: type);
      await _afterChanged(_tr('头像已更新', 'Avatar updated'));
    } catch (e) {
      if (mounted) {
        ToastService.showError(e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _selectPreset(String url) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(discourseServiceProvider)
          .selectPreferenceAvatarUrl(widget.username, url);
      await _afterChanged(_tr('头像已更新', 'Avatar updated'));
    } catch (e) {
      if (mounted) {
        ToastService.showError(e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _uploadCustomAvatar() async {
    if (_busy || _user?['can_upload_avatar'] != true) return;
    final userId = (_user?['id'] as num?)?.toInt();
    if (userId == null) return;

    final selection = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: kIsWeb,
    );
    if (selection == null || selection.files.isEmpty) return;
    final picked = selection.files.single;

    setState(() => _busy = true);
    try {
      final service = ref.read(discourseServiceProvider);
      Map<String, dynamic> upload;
      if (picked.path != null && picked.path!.isNotEmpty) {
        upload = await service.uploadPreferenceAvatar(
          picked.path!,
          userId: userId,
        );
      } else if (picked.bytes != null) {
        upload = await service.uploadPreferenceAvatarBytes(
          picked.bytes!,
          fileName: picked.name,
          userId: userId,
        );
      } else {
        throw Exception(_tr('无法读取所选文件', 'Unable to read selected file'));
      }

      final uploadId = upload['id'];
      if (uploadId is! int) {
        throw Exception(_tr('上传结果缺少头像 ID', 'Avatar upload returned no ID'));
      }
      await service.pickPreferenceAvatar(
        widget.username,
        uploadId: uploadId,
        type: 'custom',
      );

      final width = upload['width'];
      final height = upload['height'];
      if (mounted && width is num && height is num && width != height) {
        ToastService.showInfo(
          _tr('头像已保存；建议使用正方形图片以获得最佳效果',
              'Avatar saved; a square image is recommended for best results'),
        );
      }
      await _afterChanged(_tr('自定义头像已更新', 'Custom avatar updated'));
    } catch (e) {
      if (mounted) {
        ToastService.showError(e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refreshGravatar() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final service = ref.read(discourseServiceProvider);
      final result = await service.refreshPreferenceGravatar(widget.username);
      final id = result['gravatar_upload_id'];
      if (id is! int) {
        throw Exception(_tr('没有找到可用的 Gravatar', 'No Gravatar was found'));
      }
      await service.pickPreferenceAvatar(
        widget.username,
        uploadId: id,
        type: 'gravatar',
      );
      await _afterChanged(_tr('Gravatar 已更新', 'Gravatar updated'));
    } catch (e) {
      if (mounted) {
        ToastService.showError(e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_tr('头像', 'Avatar')),
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

    if (_avatarOverridden) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _tr(
              '当前站点由外部认证系统管理头像，因此不能在 Discourse 中修改。',
              'This site manages avatars through an external authentication provider.',
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final current = _avatarUrl(_user?['avatar_template']);
    final system = _avatarUrl(_user?['system_avatar_template']);
    final custom = _avatarUrl(_user?['custom_avatar_template']);
    final gravatar = _avatarUrl(_user?['gravatar_avatar_template']);
    final presets = _selectableAvatars;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        Center(
          child: CircleAvatar(
            radius: 54,
            foregroundImage: current.isEmpty ? null : NetworkImage(current),
            child: current.isEmpty ? const Icon(Icons.person, size: 50) : null,
          ),
        ),
        const SizedBox(height: 8),
        Center(child: Text(_tr('当前头像', 'Current avatar'))),
        const SizedBox(height: 20),
        if (presets.isNotEmpty)
          _section(
            _tr('站点预设头像', 'Site avatars'),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final preset in presets)
                  InkWell(
                    borderRadius: BorderRadius.circular(40),
                    onTap: _busy ? null : () => _selectPreset(preset),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: CircleAvatar(
                        radius: 32,
                        foregroundImage: NetworkImage(_avatarUrl(preset, size: 120)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        if (_canUseCustomSelector)
          _section(
            _tr('头像来源', 'Avatar source'),
            Column(
              children: [
                _avatarChoice(
                  icon: Icons.text_fields,
                  title: _tr('系统字母头像', 'System letter avatar'),
                  imageUrl: system,
                  onTap: () => _pickAvatar(
                    (_user?['system_avatar_upload_id'] as num?)?.toInt(),
                    'system',
                  ),
                ),
                const Divider(height: 1),
                _avatarChoice(
                  icon: Icons.upload_outlined,
                  title: _tr('自定义上传头像', 'Custom uploaded avatar'),
                  imageUrl: custom,
                  onTap: _user?['can_upload_avatar'] == true
                      ? _uploadCustomAvatar
                      : null,
                  trailingLabel: _tr('上传', 'Upload'),
                ),
                if (_settings['gravatar_enabled'] == true) ...[
                  const Divider(height: 1),
                  _avatarChoice(
                    icon: Icons.public,
                    title: 'Gravatar',
                    imageUrl: gravatar,
                    onTap: _refreshGravatar,
                    trailingLabel: _tr('刷新并使用', 'Refresh & use'),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _section(String title, Widget child) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: child,
              ),
            ),
          ],
        ),
      );

  Widget _avatarChoice({
    required IconData icon,
    required String title,
    required String imageUrl,
    required VoidCallback? onTap,
    String? trailingLabel,
  }) => ListTile(
        leading: imageUrl.isEmpty
            ? CircleAvatar(child: Icon(icon))
            : CircleAvatar(foregroundImage: NetworkImage(imageUrl)),
        title: Text(title),
        trailing: trailingLabel == null
            ? const Icon(Icons.chevron_right)
            : TextButton(
                onPressed: _busy ? null : onTap,
                child: Text(trailingLabel),
              ),
        onTap: _busy ? null : onTap,
      );
}
