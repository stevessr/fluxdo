import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/discourse_providers.dart';
import '../services/discourse/user_preferences_api.dart';
import '../services/discourse/user_security_extras_api.dart';
import '../services/preloaded_data_service.dart';
import '../services/toast_service.dart';

class DiscoursePasskeysManagementPage extends ConsumerStatefulWidget {
  final String username;

  const DiscoursePasskeysManagementPage({
    super.key,
    required this.username,
  });

  @override
  ConsumerState<DiscoursePasskeysManagementPage> createState() =>
      _DiscoursePasskeysManagementPageState();
}

class _DiscoursePasskeysManagementPageState
    extends ConsumerState<DiscoursePasskeysManagementPage> {
  Map<String, dynamic>? _user;
  Map<String, dynamic>? _secondFactors;
  Map<String, dynamic> _settings = const {};
  bool _loading = true;
  bool _busy = false;
  bool _isCurrentUser = false;
  Object? _error;

  bool get _isZh => Localizations.localeOf(context).languageCode == 'zh';
  String _tr(String zh, String en) => _isZh ? zh : en;

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<Map<String, dynamic>> get _passkeys {
    final raw = _user?['user_passkeys'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  List<Map<String, dynamic>> get _securityKeys {
    final raw = _secondFactors?['security_keys'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final service = ref.read(discourseServiceProvider);
      final results = await Future.wait<dynamic>([
        service.getUserPreferences(widget.username),
        PreloadedDataService().getSiteSettings(),
        service.getCurrentUsername(),
      ]);

      Map<String, dynamic>? factors;
      try {
        final trusted = await service.getTrustedSession();
        if (trusted['success'] == true) {
          factors = await service.loadPreferenceSecondFactors();
        }
      } catch (_) {
        // Discourse deliberately hides detailed 2FA credentials until the
        // session has been confirmed. The page can still manage Passkeys.
      }

      if (!mounted) return;
      final currentUsername = results[2]?.toString();
      setState(() {
        _user = Map<String, dynamic>.from(results[0] as Map);
        _settings = results[1] is Map
            ? Map<String, dynamic>.from(results[1] as Map)
            : <String, dynamic>{};
        _secondFactors = factors;
        _isCurrentUser = currentUsername != null &&
            currentUsername.toLowerCase() == widget.username.toLowerCase();
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

  Future<bool> _trusted(String action) async {
    try {
      final result = await ref.read(discourseServiceProvider).getTrustedSession();
      if (result['success'] == true) return true;
      if (mounted) {
        ToastService.showError(
          _tr(
            '$action 前 Discourse 要求先完成“确认访问”。请在近期重新登录后再试。',
            'Discourse requires a trusted session before $action. Sign in again recently and retry.',
          ),
        );
      }
      return false;
    } catch (e) {
      if (mounted) {
        ToastService.showError(e.toString().replaceFirst('Exception: ', ''));
      }
      return false;
    }
  }

  Future<String?> _askName(String title, String initial) async {
    final controller = TextEditingController(text: initial);
    try {
      return await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: _tr('名称', 'Name'),
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (text) => Navigator.pop(dialogContext, text.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
              child: Text(_tr('保存', 'Save')),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<bool> _confirmDelete(String title, String message) async =>
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
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(_tr('删除', 'Delete')),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _renamePasskey(Map<String, dynamic> passkey) async {
    if (_busy || !_isCurrentUser) return;
    final id = passkey['id'];
    if (id is! int) return;
    final value = await _askName(
      _tr('重命名 Passkey', 'Rename Passkey'),
      passkey['name']?.toString() ?? '',
    );
    if (value == null || value.isEmpty || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(discourseServiceProvider).renamePreferencePasskey(id, value);
      if (!mounted) return;
      ToastService.showSuccess(_tr('Passkey 已重命名', 'Passkey renamed'));
      await _load();
    } catch (e) {
      if (mounted) {
        ToastService.showError(e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deletePasskey(Map<String, dynamic> passkey) async {
    if (_busy || !_isCurrentUser) return;
    final id = passkey['id'];
    if (id is! int) return;
    if (!await _trusted(_tr('删除 Passkey', 'deleting a Passkey')) || !mounted) {
      return;
    }

    final name = passkey['name']?.toString() ?? 'Passkey';
    final confirmed = await _confirmDelete(
      _tr('删除 Passkey？', 'Delete Passkey?'),
      _tr(
        '将删除“$name”。如果它是账户最后一个可用的第一因素 Passkey，Discourse 会按服务器规则拒绝删除以避免账户被锁定。',
        'This will delete “$name”. If it is the final usable first-factor Passkey, Discourse will reject the operation according to its lockout-protection rules.',
      ),
    );
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(discourseServiceProvider).deletePreferencePasskey(id);
      await ref.read(currentUserProvider.notifier).refreshSilently(force: true);
      if (!mounted) return;
      ToastService.showSuccess(_tr('Passkey 已删除', 'Passkey deleted'));
      await _load();
    } catch (e) {
      if (mounted) {
        ToastService.showError(e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _renameSecurityKey(Map<String, dynamic> key) async {
    if (_busy || !_isCurrentUser) return;
    final id = key['id'];
    if (id is! int) return;
    if (!await _trusted(_tr('重命名安全密钥', 'renaming a security key')) ||
        !mounted) {
      return;
    }
    final oldName = key['name']?.toString() ?? '';
    final value = await _askName(
      _tr('重命名安全密钥', 'Rename security key'),
      oldName,
    );
    if (value == null || value.isEmpty || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(discourseServiceProvider).updatePreferenceSecondFactor(
            id: id,
            name: value,
            disable: false,
            targetMethod: 3,
          );
      if (!mounted) return;
      ToastService.showSuccess(_tr('安全密钥已重命名', 'Security key renamed'));
      await _load();
    } catch (e) {
      if (mounted) {
        ToastService.showError(e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteSecurityKey(Map<String, dynamic> key) async {
    if (_busy || !_isCurrentUser) return;
    final id = key['id'];
    if (id is! int) return;
    if (!await _trusted(_tr('删除安全密钥', 'deleting a security key')) ||
        !mounted) {
      return;
    }
    final name = key['name']?.toString() ?? _tr('安全密钥', 'Security key');
    final confirmed = await _confirmDelete(
      _tr('删除安全密钥？', 'Delete security key?'),
      _tr(
        '将停用二因素安全密钥“$name”。',
        'This will disable the two-factor security key “$name”.',
      ),
    );
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(discourseServiceProvider).updatePreferenceSecondFactor(
            id: id,
            name: name,
            disable: true,
            targetMethod: 3,
          );
      await ref.read(currentUserProvider.notifier).refreshSilently(force: true);
      if (!mounted) return;
      ToastService.showSuccess(_tr('安全密钥已删除', 'Security key deleted'));
      await _load();
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
        title: Text(_tr('已有安全凭据', 'Existing credentials')),
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
        child: FilledButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh),
          label: Text(_tr('重试', 'Retry')),
        ),
      );
    }

    final passkeys = _passkeys;
    final securityKeys = _securityKeys;
    final passkeysEnabled = _settings['enable_passkeys'] == true;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              _tr(
                '这里管理已经存在于 Discourse 账户中的 WebAuthn 凭据。Passkey 是第一因素；Security Key 是二因素。重命名与删除都使用当前 Discourse 官方接口，Fluxdo 不在此恢复 WebAuthn 创建实验。',
                'This page manages WebAuthn credentials already registered with Discourse. Passkeys are first-factor credentials; Security Keys are second-factor credentials. Rename/delete use current official Discourse endpoints; Fluxdo does not reintroduce WebAuthn creation here.',
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        _sectionTitle(_tr('Passkey（一因素）', 'Passkeys (first factor)')),
        if (!passkeysEnabled)
          _infoTile(_tr('站点当前未启用 Passkey', 'Passkeys are disabled on this site'))
        else if (passkeys.isEmpty)
          _infoTile(_tr('没有已注册 Passkey', 'No registered Passkeys'))
        else
          for (final passkey in passkeys) ...[
            _passkeyCard(passkey),
            const SizedBox(height: 12),
          ],
        const SizedBox(height: 20),
        _sectionTitle(_tr('Security Key（二因素）', 'Security keys (second factor)')),
        if (_secondFactors == null)
          _infoTile(
            _tr(
              '需要先完成 Discourse“确认访问”才能读取二因素安全密钥详情。',
              'Confirm access in Discourse before two-factor security-key details can be read.',
            ),
          )
        else if (securityKeys.isEmpty)
          _infoTile(_tr('没有已注册安全密钥', 'No registered security keys'))
        else
          for (final key in securityKeys) ...[
            _securityKeyCard(key),
            const SizedBox(height: 12),
          ],
      ],
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
        child: Text(
          text,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
        ),
      );

  Widget _infoTile(String text) => Card(
        child: ListTile(
          leading: const Icon(Icons.info_outline),
          title: Text(text),
        ),
      );

  Widget _passkeyCard(Map<String, dynamic> passkey) {
    final name = passkey['name']?.toString() ?? 'Passkey';
    final created = _formatDate(passkey['created_at']);
    final lastUsed = _formatDate(passkey['last_used']);
    return Card(
      child: ListTile(
        leading: const Icon(Icons.key_outlined),
        title: Text(name),
        subtitle: Text(
          [
            if (created != null) _tr('添加：$created', 'Added: $created'),
            lastUsed == null
                ? _tr('从未使用', 'Never used')
                : _tr('最近使用：$lastUsed', 'Last used: $lastUsed'),
          ].join('\n'),
        ),
        isThreeLine: created != null,
        trailing: !_isCurrentUser
            ? null
            : PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'rename') _renamePasskey(passkey);
                  if (value == 'delete') _deletePasskey(passkey);
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'rename',
                    child: Text(_tr('重命名', 'Rename')),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(_tr('删除', 'Delete')),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _securityKeyCard(Map<String, dynamic> key) {
    final name = key['name']?.toString() ?? _tr('安全密钥', 'Security key');
    final created = _formatDate(key['created_at']);
    final lastUsed = _formatDate(key['last_used'] ?? key['last_used_at']);
    return Card(
      child: ListTile(
        leading: const Icon(Icons.usb_outlined),
        title: Text(name),
        subtitle: Text(
          [
            if (created != null) _tr('添加：$created', 'Added: $created'),
            if (lastUsed != null) _tr('最近使用：$lastUsed', 'Last used: $lastUsed'),
          ].isEmpty
              ? _tr('二因素 WebAuthn 安全密钥', 'Two-factor WebAuthn security key')
              : [
                  if (created != null) _tr('添加：$created', 'Added: $created'),
                  if (lastUsed != null) _tr('最近使用：$lastUsed', 'Last used: $lastUsed'),
                ].join('\n'),
        ),
        trailing: !_isCurrentUser
            ? null
            : PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'rename') _renameSecurityKey(key);
                  if (value == 'delete') _deleteSecurityKey(key);
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'rename',
                    child: Text(_tr('重命名', 'Rename')),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(_tr('删除', 'Delete')),
                  ),
                ],
              ),
      ),
    );
  }

  String? _formatDate(dynamic value) {
    if (value == null) return null;
    final date = DateTime.tryParse(value.toString())?.toLocal();
    if (date == null) return value.toString();
    return MaterialLocalizations.of(context).formatMediumDate(date);
  }
}
