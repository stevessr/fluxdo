import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:app_icons/app_icons.dart';
import 'package:m3e_ui/m3e_ui.dart';

import '../../../l10n/s.dart';
import '../../../services/network/doh/custom_hosts_service.dart';
import '../../../services/network/doh/network_settings_service.dart';
import '../../../services/toast_service.dart';
import '../../../utils/dialog_utils.dart';

/// 自定义 hosts 导入卡片。
///
/// hosts 文件保持系统格式，只做导入和清除，不在应用内提供域名搜索或编辑器。
class CustomHostsCard extends StatefulWidget {
  const CustomHostsCard({super.key});

  @override
  State<CustomHostsCard> createState() => _CustomHostsCardState();
}

class _CustomHostsCardState extends State<CustomHostsCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final service = NetworkSettingsService.instance;

    return AnimatedBuilder(
      animation: service.notifier,
      builder: (context, _) {
        final settings = service.current;
        final hasHosts = settings.customHosts.isNotEmpty;
        final source = settings.customHostsSource;
        final sourceUrl = settings.customHostsSourceUrl;

        return SegmentedCardGroup(
          color: hasHosts
              ? Theme.of(
                  context,
                ).colorScheme.primaryContainer.withValues(alpha: 0.3)
              : null,
          children: [
            ListTile(
              leading: Icon(
                Symbols.dns_rounded,
                color: hasHosts ? Theme.of(context).colorScheme.primary : null,
              ),
              title: Text(context.l10n.customHosts_title),
              subtitle: Text(context.l10n.customHosts_subtitle),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasHosts
                        ? context.l10n.customHosts_loaded(
                            settings.customHosts.length,
                            settings.customHosts.values.fold<int>(
                              0,
                              (total, addresses) => total + addresses.length,
                            ),
                          )
                        : context.l10n.customHosts_empty,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (source != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          sourceUrl == null
                              ? Symbols.description_rounded
                              : Symbols.link_rounded,
                          size: 16,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            context.l10n.customHosts_source(source),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ),
                        if (sourceUrl != null)
                          IconButton(
                            tooltip: context.l10n.customHosts_refresh,
                            onPressed: _busy ? null : _refresh,
                            icon: const Icon(Symbols.refresh_rounded),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: _busy ? null : _importFromUrl,
                        icon: _busy
                            ? const LoadingSpinner(size: 18)
                            : const Icon(Symbols.link_rounded),
                        label: Text(context.l10n.customHosts_importUrl),
                      ),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _importFromFile,
                        icon: const Icon(Symbols.folder_open_rounded),
                        label: Text(context.l10n.customHosts_importFile),
                      ),
                      if (hasHosts)
                        TextButton.icon(
                          onPressed: _busy ? null : _clear,
                          icon: const Icon(Symbols.clear_rounded),
                          label: Text(context.l10n.customHosts_clear),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _importFromUrl() async {
    final controller = TextEditingController(
      text:
          NetworkSettingsService.instance.current.customHostsSourceUrl ??
          defaultCustomHostsUrl,
    );
    final url = await showAppDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.l10n.customHosts_urlTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            labelText: dialogContext.l10n.customHosts_urlHint,
          ),
          minLines: 1,
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(dialogContext.l10n.common_cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: Text(dialogContext.l10n.common_import),
          ),
        ],
      ),
    );
    controller.dispose();

    if (url == null || url.trim().isEmpty || !mounted) return;
    await _runImport(
      () => NetworkSettingsService.instance.importCustomHostsFromUrl(url),
    );
  }

  Future<void> _importFromFile() async {
    await _runImport(() async {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return null;

      final file = result.files.single;
      final content = file.bytes != null
          ? CustomHostsService.decodeBytes(file.bytes!)
          : file.path != null
          ? await CustomHostsService.readFile(file.path!)
          : null;
      if (content == null) {
        throw const FormatException('无法读取所选文件');
      }

      final source = file.name.trim().isNotEmpty
          ? file.name.trim()
          : (file.path ?? 'hosts');
      return NetworkSettingsService.instance.importCustomHostsText(
        content,
        source: source,
      );
    });
  }

  Future<void> _refresh() async {
    await _runImport(
      () => NetworkSettingsService.instance.refreshCustomHosts(),
    );
  }

  Future<void> _runImport(
    Future<CustomHostsParseResult?> Function() action,
  ) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await action();
      if (!mounted || result == null) return;
      ToastService.showSuccess(
        context.l10n.customHosts_imported(
          result.hostCount,
          result.addressCount,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ToastService.showError(
        context.l10n.customHosts_importFailed(_errorMessage(error)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.l10n.customHosts_clearTitle),
        content: Text(dialogContext.l10n.customHosts_clearConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(dialogContext.l10n.common_cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(dialogContext.l10n.common_clear),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await NetworkSettingsService.instance.clearCustomHosts();
      if (mounted) {
        ToastService.showSuccess(context.l10n.customHosts_cleared);
      }
    } catch (error) {
      if (mounted) {
        ToastService.showError(
          context.l10n.customHosts_importFailed(_errorMessage(error)),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _errorMessage(Object error) {
    if (error is FormatException) return error.message.toString();
    return error.toString().replaceFirst(RegExp(r'^\w+Exception: '), '');
  }
}
