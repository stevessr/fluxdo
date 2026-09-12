import 'package:flutter/material.dart';

import '../config/discourse_instance_runtime.dart';
import '../services/discourse_instance_manager.dart';

class DiscourseInstancesPage extends StatefulWidget {
  const DiscourseInstancesPage({super.key});

  @override
  State<DiscourseInstancesPage> createState() => _DiscourseInstancesPageState();
}

class _DiscourseInstancesPageState extends State<DiscourseInstancesPage> {
  final _manager = DiscourseInstanceManager.instance;
  bool _loading = true;
  bool _enabled = false;
  List<DiscourseInstanceProfile> _instances = const [];
  DiscourseInstanceProfile _selected = DiscourseInstanceProfile.linuxDo;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final enabled = await _manager.isEnabled();
    final instances = await _manager.listInstances();
    final selected = await _manager.selectedInstance();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _instances = instances;
      _selected = selected;
      _loading = false;
    });
  }

  bool get _restartRequired {
    final runtimeId = DiscourseInstanceRuntime.instanceId;
    final desiredId = _enabled
        ? _selected.id
        : DiscourseInstanceRuntime.defaultInstanceId;
    return runtimeId != desiredId;
  }

  Future<void> _setEnabled(bool value) async {
    setState(() => _enabled = value);
    await _manager.setEnabled(value);
    await _reload();
    _showRestartNotice();
  }

  Future<void> _select(DiscourseInstanceProfile profile) async {
    if (!_enabled) {
      await _manager.setEnabled(true);
    }
    await _manager.selectInstance(profile.id);
    await _reload();
    _showRestartNotice();
  }

  void _showRestartNotice() {
    if (!mounted || !_restartRequired) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('实例选择已保存。重启 FluxDo 后会完整切换网络、账号与 WebView 会话边界。'),
      ),
    );
  }

  Future<void> _addInstance() async {
    final nameController = TextEditingController();
    final urlController = TextEditingController();
    String? errorText;

    final result = await showDialog<(String, String)>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('添加 Discourse 实例'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: '名称（可选）',
                    hintText: '例如 Meta Discourse',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: urlController,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: '论坛地址',
                    hintText: 'https://forum.example.com',
                    errorText: errorText,
                  ),
                  onSubmitted: (_) {
                    try {
                      DiscourseInstanceRuntime.normalizeBaseUrl(
                        urlController.text,
                      );
                      Navigator.of(dialogContext).pop((
                        nameController.text,
                        urlController.text,
                      ));
                    } catch (e) {
                      setDialogState(
                        () => errorText = e is FormatException
                            ? e.message.toString()
                            : '地址无效',
                      );
                    }
                  },
                ),
                const SizedBox(height: 12),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '支持标准 Discourse 根地址和相对子目录部署；query 与 fragment 会被移除。',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                try {
                  DiscourseInstanceRuntime.normalizeBaseUrl(urlController.text);
                  Navigator.of(dialogContext).pop((
                    nameController.text,
                    urlController.text,
                  ));
                } catch (e) {
                  setDialogState(
                    () => errorText = e is FormatException
                        ? e.message.toString()
                        : '地址无效',
                  );
                }
              },
              child: const Text('添加'),
            ),
          ],
        ),
      ),
    );

    nameController.dispose();
    urlController.dispose();
    if (result == null) return;

    try {
      final profile = await _manager.addInstance(
        name: result.$1,
        baseUrl: result.$2,
      );
      await _manager.setEnabled(true);
      await _manager.selectInstance(profile.id);
      await _reload();
      _showRestartNotice();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('添加实例失败：$e')),
      );
    }
  }

  Future<void> _removeInstance(DiscourseInstanceProfile profile) async {
    if (profile.builtIn) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('移除 ${profile.name}？'),
        content: const Text(
          '只移除实例配置，不主动清除该站点已经保存的 Cookie/账号快照，后续重新添加同一地址仍可继续使用。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _manager.removeInstance(profile.id);
    await _reload();
    _showRestartNotice();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Discourse 实例（实验性）')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : _addInstance,
        icon: const Icon(Icons.add_rounded),
        label: const Text('添加实例'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: [
                Card(
                  child: SwitchListTile(
                    value: _enabled,
                    onChanged: _setEnabled,
                    title: const Text('启用多 Discourse 实例'),
                    subtitle: const Text(
                      '实验性功能。一次只运行一个实例；实例切换在下次启动时生效，以保证网络、Cookie、账号和 MessageBus 使用同一站点。',
                    ),
                  ),
                ),
                if (_restartRequired)
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.restart_alt_rounded),
                      title: Text('需要重启 FluxDo'),
                      subtitle: Text('当前进程继续使用旧实例；重启后应用所选实例。'),
                    ),
                  ),
                const SizedBox(height: 8),
                ..._instances.map((profile) {
                  final selected = _enabled && profile.id == _selected.id;
                  final running = profile.id == DiscourseInstanceRuntime.instanceId;
                  return Card(
                    child: RadioListTile<String>(
                      value: profile.id,
                      groupValue: _enabled ? _selected.id : null,
                      onChanged: (_) => _select(profile),
                      title: Row(
                        children: [
                          Expanded(child: Text(profile.name)),
                          if (running)
                            const Padding(
                              padding: EdgeInsets.only(left: 8),
                              child: Chip(label: Text('当前运行')),
                            ),
                          if (selected && !running)
                            const Padding(
                              padding: EdgeInsets.only(left: 8),
                              child: Chip(label: Text('下次启动')),
                            ),
                        ],
                      ),
                      subtitle: Text(profile.baseUrl),
                      secondary: profile.builtIn
                          ? const Icon(Icons.home_rounded)
                          : IconButton(
                              tooltip: '移除实例',
                              onPressed: () => _removeInstance(profile),
                              icon: const Icon(Icons.delete_outline_rounded),
                            ),
                    ),
                  );
                }),
              ],
            ),
    );
  }
}
