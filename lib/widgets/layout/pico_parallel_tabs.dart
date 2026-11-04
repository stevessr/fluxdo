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
  });

  final SelectedTopicState selected;
  final ValueChanged<int> onActivate;
  final ValueChanged<int> onClose;

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.android ||
        MediaQuery.orientationOf(context) != Orientation.landscape ||
        selected.stack.isEmpty) {
      return const SizedBox.shrink();
    }
    return FutureBuilder<PicoVrCapabilities>(
      future: PicoVrService.instance.capabilities,
      builder: (context, snapshot) {
        if (snapshot.data?.isPico != true) {
          return const SizedBox.shrink();
        }
        final colors = Theme.of(context).colorScheme;
        final chinese = Localizations.localeOf(context).languageCode == 'zh';
        return Container(
          key: const ValueKey('pico-parallel-tabs'),
          height: 48,
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border(
              bottom: BorderSide(color: colors.outlineVariant),
            ),
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
              Expanded(
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  itemCount: selected.stack.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 6),
                  itemBuilder: (context, index) {
                    final entry = selected.stack[index];
                    final active = index == selected.stack.length - 1;
                    final label = switch (entry.kind) {
                      PaneKind.topic =>
                        entry.initialTitle?.trim().isNotEmpty == true
                            ? entry.initialTitle!
                            : (chinese
                                ? '话题 #${entry.topicId}'
                                : 'Topic #${entry.topicId}'),
                      PaneKind.profile => '@${entry.username}',
                      PaneKind.settings => chinese ? '设置' : 'Settings',
                    };
                    return Center(
                      child: InputChip(
                        key: ValueKey('pico-pane-tab-$index'),
                        selected: active,
                        showCheckmark: false,
                        tooltip: label,
                        label: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 180),
                          child: Text(
                            label,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                        onPressed: () => onActivate(index),
                        onDeleted: () => onClose(index),
                        deleteButtonTooltipMessage: chinese
                            ? '关闭标签'
                            : 'Close tab',
                        visualDensity: VisualDensity.compact,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
