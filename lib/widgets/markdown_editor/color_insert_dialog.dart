import 'package:flutter/material.dart';

import '../../../../../l10n/s.dart';
import '../../utils/dialog_utils.dart';

/// 文字颜色选色对话框（Markdown 工具栏与富 composer 共用）。
///
/// 返回颜色值原文（如 `#e45735` / `red`），取消返回 null。值会填进
/// `[color=…]` BBCode / textColor mark，由 discourse-bbcode-color 插件
/// 原样透传进 `style="color:…"` —— 只放行 hex 与命名色，非法值 cook 后
/// 不渲染，编辑端先挡掉。
///
/// 预置色板取常用 Material 色 + 中性灰阶；自定义输入接受
/// `#rgb` / `#rrggbb` / CSS 命名色（与内核 input rule 的字符集一致）。
class ColorInsertDialog extends StatefulWidget {
  /// 预置色板（hex，不带 alpha）
  static const _palette = <String, String>{
    '#000000': '黑',
    '#546e7a': '蓝灰',
    '#90a4ae': '浅蓝灰',
    '#cfd8dc': '极浅灰',
    '#ffffff': '白',
    '#b71c1c': '深红',
    '#ef5350': '红',
    '#ff7043': '橙红',
    '#ffa726': '橙',
    '#ffd54f': '琥珀',
    '#fff176': '浅黄',
    '#aed581': '黄绿',
    '#66bb6a': '绿',
    '#2e7d32': '深绿',
    '#26a69a': '青绿',
    '#4dd0e1': '青',
    '#29b6f6': '天蓝',
    '#1e88e5': '蓝',
    '#3949ab': '靛蓝',
    "#7e57c2": '紫',
    '#ab47bc': '深紫',
    '#ec407a': '粉',
    '#f48fb1': '浅粉',
    '#8d6e63': '棕',
  };

  const ColorInsertDialog({super.key, this.initialValue});

  /// 打开时的初始颜色（hex 原文）
  final String? initialValue;

  @override
  State<ColorInsertDialog> createState() => _ColorInsertDialogState();
}

class _ColorInsertDialogState extends State<ColorInsertDialog> {
  late final TextEditingController _hexController;

  @override
  void initState() {
    super.initState();
    _hexController = TextEditingController(text: widget.initialValue ?? '');
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  /// 输入规范化：3/6 位裸 hex 补 `#`，其余原样透传（命名色）。
  static String _normalize(String raw) {
    final v = raw.trim();
    final bare = RegExp(r'^[0-9a-fA-F]{3}([0-9a-fA-F]{3})?$').firstMatch(v);
    return bare != null ? '#$v' : v;
  }

  /// 是否为合法可提交的颜色值：hex(#rgb/#rrggbb) 或 CSS 命名色
  /// （字母串，长度上限对齐内核 input rule 的 1..24 字符集）。
  static bool _isValid(String value) {
    if (RegExp(r'^#[0-9a-fA-F]{3}([0-9a-fA-F]{3})?$').hasMatch(value)) {
      return true;
    }
    return RegExp(r'^[a-zA-Z]{1,24}$').hasMatch(value);
  }

  static Color? _tryParse(String value) {
    var hex = value.trim();
    if (!hex.startsWith('#')) {
      // 命名色不猜渲染值；仅 hex 参与实时预览
      if (!_isValid(hex)) return null;
      return null;
    }
    hex = hex.substring(1);
    if (hex.length == 3) {
      hex = hex.split('').map((c) => '$c$c').join();
    }
    if (hex.length != 6) return null;
    return Color(int.parse('ff$hex', radix: 16));
  }

  void _submit(String value) {
    Navigator.of(context).pop(_normalize(value));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final typed = _normalize(_hexController.text);
    final previewColor = typed.startsWith('#') ? _tryParse(typed) : null;

    return AlertDialog(
      title: Text(S.current.toolbar_textColor),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in ColorInsertDialog._palette.entries)
                  InkWell(
                    onTap: () => _submit(entry.key),
                    borderRadius: BorderRadius.circular(20),
                    child: Tooltip(
                      message: '${entry.value} ${entry.key}',
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Color(
                            int.parse('ff${entry.key.substring(1)}', radix: 16),
                          ),
                          shape: BoxShape.circle,
                          border: Border.all(color: scheme.outlineVariant),
                        ),
                        // 白色色板在浅色主题下靠边框可见，无需子节点
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _hexController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: S.current.toolbar_customColor,
                hintText: '#e45735 或 red',
                border: const OutlineInputBorder(),
                errorText: _hexController.text.isEmpty || _isValid(typed)
                    ? null
                    : S.current.toolbar_invalidColorValue,
                suffixIcon: previewColor != null
                    ? Padding(
                        padding: const EdgeInsets.all(10),
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: previewColor,
                            shape: BoxShape.circle,
                            border: Border.all(color: scheme.outlineVariant),
                          ),
                        ),
                      )
                    : null,
              ),
              onSubmitted: (value) {
                final normalized = _normalize(value);
                if (_isValid(normalized)) _submit(normalized);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(S.current.common_cancel),
        ),
        FilledButton(
          onPressed: _hexController.text.isEmpty || !_isValid(typed)
              ? null
              : () => _submit(_hexController.text),
          child: Text(S.current.common_confirm),
        ),
      ],
    );
  }
}

/// 显示文字颜色选色对话框；返回颜色值原文（如 `#e45735` / `red`），取消返回 null。
Future<String?> showColorInsertDialog(
  BuildContext context, {
  String? initialValue,
}) {
  return showAppDialog<String>(
    context: context,
    builder: (context) => ColorInsertDialog(initialValue: initialValue),
  );
}
