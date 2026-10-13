import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/core_providers.dart';

import '../services/android_optional_plugin_service.dart';

/// Android core intentionally contains no LDC/CDK OAuth, balance or reward
/// implementation. Each feature is installed/upgraded as its own APK.
class MetaversePage extends ConsumerStatefulWidget {
  const MetaversePage({super.key});

  @override
  ConsumerState<MetaversePage> createState() => _MetaversePageState();
}

class _MetaversePageState extends ConsumerState<MetaversePage> {
  Future<List<AndroidOptionalPlugin>> _available =
      AndroidOptionalPluginService.instance.list();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('元宇宙')),
      body: FutureBuilder<List<AndroidOptionalPlugin>>(
        future: _available,
        builder: (context, snapshot) {
          final modules = snapshot.data ?? [];
          return ListView(
            children: [
              if (snapshot.hasError)
                ListTile(title: Text(snapshot.error.toString())),
              for (final id in const ['ldc', 'cdk'])
                Builder(builder: (context) {
                  final list = modules.where((m) => m.id == id);
                  final plugin = list.isEmpty ? null : list.first;
                  final usable = plugin?.compatible == true;
                  return ListTile(
                    leading: const Icon(Icons.extension),
                    title: Text(id.toUpperCase()),
                    subtitle: Text(usable
                        ? '插件 ${plugin!.version ?? ""} · 独立登录'
                        : '需要单独安装同签名插件 · ${plugin?.reason ?? "not_installed"}'),
                    trailing: Icon(usable
                        ? Icons.open_in_new
                        : Icons.download_outlined),
                    onTap: !usable ? null : () async {
                      try {
                        await AndroidOptionalPluginService.instance.launch(
                          id,
                          payload: {
                            'accountSlot':
                                AndroidOptionalPluginService.sessionSlotForUsername(
                              ref.read(currentUserProvider).value?.username,
                            ),
                          },
                        );
                      } catch (error) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(error.toString())),
                        );
                      }
                    },
                  );
                }),
              ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text('刷新插件状态'),
                onTap: () => setState(() {
                  _available = AndroidOptionalPluginService.instance.list();
                }),
              ),
            ],
          );
        },
      ),
    );
  }
}
