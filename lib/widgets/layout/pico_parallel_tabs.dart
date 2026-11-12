import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../providers/selected_topic_provider.dart';
import '../../services/pico_vr_service.dart';

/// PICO's 2D Android multi-window tasks are separate from these *in-window*
/// parallel-view tabs. Keep pane identity and provider state when switching:
/// there is exactly one Flutter widget instance per tab (the filmstrip).
class PicoParallelTabs extends StatelessWidget {
  const PicoParallelTabs({
    super.key,
    required this.selected,
    required this.onActivate,
    required this.onClose,
    required this.onCloseOthers,
    required this.onCloseAll,
    this.onShowFeed,
  });

  final SelectedTopicState selected;
  final ValueChanged<int> onActivate;
  final ValueChanged<int> onClose;
  final ValueChanged<int> onCloseOthers;
  final VoidCallback onCloseAll;
  final VoidCallback? onShowFeed;

  @override
  Widget build(BuildContext context) {
    if (selected.stack.isEmpty) {
      return const SizedBox.shrink();
    }
    if (selected.tabMode) return _buildTabBar(context);
    if (defaultTargetPlatform != TargetPlatform.android ||
        MediaQuery.orientationOf(context) != Orientation.landscape) {
      return const SizedBox.shrink();
    }
    return FutureBuilder<PicoVrCapabilities>(
      future: PicoVrService.instance.capabilities,
      builder: (context, snapshot) {
        if (snapshot.data?.isPico != true) {
          return const SizedBox.shrink();
        }
        return _buildTabBar(context);
      },
    );
  }

  String _tabLabel(PaneEntry entry, bool chinese) {
    if (entry.kind == PaneKind.profile) return '@${entry.username}';
    if (entry.kind == PaneKind.settings) {
      return chinese ? '设置' : 'Settings';
    }
    final title = entry.initialTitle?.trim();
    if (title != null && title.isNotEmpty) return title;
    if (entry.isPrivateMessage) {
      return chinese ? '私信 #${entry.topicId}' : 'PM #${entry.topicId}';
    }
    return chinese ? '话题 #${entry.topicId}' : 'Topic #${entry.topicId}';
  }

  void _showTabActions(BuildContext context, int index) {
    final chinese = Localizations.localeOf(context).languageCode == 'zh';
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.tab_unselected_rounded),
              title: Text(chinese ? '关闭其他标签' : 'Close other tabs'),
              onTap: () {
                Navigator.pop(sheetContext);
                onCloseOthers(index);
              },
            ),
            ListTile(
              leading: const Icon(Icons.close_rounded),
              title: Text(chinese ? '关闭所有标签' : 'Close all tabs'),
              onTap: () {
                Navigator.pop(sheetContext);
                onCloseAll();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabBar(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final chinese = Localizations.localeOf(context).languageCode == 'zh';
    return Container(
      key: const ValueKey('pico-parallel-tabs'),
      height: 48,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Icon(
              Icons.tab_rounded,
              size: 20,
              color: colors.onSurfaceVariant,
            ),
          ),
          if (selected.tabMode && onShowFeed != null)
            IconButton(
              key: const ValueKey('unified-tabs-show-list'),
              tooltip: chinese ? '返回列表' : 'Show list',
              onPressed: onShowFeed,
              icon: const Icon(Icons.view_list_rounded),
            ),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              itemCount: selected.stack.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final entry = selected.stack[index];
                final active =
                    !selected.showingFeed &&
                    index == selected.stack.length - 1;
                final label = _tabLabel(entry, chinese);
                return Center(
                  child: Tooltip(
                    message: label,
                    child: GestureDetector(
                      onLongPress: () => _showTabActions(context, index),
                      child: InputChip(
                          key: ValueKey('pico-pane-tab-$index'),
                          selected: active,
                          showCheckmark: false,
                        label: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 180),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (entry.kind == PaneKind.topic &&
                                  entry.isPrivateMessage) ...[
                                const Icon(Icons.mail_outline_rounded, size: 15),
                                const SizedBox(width: 5),
                              ],
                              Flexible(
                                child: Text(
                                  label,
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                        onPressed: () => onActivate(index),
                        onDeleted: () => onClose(index),
                        deleteButtonTooltipMessage: chinese ? '关闭标签' : 'Close tab',
                          visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
