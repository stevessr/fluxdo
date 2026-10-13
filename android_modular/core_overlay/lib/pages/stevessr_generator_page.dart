import 'package:flutter/material.dart';

import '../services/android_sticker_companion_service.dart';
import '../services/stevessr_export_service.dart';

/// Thin compatibility view. The actual editor, renderer, and avatar assets
/// live exclusively in the separately updated Sticker companion APK.
class StevessrGeneratorPage extends StatefulWidget {
  const StevessrGeneratorPage({super.key, this.onInsert});

  final Future<void> Function(StevessrExportedImage image)? onInsert;

  @override
  State<StevessrGeneratorPage> createState() =>
      _StevessrGeneratorPageState();
}

class _StevessrGeneratorPageState
    extends State<StevessrGeneratorPage> {
  bool _busy = false;

  Future<void> _launch() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (!await AndroidStickerCompanionService.isAvailable()) {
        throw StateError('需要安装同签名的 StevesSR 独立 APK');
      }
      final generated = await AndroidStickerCompanionService.generate();
      if (generated == null) return;
      if (widget.onInsert != null) {
        await widget.onInsert!(generated);
      } else {
        await StevessrExportService.save(generated);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('StevesSR 表情包')),
    body: Center(
      child: FilledButton.icon(
        onPressed: _busy ? null : _launch,
        icon: const Icon(Icons.extension_outlined),
        label: Text(_busy ? '处理中' : '打开独立表情包插件'),
      ),
    ),
  );
}
