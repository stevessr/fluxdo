import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/board.dart';
import '../../providers/core_providers.dart';
import '../../services/toast_service.dart';
import '../common/app_bottom_sheet.dart';

/// Use the Boards plugin's ACL-checked endpoints to attach a topic to a column.
Future<void> showAddTopicToBoardSheet(BuildContext context, {required int topicId}) async {
  await AppBottomSheet.show<void>(
    context: context,
    title: Localizations.localeOf(context).languageCode == 'zh'
        ? '添加到看板' : 'Add to board',
    builder: (_) => _AddTopicToBoardSheet(topicId: topicId),
  );
}

/// available.json 使用 BasicBoardSerializer，不带 can_write/can_manage。
/// 服务端已根据 edit/manage ACL 筛选；不能再检查缺失的权限字段。
List<DiscourseBoard> availableTopicBoards(List<DiscourseBoard> boards) =>
    boards.where((board) => !board.archived).toList(growable: false);

/// 复用既有话题卡片，避免在其他分栏意外创建重复条目。
BoardCard? existingTopicBoardCard(DiscourseBoard board, int topicId) {
  for (final column in board.columns) {
    for (final card in column.cards) {
      if (card.cardType == 'topic' && card.topicId == topicId) return card;
    }
  }
  return null;
}

class _AddTopicToBoardSheet extends ConsumerStatefulWidget {
  const _AddTopicToBoardSheet({required this.topicId});
  final int topicId;

  @override
  ConsumerState<_AddTopicToBoardSheet> createState() => _AddTopicToBoardSheetState();
}

class _AddTopicToBoardSheetState extends ConsumerState<_AddTopicToBoardSheet> {
  late Future<List<DiscourseBoard>> _boards;
  DiscourseBoard? _board;
  bool _busy = false;

  bool get _zh => Localizations.localeOf(context).languageCode == 'zh';

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _boards = ref.read(discourseServiceProvider).getAvailableBoards(topicId: widget.topicId);
  }

  Future<void> _select(DiscourseBoard summary) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      // Available boards contain summaries, not necessarily their columns.
      final board = await ref.read(discourseServiceProvider).getBoard(summary.id);
      if (!mounted) return;
      if (board.archived || (!board.canWrite && !board.canManage)) {
        ToastService.showError(_zh ? '没有看板编辑权限' : 'No board edit permission');
        return;
      }
      setState(() => _board = board);
    } catch (e) {
      if (mounted) ToastService.showError(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// null means cancelled; an empty map means no mutation of topic metadata.
  Future<Map<String, dynamic>?> _resolveConstraints(
    DiscourseBoard board, BoardColumn column,
  ) async {
    final mismatch = await ref.read(discourseServiceProvider)
        .checkBoardConstraintMismatches(
          board.id, topicId: widget.topicId, targetColumnId: column.id,
        );
    if (mismatch['constraints_need_fixing'] != true) return <String, dynamic>{};
    final categories = (mismatch['categories_needed'] as List? ?? const [])
        .whereType<num>().map((id) => id.toInt()).toSet().toList();
    final tags = (mismatch['tags_needed'] as List? ?? const [])
        .map((tag) => tag.toString()).where((tag) => tag.isNotEmpty)
        .toSet().toList();
    if (categories.isEmpty && tags.isEmpty) return <String, dynamic>{};
    if (!mounted) return null;

    int? category = categories.length == 1 ? categories.first : null;
    final selectedTags = <String>{if (tags.length == 1) tags.first};
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, update) => AlertDialog(
          title: Text(_zh ? '修正话题约束' : 'Fix topic constraints'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_zh ? '添加前需要修改话题的分类或标签，请选择：'
                    : 'Adding this topic requires a category or tag change:'),
                if (categories.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(_zh ? '分类' : 'Category'),
                  Wrap(spacing: 8, children: [
                    for (final id in categories)
                      ChoiceChip(label: Text('#$id'), selected: category == id,
                        onSelected: (selected) {
                          if (selected) update(() => category = id);
                        }),
                  ]),
                ],
                if (tags.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(_zh ? '标签' : 'Tags'),
                  Wrap(spacing: 8, children: [
                    for (final tag in tags)
                      FilterChip(label: Text(tag), selected: selectedTags.contains(tag),
                        onSelected: (selected) => update(() {
                          if (selected) {
                            selectedTags.add(tag);
                          } else {
                            selectedTags.remove(tag);
                          }
                        })),
                  ]),
                ],
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext),
                child: Text(_zh ? '取消' : 'Cancel')),
            FilledButton(
              onPressed: (categories.isEmpty || category != null) &&
                    (tags.isEmpty || selectedTags.isNotEmpty)
                  ? () => Navigator.pop(dialogContext, <String, dynamic>{
                      if (categories.isNotEmpty) 'category_id': category,
                      if (tags.isNotEmpty) 'tag_names': selectedTags.toList(),
                    }) : null,
              child: Text(_zh ? '应用并继续' : 'Apply & continue'),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirm(DiscourseBoard board, BoardColumn column) async {
    if (!board.requireConfirmation) return true;
    final destination = board.displayName + ' / ' + column.displayTitle;
    return await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_zh ? '确认添加到看板' : 'Confirm board action'),
        content: Text((_zh ? '将话题添加或移动到 ' : 'Add or move this topic to ') + destination + '?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_zh ? '取消' : 'Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_zh ? '确认' : 'Confirm')),
        ],
      ),
    ) ?? false;
  }

  Future<void> _submit(BoardColumn column) async {
    final board = _board;
    if (_busy || board == null || board.archived) return;
    final existing = existingTopicBoardCard(board, widget.topicId);
    if (existing?.columnId == column.id) {
      ToastService.showSuccess(_zh ? '话题已在此分栏' : 'Topic already in this column');
      return;
    }
    setState(() => _busy = true);
    try {
      final fix = await _resolveConstraints(board, column);
      if (fix == null || !mounted) return;
      if (!await _confirm(board, column) || !mounted) return;
      final service = ref.read(discourseServiceProvider);
      if (existing != null) {
        await service.updateBoardCard(board.id, existing.id,
          {'column_id': column.id}, constraintFix: fix.isEmpty ? null : fix);
      } else {
        await service.createBoardCard(board.id,
          card: {'topic_id': widget.topicId, 'column_id': column.id},
          constraintFix: fix.isEmpty ? null : fix);
      }
      if (!mounted) return;
      ToastService.showSuccess(_zh ? '已添加到看板' : 'Added to board');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) ToastService.showError(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final board = _board;
    return SizedBox(
      width: 480,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (_busy) const LinearProgressIndicator(),
        if (board != null) ...[
          ListTile(
            leading: const Icon(Icons.arrow_back_rounded),
            title: Text(board.displayName),
            subtitle: Text(_zh ? '选择分栏' : 'Choose a column'),
            onTap: _busy ? null : () => setState(() => _board = null),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 420),
            child: board.columns.isEmpty
                ? Padding(padding: const EdgeInsets.all(24),
                    child: Text(_zh ? '看板没有分栏' : 'Board has no columns'))
                : ListView(shrinkWrap: true, children: [
                    for (final column in board.columns)
                      ListTile(
                        leading: const Icon(Icons.view_column_outlined),
                        title: Text(column.displayTitle),
                        enabled: !_busy,
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => _submit(column),
                      ),
                  ]),
          ),
        ] else
          FutureBuilder<List<DiscourseBoard>>(
            future: _boards,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Column(mainAxisSize: MainAxisSize.min, children: [
                  Text((_zh ? '获取可用看板失败：' : 'Failed to load boards: ') +
                      snapshot.error.toString()),
                  TextButton(
                    onPressed: () => setState(_load),
                    child: Text(_zh ? '重试' : 'Retry'),
                  ),
                ]);
              }
              final available = availableTopicBoards(snapshot.data ?? const <DiscourseBoard>[]);
              if (available.isEmpty) {
                return Padding(padding: const EdgeInsets.all(24),
                  child: Text(_zh ? '没有可编辑的看板' : 'No editable boards available'));
              }
              return ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 420),
                child: ListView(shrinkWrap: true, children: [
                  for (final item in available)
                    ListTile(
                      leading: const Icon(Icons.view_kanban_outlined),
                      title: Text(item.displayName),
                      enabled: !_busy,
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => _select(item),
                    ),
                ]),
              );
            },
          ),
      ]),
    );
  }
}
