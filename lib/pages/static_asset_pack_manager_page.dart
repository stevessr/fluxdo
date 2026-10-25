import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/assets/static_asset_packs.dart';

/// 管理手动从可信发行渠道取得的可选静态资源包。
///
/// 安装时强制用户另外提供可信的 ZIP SHA-256；绝不信任 ZIP 内的
/// manifest、下载链接或文件名来决定待执行的 JS 是否可信。
class StaticAssetPackManagerPage extends StatefulWidget {
  const StaticAssetPackManagerPage({super.key});

  @override
  State<StaticAssetPackManagerPage> createState() =>
      _StaticAssetPackManagerPageState();
}

class _StaticAssetPackManagerPageState
    extends State<StaticAssetPackManagerPage> {
  static const _labels = <String, String>{
    'font-misans': 'MiSans 字体',
    'render-cook': 'Discourse Cook 脚本',
    'render-polyfill': 'WebView 兼容脚本',
    'ai-brands': 'AI 品牌图标',
    'avatar-touhou': '东方角色素材',
    'avatar-blue-archive': '蔚蓝档案角色素材',
    'avatar-witch-judgment': '魔法少女审判角色素材',
    'avatar-llm': 'LLM 角色差分素材',
    'avatar-stevessr': 'Stevessr 角色差分素材',
  };
  static final _digest = RegExp(r'^[a-f0-9]{64}$');
  static const _maximumZipBytes = 128 * 1024 * 1024;

  StreamSubscription<String>? _subscription;
  Map<String, String> _installed = const {};
  bool _busy = false;
  String? _error;

  bool get _zh => Localizations.localeOf(context).languageCode == 'zh';
  String _tr(String chinese, String english) => _zh ? chinese : english;

  @override
  void initState() {
    super.initState();
    _subscription = StaticAssetPacks.changes.listen((_) => _refresh());
    _refresh();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final installed = await StaticAssetPacks.listInstalled();
      if (!mounted) return;
      setState(() {
        _installed = {for (final item in installed) item['id']!: item['digest']!};
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      await _refresh();
    } catch (error) {
      _message(_tr('操作失败：$error', 'Operation failed: $error'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _requestDigest(String packName) async {
    final controller = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(_tr('安装 $packName', 'Install $packName')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_tr(
                '先从可信发行页面独立复制 ZIP 文件的完整 SHA-256，再选择对应 ZIP。'
                '应用只校验一致性，不会仅凭 ZIP 自己提供的清单判断发布者身份。',
                'Copy the complete ZIP SHA-256 independently from a trusted '
                'release page before selecting the ZIP. The ZIP manifest '
                'cannot authenticate its publisher.',
              )),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                maxLength: 64,
                decoration: InputDecoration(
                  labelText: 'SHA-256',
                  border: const OutlineInputBorder(),
                  hintText: _tr('完整 64 位小写十六进制', '64 lowercase hex digits'),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(_tr('取消', 'Cancel')),
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (_, value, _) => FilledButton(
                onPressed: _digest.hasMatch(value.text.trim().toLowerCase())
                    ? () => Navigator.pop(
                        dialogContext, value.text.trim().toLowerCase(),
                      )
                    : null,
                child: Text(_tr('选择 ZIP', 'Choose ZIP')),
              ),
            ),
          ],
        ),
      );
    } finally {
      // 等对话框退出后再释放其 TextField 持有的控制器。
      WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    }
  }

  Future<void> _install(String id) async {
    if (kIsWeb) {
      _message(_tr('Web 暂不支持本地包', 'Local packs are not supported on Web'));
      return;
    }
    final digest = await _requestDigest(_labels[id]!);
    if (digest == null || !mounted) return;
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
      withData: true,
    );
    if (picked == null || !mounted) return;
    final file = picked.files.single;
    if (file.size > _maximumZipBytes) {
      _message(_tr('资源包超过 128 MiB 的导入上限', 'Pack exceeds 128 MiB import limit'));
      return;
    }
    final bytes = file.bytes;
    if (bytes == null) {
      _message(_tr('无法读取所选 ZIP', 'Unable to read selected ZIP'));
      return;
    }
    await _run(() async {
      await StaticAssetPacks.installTrustedZip(
        packId: id,
        zipBytes: bytes,
        expectedSha256: digest,
      );
      _message(_tr('安装并启用成功', 'Pack installed and enabled'));
    });
  }

  Future<void> _disable(String id) => _run(() async {
    final disabled = await StaticAssetPacks.disable(id);
    _message(disabled
        ? _tr('已禁用；回退到内置资源', 'Disabled; using bundled assets')
        : _tr('当前没有已启用的包', 'No enabled pack'));
  });

  Future<void> _rollback(String id) => _run(() async {
    final rolledBack = await StaticAssetPacks.rollback(id);
    _message(rolledBack
        ? _tr('已回滚到上一状态', 'Restored previous state')
        : _tr('无可用历史版本', 'No previous version available'));
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_tr('静态资源包', 'Static resource packs')),
        actions: [
          IconButton(
            tooltip: _tr('刷新', 'Refresh'),
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            _tr(
              '各资源包可独立更新。仅导入从可信发布渠道获得的 ZIP 和 SHA-256；'
              '没有外置包时继续使用 Core 内置资源。',
              'Each pack updates independently. Import ZIP and SHA-256 '
              'from a trusted release source. Bundled assets are the fallback.',
            ),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: TextStyle(color: color.error)),
            ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _busy || kIsWeb
                  ? null
                  : () => _run(() async {
                      final bytes = await StaticAssetPacks.pruneUnused();
                      _message(_tr(
                        '已安全回收 $bytes 字节旧资源',
                        'Reclaimed $bytes bytes of obsolete resources',
                      ));
                    }),
              icon: const Icon(Icons.cleaning_services_outlined),
              label: Text(_tr('清理无用历史版本', 'Clean obsolete versions')),
            ),
          ),
          const SizedBox(height: 16),
          for (final entry in _labels.entries)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.value,
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      _installed.containsKey(entry.key)
                          ? _tr('已启用外置版本', 'External pack active')
                          : _tr('使用内置资源或未安装', 'Bundled / not installed'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (_installed[entry.key] case final String digest)
                      SelectableText(
                        digest,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: _busy || kIsWeb
                              ? null
                              : () => _install(entry.key),
                          child: Text(_tr('导入 / 更新', 'Import / update')),
                        ),
                        TextButton(
                          onPressed: _busy || !_installed.containsKey(entry.key)
                              ? null
                              : () => _disable(entry.key),
                          child: Text(_tr('禁用', 'Disable')),
                        ),
                        TextButton(
                          onPressed: _busy ? null : () => _rollback(entry.key),
                          child: Text(_tr('回滚', 'Rollback')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          Text(
            _tr(
              '说明：外置字体加载后可能需要重启以应用新版本；已打开的 '
              'WebView 不会自动重注入脚本。此页不从互联网自动下载可执行 JS。',
              'Some font changes require a restart. Open WebViews do not '
              'reinject scripts. This page never downloads executable JS.',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
