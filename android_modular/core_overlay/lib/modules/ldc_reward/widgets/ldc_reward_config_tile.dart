import 'package:flutter/material.dart';

/// LDC reward credentials live in the plugin, never in Android Core.
class LdcRewardConfigTile extends StatelessWidget {
  const LdcRewardConfigTile({super.key});

  @override
  Widget build(BuildContext context) => const ListTile(
    leading: Icon(Icons.extension),
    title: Text('打赏配置由 LDC 插件管理'),
  );
}
