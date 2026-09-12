import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/s.dart';
import '../models/stevessr_render_params.dart';
import '../services/stevessr_export_service.dart';
import '../utils/share_utils.dart';
import '../widgets/stevessr/stevessr_canvas.dart';

/// StevesSR 离线图片生成器。
class StevessrGeneratorPage extends StatefulWidget {
  const StevessrGeneratorPage({super.key});

  @override
  State<StevessrGeneratorPage> createState() => _StevessrGeneratorPageState();
}

class _StevessrGeneratorPageState extends State<StevessrGeneratorPage> {
  final _repaintBoundaryKey = GlobalKey();
  late final TextEditingController _textController;
  late final TextEditingController _widthController;
  late final TextEditingController _heightController;
  late final TextEditingController _bubbleXController;
  late final TextEditingController _bubbleYController;
  late final TextEditingController _bubbleWidthController;
  late final TextEditingController _bubbleHeightController;
  late final TextEditingController _characterXController;
  late final TextEditingController _characterYController;
  late final TextEditingController _characterWidthController;
  late final TextEditingController _characterHeightController;
  late final TextEditingController _strokeWidthController;
  late final TextEditingController _fontMinController;
  late final TextEditingController _fontMaxController;
  late final TextEditingController _lineHeightController;
  late final TextEditingController _paddingController;
  late final TextEditingController _backgroundController;
  late final TextEditingController _bubbleFillController;
  late final TextEditingController _bubbleStrokeController;
  late final TextEditingController _textColorController;

  StevessrRenderParams _params = StevessrRenderParams.defaults();
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    final p = _params;
    _textController = TextEditingController(text: p.text);
    _widthController = TextEditingController(text: '${p.width}');
    _heightController = TextEditingController(text: '${p.height}');
    _bubbleXController = _numberController(p.bubbleRect.x);
    _bubbleYController = _numberController(p.bubbleRect.y);
    _bubbleWidthController = _numberController(p.bubbleRect.width);
    _bubbleHeightController = _numberController(p.bubbleRect.height);
    _characterXController = _numberController(p.characterRect.x);
    _characterYController = _numberController(p.characterRect.y);
    _characterWidthController = _numberController(p.characterRect.width);
    _characterHeightController = _numberController(p.characterRect.height);
    _strokeWidthController = _numberController(p.bubbleStrokeWidth);
    _fontMinController = TextEditingController(text: '${p.fontMin}');
    _fontMaxController = TextEditingController(text: '${p.fontMax}');
    _lineHeightController = _numberController(p.lineHeight);
    _paddingController = _numberController(p.padding);
    _backgroundController = TextEditingController(
      text: _colorHex(p.background),
    );
    _bubbleFillController = TextEditingController(
      text: _colorHex(p.bubbleFill),
    );
    _bubbleStrokeController = TextEditingController(
      text: _colorHex(p.bubbleStroke),
    );
    _textColorController = TextEditingController(text: _colorHex(p.textColor));
  }

  TextEditingController _numberController(num value) {
    return TextEditingController(text: _formatNumber(value.toDouble()));
  }

  @override
  void dispose() {
    for (final controller in [
      _textController,
      _widthController,
      _heightController,
      _bubbleXController,
      _bubbleYController,
      _bubbleWidthController,
      _bubbleHeightController,
      _characterXController,
      _characterYController,
      _characterWidthController,
      _characterHeightController,
      _strokeWidthController,
      _fontMinController,
      _fontMaxController,
      _lineHeightController,
      _paddingController,
      _backgroundController,
      _bubbleFillController,
      _bubbleStrokeController,
      _textColorController,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _setParams(StevessrRenderParams params) {
    setState(() => _params = params.normalized());
  }

  void _setText(String value) {
    _setParams(_params.copyWith(text: value));
  }

  Color? _parseColor(String value) {
    var hex = value.trim().replaceFirst('#', '');
    if (hex.length == 6) hex = 'ff$hex';
    if (hex.length != 8) return null;
    final parsed = int.tryParse(hex, radix: 16);
    return parsed == null ? null : Color(parsed);
  }

  String _colorHex(Color color) {
    int channel(double value) => (value * 255).round().clamp(0, 255).toInt();
    String hex(int value) => value.toRadixString(16).padLeft(2, '0');
    return '#${hex(channel(color.a))}${hex(channel(color.r))}${hex(channel(color.g))}${hex(channel(color.b))}';
  }

  String _formatNumber(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
  }

  int? _parseInt(String value) => int.tryParse(value.trim());

  double? _parseDouble(String value) => double.tryParse(value.trim());

  void _updateSize({int? width, int? height}) {
    _setParams(_params.copyWith(width: width, height: height));
  }

  void _updateBubbleRect() {
    final rect = _params.bubbleRect.copyWith(
      x: _parseDouble(_bubbleXController.text),
      y: _parseDouble(_bubbleYController.text),
      width: _parseDouble(_bubbleWidthController.text),
      height: _parseDouble(_bubbleHeightController.text),
    );
    _setParams(_params.copyWith(bubbleRect: rect));
  }

  void _updateCharacterRect() {
    final rect = _params.characterRect.copyWith(
      x: _parseDouble(_characterXController.text),
      y: _parseDouble(_characterYController.text),
      width: _parseDouble(_characterWidthController.text),
      height: _parseDouble(_characterHeightController.text),
    );
    _setParams(_params.copyWith(characterRect: rect));
  }

  Future<void> _save() async {
    await _export(save: true);
  }

  Future<void> _share() async {
    await _export(save: false);
  }

  Future<void> _export({required bool save}) async {
    if (_isExporting) return;
    setState(() => _isExporting = true);
    try {
      final image = await StevessrExportService.render(
        params: _params,
        repaintBoundaryKey: _repaintBoundaryKey,
      );
      if (save) {
        await StevessrExportService.save(image);
      } else {
        final outcome = await StevessrExportService.share(image);
        if (mounted && !outcome.shared) {
          _showMessage(context.l10n.renderFailed);
        }
      }
    } catch (error) {
      if (mounted) {
        _showMessage('${context.l10n.renderFailed}: $error');
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.title)),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 820;
          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _buildPreviewArea(constraints.maxWidth * .58)),
                SizedBox(
                  width: math.min(420, constraints.maxWidth * .42),
                  child: _buildControls(),
                ),
              ],
            );
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 24),
            child: Column(
              children: [
                _buildPreviewArea(constraints.maxWidth),
                _buildControls(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildPreviewArea(double availableWidth) {
    final previewWidth = math.min(math.max(240.0, availableWidth - 32), 560.0);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Center(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: StevessrCanvas(
                key: ValueKey('canvas-${_params.expression.key}'),
                repaintBoundaryKey: _repaintBoundaryKey,
                params: _params,
                logicalWidth: previewWidth,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildControls() {
    final l10n = context.l10n;
    return Card(
      margin: const EdgeInsets.fromLTRB(0, 16, 16, 16),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.description,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _textController,
              minLines: 3,
              maxLines: 8,
              maxLength: 500,
              decoration: InputDecoration(
                labelText: l10n.text,
                border: const OutlineInputBorder(),
              ),
              onChanged: _setText,
            ),
            const SizedBox(height: 12),
            _buildEnumDropdown<StevessrExpression>(
              label: l10n.expression,
              value: _params.expression,
              values: StevessrExpression.values,
              labelBuilder: _enumLabel,
              onChanged: (value) =>
                  _setParams(_params.copyWith(expression: value)),
            ),
            const SizedBox(height: 12),
            _buildEnumDropdown<StevessrBubble>(
              label: l10n.bubble,
              value: _params.bubble,
              values: StevessrBubble.values,
              labelBuilder: _enumLabel,
              onChanged: (value) => _setParams(_params.copyWith(bubble: value)),
            ),
            const SizedBox(height: 12),
            _buildEnumDropdown<StevessrFormat>(
              label: l10n.format,
              value: _params.format,
              values: StevessrFormat.values,
              labelBuilder: (value) => switch (value) {
                StevessrFormat.png => l10n.png,
                StevessrFormat.webp => l10n.webp,
                StevessrFormat.svg => l10n.svg,
              },
              onChanged: (value) => _setParams(_params.copyWith(format: value)),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildIntField(
                    controller: _widthController,
                    label: l10n.width,
                    onChanged: (value) => _updateSize(width: value),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildIntField(
                    controller: _heightController,
                    label: l10n.height,
                    onChanged: (value) => _updateSize(height: value),
                  ),
                ),
              ],
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.transparent),
              value: _params.transparent,
              onChanged: (value) =>
                  _setParams(_params.copyWith(transparent: value)),
            ),
            _buildColorField(
              controller: _backgroundController,
              label: l10n.background,
              onChanged: (value) => _changeColor(value, (color) {
                _setParams(_params.copyWith(background: color));
              }),
            ),
            _buildColorField(
              controller: _bubbleFillController,
              label: l10n.bubbleFill,
              onChanged: (value) => _changeColor(value, (color) {
                _setParams(_params.copyWith(bubbleFill: color));
              }),
            ),
            _buildColorField(
              controller: _bubbleStrokeController,
              label: l10n.bubbleStroke,
              onChanged: (value) => _changeColor(value, (color) {
                _setParams(_params.copyWith(bubbleStroke: color));
              }),
            ),
            _buildColorField(
              controller: _textColorController,
              label: l10n.textColor,
              onChanged: (value) => _changeColor(value, (color) {
                _setParams(_params.copyWith(textColor: color));
              }),
            ),
            _buildDoubleField(
              controller: _strokeWidthController,
              label: l10n.bubbleStroke,
              onChanged: (value) =>
                  _setParams(_params.copyWith(bubbleStrokeWidth: value)),
            ),
            const SizedBox(height: 8),
            _buildEnumDropdown<StevessrTail>(
              label: l10n.tail,
              value: _params.tail,
              values: StevessrTail.values,
              labelBuilder: (value) => switch (value) {
                StevessrTail.left => l10n.left,
                StevessrTail.right => l10n.right,
                StevessrTail.none => l10n.none,
              },
              onChanged: (value) => _setParams(_params.copyWith(tail: value)),
            ),
            const SizedBox(height: 12),
            _buildEnumDropdown<StevessrFont>(
              label: l10n.font,
              value: _params.font,
              values: StevessrFont.values,
              labelBuilder: (value) => switch (value) {
                StevessrFont.sans => l10n.sans,
                StevessrFont.serif => l10n.serif,
                StevessrFont.mono => l10n.mono,
                StevessrFont.rounded => l10n.rounded,
              },
              onChanged: (value) => _setParams(_params.copyWith(font: value)),
            ),
            const SizedBox(height: 12),
            _buildEnumDropdown<StevessrTextAlign>(
              label: l10n.align,
              value: _params.align,
              values: StevessrTextAlign.values,
              labelBuilder: (value) => switch (value) {
                StevessrTextAlign.left => l10n.left,
                StevessrTextAlign.center => l10n.center,
                StevessrTextAlign.right => l10n.right,
              },
              onChanged: (value) => _setParams(_params.copyWith(align: value)),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildIntField(
                    controller: _fontMinController,
                    label: l10n.fontMin,
                    onChanged: (value) =>
                        _setParams(_params.copyWith(fontMin: value)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildIntField(
                    controller: _fontMaxController,
                    label: l10n.fontMax,
                    onChanged: (value) =>
                        _setParams(_params.copyWith(fontMax: value)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildDoubleField(
                    controller: _lineHeightController,
                    label: l10n.lineHeight,
                    onChanged: (value) =>
                        _setParams(_params.copyWith(lineHeight: value)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildDoubleField(
                    controller: _paddingController,
                    label: l10n.padding,
                    onChanged: (value) =>
                        _setParams(_params.copyWith(padding: value)),
                  ),
                ),
              ],
            ),
            _buildPositionSection(),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _isExporting ? null : _save,
                    icon: const Icon(Icons.save_rounded),
                    label: Text(l10n.save),
                  ),
                ),
                if (ShareUtils.canShareFiles) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isExporting ? null : _share,
                      icon: const Icon(Icons.share_rounded),
                      label: Text(l10n.share),
                    ),
                  ),
                ],
              ],
            ),
            if (_isExporting) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
              const SizedBox(height: 4),
              Center(child: Text(l10n.rendering)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPositionSection() {
    final l10n = context.l10n;
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text(l10n.position),
      children: [
        _buildRectFields(
          title: l10n.bubble,
          xController: _bubbleXController,
          yController: _bubbleYController,
          widthController: _bubbleWidthController,
          heightController: _bubbleHeightController,
          onChanged: _updateBubbleRect,
        ),
        const SizedBox(height: 12),
        _buildRectFields(
          title: l10n.expression,
          xController: _characterXController,
          yController: _characterYController,
          widthController: _characterWidthController,
          heightController: _characterHeightController,
          onChanged: _updateCharacterRect,
        ),
      ],
    );
  }

  Widget _buildRectFields({
    required String title,
    required TextEditingController xController,
    required TextEditingController yController,
    required TextEditingController widthController,
    required TextEditingController heightController,
    required VoidCallback onChanged,
  }) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildDoubleField(
                controller: xController,
                label: l10n.bubbleX,
                onChanged: (_) => onChanged(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildDoubleField(
                controller: yController,
                label: l10n.bubbleY,
                onChanged: (_) => onChanged(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildDoubleField(
                controller: widthController,
                label: l10n.bubbleWidth,
                onChanged: (_) => onChanged(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildDoubleField(
                controller: heightController,
                label: l10n.bubbleHeight,
                onChanged: (_) => onChanged(),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildColorField({
    required TextEditingController controller,
    required String label,
    required ValueChanged<String> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.palette_outlined),
          border: const OutlineInputBorder(),
        ),
        onChanged: onChanged,
      ),
    );
  }

  void _changeColor(String value, void Function(Color color) onValid) {
    final color = _parseColor(value);
    if (color != null) onValid(color);
  }

  Widget _buildIntField({
    required TextEditingController controller,
    required String label,
    required ValueChanged<int?> onChanged,
  }) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      onChanged: (value) => onChanged(_parseInt(value)),
    );
  }

  Widget _buildDoubleField({
    required TextEditingController controller,
    required String label,
    required ValueChanged<double?> onChanged,
  }) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      onChanged: (value) => onChanged(_parseDouble(value)),
    );
  }

  Widget _buildEnumDropdown<T>({
    required String label,
    required T value,
    required List<T> values,
    required String Function(T value) labelBuilder,
    required ValueChanged<T> onChanged,
  }) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: [
        for (final item in values)
          DropdownMenuItem<T>(value: item, child: Text(labelBuilder(item))),
      ],
      onChanged: (item) {
        if (item != null) onChanged(item);
      },
    );
  }

  String _enumLabel(Object value) {
    final name = value.toString().split('.').last;
    return name[0].toUpperCase() + name.substring(1);
  }
}
