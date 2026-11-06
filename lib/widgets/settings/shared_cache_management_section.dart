import 'package:ai_model_manager/ai_model_manager.dart';
import 'package:app_icons/app_icons.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3e_ui/m3e_ui.dart';

import '../../l10n/s.dart';
import '../../providers/app_state_refresher.dart';
import '../../providers/core_providers.dart';
import '../../providers/theme_provider.dart';
import '../../services/data_management/cache_size_service.dart';
import '../../services/toast_service.dart';
import '../../utils/dialog_utils.dart';

/// 共享 URL 缓存的管理区块。
///
/// 与旧区块最大的区别是把“真实磁盘占用”和“按用途计算的逻辑大小”分开：
/// 同一物理对象可以同时属于正文、头像等多个用途，因此分类之和允许大于
/// 真实占用。清理完成后的 Toast 也用清理前后的真实占用差值，避免把共享
/// 引用的逻辑大小误报成释放空间。
class SharedCacheManagementSection extends ConsumerStatefulWidget {
  const SharedCacheManagementSection({super.key});

  @override
  ConsumerState<SharedCacheManagementSection> createState() =>
      _SharedCacheManagementSectionState();
}

class _SharedCacheManagementSectionState
    extends ConsumerState<SharedCacheManagementSection> {
  ImageCacheUsage? _usage;
  int _aiChatDataSize = -1;
  int _cookieCacheSize = -1;
  bool _isClearing = false;

  final Set<ImageCacheCategory> _selected = {...ImageCacheCategory.values};

  Map<ImageCacheCategory, int>? get _breakdown => _usage?.breakdown;

  int get _physicalTotal => _usage?.physicalBytes ?? -1;

  int get _logicalCategoryTotal =>
      _breakdown?.values.fold<int>(0, (sum, size) => sum + size) ?? 0;

  int get _selectedLogicalSize {
    final breakdown = _breakdown;
    if (breakdown == null) return 0;
    var total = 0;
    for (final category in _selected) {
      total += breakdown[category] ?? 0;
    }
    return total;
  }

  @override
  void initState() {
    super.initState();
    _loadCacheSizes();
  }

  Future<void> _loadCacheSizes() async {
    final prefs = ref.read(sharedPreferencesProvider);
    final results = await Future.wait([
      CacheSizeService.getImageCacheUsage(),
      CacheSizeService.getAiChatDataSize(prefs),
      CacheSizeService.getCookieCacheSize(),
    ]);
    if (!mounted) return;
    setState(() {
      _usage = results[0] as ImageCacheUsage;
      _aiChatDataSize = results[1] as int;
      _cookieCacheSize = results[2] as int;
    });
  }

  String _formatCacheSize(int size) {
    if (size < 0) return S.current.dataManagement_calculating;
    if (size == 0) return S.current.dataManagement_noCache;
    return CacheSizeService.formatSize(size);
  }

  String _categoryName(ImageCacheCategory category) => switch (category) {
    ImageCacheCategory.content => S.current.dataManagement_categoryContent,
    ImageCacheCategory.emoji => S.current.dataManagement_categoryEmoji,
    ImageCacheCategory.avatar => S.current.dataManagement_categoryAvatar,
    ImageCacheCategory.sticker => S.current.dataManagement_categorySticker,
    ImageCacheCategory.external => S.current.dataManagement_categoryExternal,
    ImageCacheCategory.other => S.current.dataManagement_categoryOther,
  };

  Color _categoryColor(ImageCacheCategory category, ColorScheme scheme) {
    const palette = {
      ImageCacheCategory.content: Color(0xFF4C8DF6),
      ImageCacheCategory.sticker: Color(0xFFF2A03F),
      ImageCacheCategory.emoji: Color(0xFF41BA6D),
      ImageCacheCategory.avatar: Color(0xFF45B7D2),
      ImageCacheCategory.external: Color(0xFF9B7BF0),
      ImageCacheCategory.other: Color(0xFF95A1AC),
    };
    return palette[category]!.harmonizeWith(scheme.primary);
  }

  Future<void> _clearSelected() async {
    final before =
        _usage?.physicalBytes ?? await CacheSizeService.getImageCacheSize();
    final confirmed = await _showConfirmDialog(
      title: S.current.dataManagement_clearSelectedTitle,
      content: S.current.dataManagement_clearSelectedContent,
      confirmText: S.current.common_clear,
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isClearing = true);
    try {
      for (final category in _selected) {
        await CacheSizeService.clearImageCacheCategory(category);
      }
      PaintingBinding.instance.imageCache.clear();

      final afterUsage = await CacheSizeService.getImageCacheUsage();
      final freed = before > afterUsage.physicalBytes
          ? before - afterUsage.physicalBytes
          : 0;
      if (mounted) setState(() => _usage = afterUsage);
      ToastService.showSuccess(
        S.current.dataManagement_freedSpace(CacheSizeService.formatSize(freed)),
      );
    } catch (e) {
      ToastService.showError(S.current.common_clearFailed(e.toString()));
    } finally {
      if (mounted) setState(() => _isClearing = false);
    }
  }

  Future<void> _clearAiChatData() async {
    final confirmed = await _showConfirmDialog(
      title: S.current.dataManagement_clearAiChatTitle,
      content: S.current.dataManagement_clearAiChatContent,
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isClearing = true);
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      await AiChatStorageService(prefs).deleteAllSessions();
      if (mounted) setState(() => _aiChatDataSize = 0);
      ToastService.showSuccess(S.current.dataManagement_aiChatCleared);
    } catch (e) {
      ToastService.showError(S.current.common_clearFailed(e.toString()));
    } finally {
      if (mounted) setState(() => _isClearing = false);
    }
  }

  Future<void> _clearCookieCache() async {
    final confirmed = await _showConfirmDialog(
      title: S.current.dataManagement_clearCookieTitle,
      content: S.current.dataManagement_clearCookieContent,
      confirmText: S.current.dataManagement_clearAndLogout,
      isDestructive: true,
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isClearing = true);
    try {
      await _doClearCookies();
      if (mounted) setState(() => _cookieCacheSize = 0);
      ToastService.showSuccess(S.current.dataManagement_cookieCleared);
    } catch (e) {
      ToastService.showError(S.current.common_clearFailed(e.toString()));
    } finally {
      if (mounted) setState(() => _isClearing = false);
    }
  }

  Future<void> _doClearCookies() async {
    final container = ProviderScope.containerOf(context, listen: false);
    await ref.read(discourseServiceProvider).logout(callApi: false);
    await AppStateRefresher.resetForLogout(container);
  }

  Future<bool?> _showConfirmDialog({
    required String title,
    required String content,
    String? confirmText,
    bool isDestructive = false,
  }) {
    return showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.common_cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: isDestructive
                ? FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                  )
                : null,
            child: Text(confirmText ?? context.l10n.common_confirm),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final usage = _usage;
    final breakdown = _breakdown;
    final categories = [...ImageCacheCategory.values];
    if (breakdown != null) {
      categories.sort((a, b) => (breakdown[b] ?? 0) - (breakdown[a] ?? 0));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedCardGroup(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Expanded(
                        child: Text(
                          context.l10n.dataManagement_imageCache,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      Text(
                        _formatCacheSize(_physicalTotal),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _SharedCacheSegmentedBar(
                    segments: breakdown == null
                        ? null
                        : [
                            for (final category in categories)
                              if (_selected.contains(category) &&
                                  (breakdown[category] ?? 0) > 0)
                                (
                                  color: _categoryColor(
                                    category,
                                    theme.colorScheme,
                                  ),
                                  size: breakdown[category]!,
                                ),
                          ],
                  ),
                  if (usage != null) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (usage.referenceCount > 0)
                          _UsagePill(
                            icon: Symbols.link_rounded,
                            label: context.l10n.dataManagement_cacheObjects(
                              usage.objectCount,
                              usage.referenceCount,
                            ),
                          ),
                        if (usage.deduplicatedBytes > 0)
                          _UsagePill(
                            icon: Symbols.content_copy_rounded,
                            label: context.l10n
                                .dataManagement_deduplicatedSpace(
                                  CacheSizeService.formatSize(
                                    usage.deduplicatedBytes,
                                  ),
                                ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.l10n.dataManagement_sharedCacheHint,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            for (final category in categories)
              _buildCategoryTile(theme, category, breakdown?[category]),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              child: SizedBox(
                width: double.infinity,
                height: 44,
                child: FilledButton(
                  onPressed:
                      _isClearing ||
                          breakdown == null ||
                          _selectedLogicalSize <= 0
                      ? null
                      : _clearSelected,
                  child: _isClearing
                      ? const LoadingSpinner(size: 18)
                      : Text(
                          S.current.dataManagement_clearSelected(
                            CacheSizeService.formatSize(_selectedLogicalSize),
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SegmentedCardGroup(
          children: [
            _buildLocalDataTile(
              theme: theme,
              icon: Symbols.smart_toy_rounded,
              title: context.l10n.dataManagement_aiChatData,
              size: _aiChatDataSize,
              onClear: _isClearing ? null : _clearAiChatData,
            ),
            _buildLocalDataTile(
              theme: theme,
              icon: Symbols.cookie_rounded,
              title: context.l10n.dataManagement_cookieCache,
              size: _cookieCacheSize,
              onClear: _isClearing ? null : _clearCookieCache,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCategoryTile(
    ThemeData theme,
    ImageCacheCategory category,
    int? size,
  ) {
    final color = _categoryColor(category, theme.colorScheme);
    final empty = size != null && size <= 0;
    final checked = _selected.contains(category) && !empty;
    String? percent;
    if (size != null && size > 0 && _logicalCategoryTotal > 0) {
      final value = size * 100 / _logicalCategoryTotal;
      percent = value < 1 ? '<1%' : '${value.round()}%';
    }

    return ListTile(
      dense: true,
      enabled: !empty && !_isClearing,
      leading: Checkbox(
        value: checked,
        shape: const CircleBorder(),
        activeColor: color,
        side: BorderSide(
          color: empty ? theme.colorScheme.outlineVariant : color,
          width: 2,
        ),
        onChanged: empty || _isClearing
            ? null
            : (value) => setState(() {
                if (value == true) {
                  _selected.add(category);
                } else {
                  _selected.remove(category);
                }
              }),
      ),
      title: Text.rich(
        TextSpan(
          text: _categoryName(category),
          children: [
            if (percent != null)
              TextSpan(
                text: '  $percent',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
      trailing: size == null
          ? _SharedCacheShimmer(width: 48, height: 14, theme: theme)
          : Text(
              _formatCacheSize(size),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: empty
                    ? theme.colorScheme.outline
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
      onTap: empty || _isClearing
          ? null
          : () => setState(() {
              if (_selected.contains(category)) {
                _selected.remove(category);
              } else {
                _selected.add(category);
              }
            }),
    );
  }

  Widget _buildLocalDataTile({
    required ThemeData theme,
    required IconData icon,
    required String title,
    required int size,
    required VoidCallback? onClear,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(_formatCacheSize(size)),
      trailing: TextButton(
        onPressed: size <= 0 ? null : onClear,
        child: Text(S.current.common_clear),
      ),
    );
  }
}

class _UsagePill extends StatelessWidget {
  const _UsagePill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SharedCacheSegmentedBar extends StatelessWidget {
  const _SharedCacheSegmentedBar({required this.segments});

  final List<({Color color, int size})>? segments;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 12,
      child: segments == null
          ? _SharedCacheShimmer(
              width: double.infinity,
              height: 12,
              theme: theme,
            )
          : CustomPaint(
              painter: _SharedCacheSegmentedBarPainter(
                segments: segments!,
                emptyColor: theme.colorScheme.surfaceContainerHighest,
              ),
              size: const Size(double.infinity, 12),
            ),
    );
  }
}

class _SharedCacheSegmentedBarPainter extends CustomPainter {
  _SharedCacheSegmentedBarPainter({
    required this.segments,
    required this.emptyColor,
  });

  final List<({Color color, int size})> segments;
  final Color emptyColor;

  static const double _gap = 3;
  static const double _minSegmentWidth = 10;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    final radius = Radius.circular(size.height / 2);
    final total = segments.fold<int>(0, (sum, item) => sum + item.size);
    if (total <= 0 || segments.isEmpty) {
      paint.color = emptyColor;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, radius),
        paint,
      );
      return;
    }

    final gapTotal = _gap * (segments.length - 1);
    final usable = (size.width - gapTotal).clamp(0.0, double.infinity);
    final widths = [
      for (final segment in segments) usable * segment.size / total,
    ];
    var deficit = 0.0;
    for (var i = 0; i < widths.length; i++) {
      if (widths[i] < _minSegmentWidth) {
        deficit += _minSegmentWidth - widths[i];
        widths[i] = _minSegmentWidth;
      }
    }
    if (deficit > 0) {
      var largest = 0;
      for (var i = 1; i < widths.length; i++) {
        if (widths[i] > widths[largest]) largest = i;
      }
      widths[largest] = (widths[largest] - deficit).clamp(
        _minSegmentWidth,
        double.infinity,
      );
    }

    var x = 0.0;
    for (var i = 0; i < segments.length; i++) {
      paint.color = segments[i].color;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, 0, widths[i], size.height),
          radius,
        ),
        paint,
      );
      x += widths[i] + _gap;
    }
  }

  @override
  bool shouldRepaint(covariant _SharedCacheSegmentedBarPainter oldDelegate) =>
      oldDelegate.segments != segments || oldDelegate.emptyColor != emptyColor;
}

class _SharedCacheShimmer extends StatelessWidget {
  const _SharedCacheShimmer({
    required this.width,
    required this.height,
    required this.theme,
  });

  final double width;
  final double height;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(height / 2),
      ),
    );
  }
}
