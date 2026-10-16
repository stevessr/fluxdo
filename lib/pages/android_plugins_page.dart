import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/core_providers.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/android_optional_plugin_service.dart';
import '../services/android_sticker_companion_service.dart';
import '../services/stevessr_export_service.dart';

/// Displays separately installed Android companion APKs. Deliberately does not
/// install unsigned/untrusted APKs automatically.
class AndroidPluginsPage extends ConsumerStatefulWidget {
  const AndroidPluginsPage({super.key});

  @override
  ConsumerState<AndroidPluginsPage> createState() => _AndroidPluginsPageState();
}

class _AndroidPluginsPageState extends ConsumerState<AndroidPluginsPage>
    with WidgetsBindingObserver {
  late Future<List<AndroidOptionalPlugin>> _plugins = _load();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) _refresh();
  }

  bool get _zh => Localizations.localeOf(context).languageCode == 'zh';
  String _t(String cn, String en) => _zh ? cn : en;

  String _reasonText(String reason) => switch (reason) {
    'ready' => _t('可使用', 'Ready'),
    'not_installed' => _t('未安装', 'Not installed'),
    'signature_mismatch' => _t('签名不匹配', 'Signature mismatch'),
    'incompatible_protocol' => _t('协议版本不兼容', 'Incompatible protocol'),
    'unprotected_service' => _t('缺少受保护的服务', 'Unprotected service'),
    'missing_activity' => _t('启动入口不可用', 'Missing activity'),
    _ => reason,
  };

  Future<List<AndroidOptionalPlugin>> _load() =>
      AndroidOptionalPluginService.instance.list();

  void _refresh() {
    setState(() => _plugins = _load());
  }

  Future<void> _run(AndroidOptionalPlugin plugin, String operation,
      [Map<String, dynamic> arguments = const {}]) async {
    try {
      final response = await AndroidOptionalPluginService.instance
          .invoke(plugin.id, operation, arguments);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(operation),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: SelectableText(
                const JsonEncoder.withIndent('  ').convert(response),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(_t('关闭', 'Close')),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _lookup(AndroidOptionalPlugin plugin) async {
    final controller = TextEditingController(text: 'linux.do');
    final hostname = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_t('DNS 查询', 'DNS lookup')),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'example.com'),
          keyboardType: TextInputType.url,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(_t('取消', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(_t('查询', 'Lookup')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (hostname == null || hostname.isEmpty || !mounted) return;
    await _run(plugin, 'network.lookup', {'hostname': hostname});
  }

  Future<void> _openReleases() async {
    try {
      final opened = await launchUrl(
        Uri.parse('https://github.com/stevessr/fluxdo/releases'),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) throw StateError('Unable to open GitHub Releases');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_t('Android 插件 APK', 'Android Plugin APKs')),
        actions: [
          IconButton(
            tooltip: _t('刷新已安装插件', 'Refresh installed plugins'),
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FutureBuilder<List<AndroidOptionalPlugin>>(
        future: _plugins,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text(snapshot.error.toString()));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final plugins = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                _t(
                  '可选功能使用独立 APK 安装和升级，不会替换主程序。'
                  '插件必须与 FluxDO 使用相同签名，并兼容当前协议。'
                  '发布签名版本后，可在 GitHub Releases 获取对应 APK。',
                  'Optional modules can be installed and updated independently. '
                  'Each APK must match the main app signer and protocol version. '
                  'After signed releases are published, install plugin APKs from GitHub Releases.',
                ),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _openReleases,
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: Text(_t('查看发布页', 'Open releases')),
                ),
              ),
              const SizedBox(height: 12),
              for (final plugin in plugins)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      children: [
                        ListTile(
                          leading: Icon(
                            plugin.compatible
                                ? Icons.extension_rounded
                                : Icons.extension_off_rounded,
                          ),
                          title: Text(switch (plugin.id) {
                            'deviceinfo' => _t('设备诊断', 'Device diagnostics'),
                            'network' => _t('网络诊断', 'Network diagnostics'),
                            'cdk' => 'CDK',
                            'ldc' => 'LDC',
                            'ldc_reward' => _t('LDC 打赏', 'LDC reward'),
                            'sticker' => _t('表情包生成器', 'Sticker generator'),
                            _ => plugin.name,
                          }),
                          subtitle: Text(
                            '${plugin.packageName}\n'
                            '${plugin.version ?? "-"} · ${_reasonText(plugin.reason)}',
                          ),
                          isThreeLine: true,
                          trailing: Icon(
                            plugin.compatible
                                ? Icons.check_circle_outline
                                : Icons.info_outline,
                          ),
                        ),
                        if (plugin.compatible)
                          Padding(
                            padding: const EdgeInsets.only(
                                left: 16, right: 16, bottom: 8),
                            child: Wrap(
                              spacing: 8,
                              children: [
                                if (plugin.id != 'sticker')
                                  FilledButton.tonal(
                                    onPressed: () => _run(
                                      plugin,
                                      switch (plugin.id) {
                                        'deviceinfo' => 'device.snapshot',
                                        'network' => 'network.state',
                                        'ldc_reward' => 'reward.capabilities',
                                      _ => 'metaverse.capabilities',
                                      },
                                    ),
                                    child: Text(_t('查询插件能力', 'Query capabilities')),
                                  ),
                                if (plugin.id == 'sticker')
                                  FilledButton.tonal(
                                    onPressed: () async {
                                      try {
                                        final image = await
                                            AndroidStickerCompanionService.generate();
                                        if (image != null) {
                                          await StevessrExportService.save(image);
                                        }
                                      } catch (error) {
                                        if (!mounted) return;
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text(error.toString())),
                                        );
                                      }
                                    },
                                    child: Text(_t('打开生成器', 'Open generator')),
                                  ),
                                if (plugin.id == 'network')
                                  OutlinedButton(
                                    onPressed: () => _lookup(plugin),
                                    child: Text(_t('DNS 查询', 'DNS lookup')),
                                  ),
                                if (plugin.id == 'cdk' || plugin.id == 'ldc' || plugin.id == 'ldc_reward')
                                  OutlinedButton.icon(
                                    onPressed: plugin.id == 'ldc_reward'
                                        ? null
                                        : () async {
                                      try {
                                        await AndroidOptionalPluginService.instance.launch(
                                          plugin.id,
                                          payload: {
                                            'accountSlot': AndroidOptionalPluginService.sessionSlotForUsername(
                                              ref.read(currentUserProvider).value?.username,
                                            ),
                                          },
                                        );
                                      } catch (error) {
                                        if (!mounted) return;
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text(error.toString())),
                                        );
                                      }
                                    },
                                    icon: const Icon(Icons.open_in_new),
                                    label: Text(plugin.id == 'ldc_reward'
                                        ? _t('请从帖子发起', 'Open from a post')
                                        : _t('打开独立插件', 'Open companion')),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
