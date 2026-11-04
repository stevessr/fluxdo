import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluxdo/l10n/s.dart';
import '../../services/toast_service.dart';
import '../../services/uploads/long_image_splitter.dart';
import '../../utils/dialog_utils.dart';
import 'image_compression_strategy.dart';

/// 独立长图上传入口返回的单个切片。
class LongImageUploadResult {
  const LongImageUploadResult({
    required this.path,
    required this.originalName,
  });

  final String path;
  final String originalName;
}

class LongImageUploadDialog extends StatefulWidget {
  const LongImageUploadDialog({
    super.key,
    required this.imagePath,
    required this.imageName,
    required this.info,
  });

  final String imagePath;
  final String imageName;
  final LongImageInfo info;

  @override
  State<LongImageUploadDialog> createState() => _LongImageUploadDialogState();
}

class _LongImageUploadDialogState extends State<LongImageUploadDialog> {
  static const _qualityPreferenceKey = 'markdown_editor.image_upload_quality';

  int? _partCount;
  int _quality = 85;
  bool _isProcessing = false;

  int get _recommendedCount => LongImageSplitter.recommendedPartCount(
    width: widget.info.width,
    height: widget.info.height,
  );

  int get _maxPartCount =>
      (widget.info.aspectRatio.ceil() + 2).clamp(2, 20).toInt();

  @override
  void initState() {
    super.initState();
    _restoreQualityPreference();
  }

  Future<void> _restoreQualityPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getInt(_qualityPreferenceKey);
    if (!mounted || saved == null) return;
    setState(() => _quality = saved.clamp(10, 100).toInt());
  }

  Future<void> _submit() async {
    final partCount = _partCount;
    if (partCount == null || _isProcessing) return;

    setState(() => _isProcessing = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_qualityPreferenceKey, _quality);

      final slices = await LongImageSplitter.split(
        widget.imagePath,
        originalName: widget.imageName,
        partCount: partCount,
      );
      final results = <LongImageUploadResult>[];
      for (final slice in slices) {
        final strategy = ImageCompressionStrategyFactory.fromPath(slice.path);
        final compressedPath = await strategy.compress(slice.path, _quality);
        results.add(
          LongImageUploadResult(
            path: compressedPath,
            originalName: slice.name,
          ),
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop(results);
    } catch (error) {
      if (!mounted) return;
      ToastService.showError(S.current.imageUpload_processFailed('$error'));
      setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = _partCount;
    final plan = selected == null
        ? null
        : LongImageSplitter.planForCount(
            width: widget.info.width,
            height: widget.info.height,
            partCount: selected,
          );

    return AlertDialog(
      title: Text(S.current.imageUpload_longImageTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 220,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.file(
                File(widget.imagePath),
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Center(
                  child: Icon(Icons.broken_image_outlined, size: 48),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '${widget.info.width} × ${widget.info.height} px · '
              '${widget.info.aspectRatio.toStringAsFixed(2)}:1',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    S.current.imageUpload_longImageSliceCount,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                DropdownButton<int>(
                  value: _partCount,
                  hint: Text(S.current.imageUpload_longImageSelectCount),
                  items: [
                    for (var count = 2; count <= _maxPartCount; count++)
                      DropdownMenuItem(value: count, child: Text('$count')),
                  ],
                  onChanged: _isProcessing
                      ? null
                      : (value) => setState(() => _partCount = value),
                ),
              ],
            ),
            Text(
              '${S.current.imageUpload_longImageRecommendedPrefix} '
              '$_recommendedCount',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            if (plan != null) ...[
              const SizedBox(height: 6),
              Text(
                '${S.current.imageUpload_longImagePartHeightPrefix} '
                '${plan.partHeight}px',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.content_cut_rounded,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    S.current.imageUpload_longImageOverlapHint,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  S.current.imageUpload_compressionQuality,
                  style: theme.textTheme.bodyMedium,
                ),
                Expanded(
                  child: Slider(
                    value: _quality.toDouble(),
                    min: 10,
                    max: 100,
                    divisions: 18,
                    label: '$_quality%',
                    onChanged: _isProcessing
                        ? null
                        : (value) =>
                            setState(() => _quality = value.round()),
                  ),
                ),
                SizedBox(
                  width: 48,
                  child: Text(
                    '$_quality%',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isProcessing ? null : () => Navigator.of(context).pop(),
          child: Text(S.current.common_cancel),
        ),
        FilledButton(
          onPressed: _isProcessing || _partCount == null ? null : _submit,
          child: _isProcessing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(S.current.common_upload),
        ),
      ],
    );
  }
}

/// 读取尺寸并校验后才显示长图上传 UI。
///
/// 普通图片、读取失败或不满足长宽比要求时不会打开切片弹框。
Future<List<LongImageUploadResult>?> showLongImageUploadDialog(
  BuildContext context, {
  required String imagePath,
  String? imageName,
}) async {
  final info = await LongImageSplitter.inspect(imagePath);
  if (!context.mounted) return null;

  if (info == null) {
    ToastService.showError(S.current.imageUpload_longImageReadFailed);
    return null;
  }
  if (!info.isEligible) {
    ToastService.showInfo(S.current.imageUpload_longImageNotEligible);
    return null;
  }

  return showAppDialog<List<LongImageUploadResult>>(
    context: context,
    barrierDismissible: false,
    builder: (_) => LongImageUploadDialog(
      imagePath: imagePath,
      imageName: imageName ?? p.basename(imagePath),
      info: info,
    ),
  );
}
