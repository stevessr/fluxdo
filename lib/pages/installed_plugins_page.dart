import 'package:flutter/material.dart';

import '../l10n/s.dart';
import '../services/external_plugin_service.dart';

/// Android 已安装外部插件。安装器返回后在 resumed 时重新扫描，卸载无需重启。
class InstalledPluginsPage extends StatefulWidget {
  const InstalledPluginsPage({super.key});

  @override
  State<InstalledPluginsPage> createState() => _InstalledPluginsPageState();
}

class _InstalledPluginsPageState extends State<InstalledPluginsPage>
    with WidgetsBindingObserver {
  late Future<List<ExternalPlugin>> _plugins;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _plugins = ExternalPluginService.instance.installedPlugins();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _reload();
  }

  Future<void> _reload() {
    final future = ExternalPluginService.instance.installedPlugins();
    if (mounted) setState(() => _plugins = future);
    return future.then((_) {});
  }

  Future<void> _launch(ExternalPlugin plugin) async {
    final opened = await ExternalPluginService.instance.launchPlugin(plugin);
    if (!mounted || opened) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.externalPlugin_openFailed)),
    );
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.externalPlugin_title),
        actions: [
          IconButton(
            tooltip: context.l10n.externalPlugin_refresh,
            onPressed: _reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FutureBuilder<List<ExternalPlugin>>(
        future: _plugins,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final plugins = snapshot.data!;
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              children: plugins.isEmpty
                  ? [
                      Padding(
                        padding: const EdgeInsets.all(32),
                        child: Center(
                          child: Text(context.l10n.externalPlugin_empty),
                        ),
                      ),
                    ]
                  : [
                      for (final plugin in plugins)
                        ListTile(
                          leading: const Icon(Icons.extension_rounded),
                          title: Text(plugin.label),
                          subtitle: Text(context.l10n.externalPlugin_openHint),
                          trailing: const Icon(Icons.open_in_new_rounded),
                          onTap: () => _launch(plugin),
                        ),
                    ],
            ),
          );
        },
      ),
    );
  }
}
