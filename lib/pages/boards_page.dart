import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/board.dart';
import '../models/mention_user.dart';
import '../models/topic.dart';
import '../pages/topic_detail_page/topic_detail_page.dart';
import '../providers/core_providers.dart';
import '../services/preloaded_data_service.dart';
import '../services/toast_service.dart';
import '../utils/url_helper.dart';
import '../widgets/common/relative_time_text.dart';
import '../widgets/common/smart_avatar.dart';
import '../widgets/topic/assign_sheet.dart';
import '../widgets/topic/topic_preview_dialog.dart';

/// Discourse Boards 看板列表。
class BoardsPage extends ConsumerStatefulWidget {
  const BoardsPage({super.key, this.isActive = true});

  final bool isActive;

  @override
  ConsumerState<BoardsPage> createState() => _BoardsPageState();
}

class _BoardsPageState extends ConsumerState<BoardsPage> {
  late Future<List<DiscourseBoard>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<DiscourseBoard>> _load() =>
      ref.read(discourseServiceProvider).getBoards();

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    final zh = _isZh(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(zh ? '看板' : 'Boards'),
        actions: [
          IconButton(
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
            tooltip: zh ? '刷新' : 'Refresh',
          ),
        ],
      ),
      body: FutureBuilder<List<DiscourseBoard>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _BoardsErrorView(error: snapshot.error, onRetry: _reload);
          }
          final boards = snapshot.data ?? const [];
          if (boards.isEmpty) {
            return _EmptyBoardsView(onRetry: _reload);
          }
          return RefreshIndicator(
            onRefresh: () async {
              final next = _load();
              setState(() => _future = next);
              await next;
            },
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              itemCount: boards.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final board = boards[index];
                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    leading: const Icon(Icons.view_kanban_outlined),
                    title: Text(board.displayName),
                    subtitle: Text(
                      zh
                          ? '${board.columns.length} 个分栏'
                          : '${board.columns.length} columns',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      final changed = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (_) => BoardDetailPage(
                            boardId: board.id,
                            initialName: board.displayName,
                          ),
                        ),
                      );
                      if (changed == true && mounted) _reload();
                    },
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// 单个看板详情，也用于 Boards 深链。
class BoardDetailPage extends ConsumerStatefulWidget {
  const BoardDetailPage({
    super.key,
    required this.boardId,
    this.initialName,
    this.initialCardId,
  });

  final int boardId;
  final String? initialName;
  final int? initialCardId;

  @override
  ConsumerState<BoardDetailPage> createState() => _BoardDetailPageState();
}

class _BoardDetailPageState extends ConsumerState<BoardDetailPage> {
  DiscourseBoard? _board;
  Object? _error;
  bool _loading = true;
  bool _initialCardHandled = false;

  @override
  void initState() {
    super.initState();
    _loadBoard();
  }

  Future<void> _loadBoard({bool showLoading = true}) async {
    if (showLoading && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final board = await ref
          .read(discourseServiceProvider)
          .getBoard(widget.boardId);
      if (!mounted) return;
      setState(() {
        _board = board;
        _loading = false;
        _error = null;
      });
      _openInitialCardIfNeeded(board);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  void _openInitialCardIfNeeded(DiscourseBoard board) {
    final cardId = widget.initialCardId;
    if (cardId == null || _initialCardHandled) return;
    BoardCard? target;
    for (final column in board.columns) {
      for (final card in column.cards) {
        if (card.id == cardId) {
          target = card;
          break;
        }
      }
      if (target != null) break;
    }
    _initialCardHandled = true;
    if (target == null) return;
    final card = target;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openCard(card);
    });
  }

  Future<void> _openCard(BoardCard card) async {
    final service = ref.read(discourseServiceProvider);
    unawaited(
      service
          .recordBoardCardView(boardId: widget.boardId, cardId: card.id)
          .catchError((_) {}),
    );

    if (card.isTopic) {
      final topic = _topicFromBoardTopic(card.topic!);
      await TopicPreviewDialog.show(
        context,
        topic: topic,
        onOpen: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  TopicDetailPage(topicId: topic.id, initialTitle: topic.title),
            ),
          );
        },
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _FloaterDetailSheet(card: card),
    );
  }

  bool _canAssign(DiscourseBoard board, BoardColumn column, BoardCard card) {
    if (board.archived || column.isResolvedLike) return false;
    if (!PreloadedDataService().assignEnabled) return false;
    final user = ref.read(currentUserProvider).value;
    if (user?.canAssign != true) return false;
    if (card.isTopic && card.topic!.closed) return false;

    // 官方 Boards：topic 走 discourse-assign，不要求 board.can_write；
    // floater 的负责人保存在卡片本身，因此必须有 Board 写权限。
    return card.isTopic || board.canWrite;
  }

  Future<void> _assign(
    DiscourseBoard board,
    BoardColumn column,
    BoardCard card,
  ) async {
    if (!_canAssign(board, column, card)) return;

    if (card.isTopic) {
      await showAssignSheet(context, ref, topicId: card.topic!.id);
      if (mounted) await _loadBoard(showLoading: false);
      return;
    }

    final selection = await showDialog<_AssigneeSelection>(
      context: context,
      builder: (_) =>
          _BoardAssigneeDialog(initialUsername: card.assignedTo?.username),
    );
    if (selection == null) return;

    try {
      await ref
          .read(discourseServiceProvider)
          .updateBoardCardAssignee(
            boardId: board.id,
            cardId: card.id,
            assignedToName: selection.username,
          );
      if (!mounted) return;
      ToastService.showSuccess(selection.username == null ? '已取消指定' : '已更新负责人');
      await _loadBoard(showLoading: false);
    } catch (e) {
      ToastService.showError('操作失败: $e');
    }
  }

  Future<void> _addColumn(DiscourseBoard board) async {
    if (!board.canManage || board.archived) return;
    final controller = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_isZh(context) ? '添加分栏' : 'Add column'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: _isZh(context) ? '分栏名称' : 'Column title',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(_isZh(context) ? '取消' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) Navigator.pop(dialogContext, value);
            },
            child: Text(_isZh(context) ? '添加' : 'Add'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (title == null || !mounted) return;
    try {
      await ref.read(discourseServiceProvider).createBoardColumn(board.id, {
        'title': title,
      });
      if (mounted) await _loadBoard(showLoading: false);
    } catch (e) {
      ToastService.showError('操作失败: $e');
    }
  }

  Future<void> _addCard(DiscourseBoard board, BoardColumn column) async {
    if (!board.canWrite || board.archived) return;
    final result = await showDialog<({String title, String notes})>(
      context: context,
      builder: (_) => const _BoardCardEditorDialog(),
    );
    if (result == null || !mounted) return;
    try {
      await ref
          .read(discourseServiceProvider)
          .createBoardCard(
            board.id,
            card: {
              'column_id': column.id,
              'title': result.title,
              if (result.notes.isNotEmpty) 'notes': result.notes,
            },
          );
      if (mounted) await _loadBoard(showLoading: false);
    } catch (e) {
      ToastService.showError('操作失败: $e');
    }
  }

  Future<void> _moveCard(DiscourseBoard board, BoardCard card) async {
    if (!board.canWrite || board.archived || board.columns.length < 2) return;
    final destination = await showDialog<BoardColumn>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(_isZh(context) ? '移动到分栏' : 'Move to column'),
        children: [
          for (final column in board.columns)
            if (column.id != card.columnId)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(dialogContext, column),
                child: Text(column.displayTitle),
              ),
        ],
      ),
    );
    if (destination == null || !mounted) return;
    try {
      await ref.read(discourseServiceProvider).updateBoardCard(
        board.id,
        card.id,
        {'column_id': destination.id},
      );
      if (mounted) await _loadBoard(showLoading: false);
    } catch (e) {
      ToastService.showError('操作失败: $e');
    }
  }

  Future<void> _deleteCard(DiscourseBoard board, BoardCard card) async {
    if (!board.canWrite || board.archived) return;
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(_isZh(context) ? '删除卡片' : 'Delete card'),
            content: Text(
              _isZh(context)
                  ? '确定删除“${card.displayTitle}”吗？'
                  : 'Delete “${card.displayTitle}”?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(_isZh(context) ? '取消' : 'Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(_isZh(context) ? '删除' : 'Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    try {
      await ref
          .read(discourseServiceProvider)
          .deleteBoardCard(board.id, card.id);
      if (mounted) await _loadBoard(showLoading: false);
    } catch (e) {
      ToastService.showError('操作失败: $e');
    }
  }

  Future<void> _clearColumn(DiscourseBoard board, BoardColumn column) async {
    if (!board.canManage || board.archived || column.cards.isEmpty) return;
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(_isZh(context) ? '清空分栏' : 'Clear column'),
            content: Text(
              _isZh(context)
                  ? '确定删除“${column.displayTitle}”中的全部卡片吗？'
                  : 'Delete all cards in “${column.displayTitle}”?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(_isZh(context) ? '取消' : 'Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(_isZh(context) ? '清空' : 'Clear'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    try {
      await ref
          .read(discourseServiceProvider)
          .clearBoardColumn(board.id, column.id);
      if (mounted) await _loadBoard(showLoading: false);
    } catch (e) {
      ToastService.showError('操作失败: $e');
    }
  }

  Future<void> _deleteColumn(DiscourseBoard board, BoardColumn column) async {
    if (!board.canManage || board.archived) return;
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(_isZh(context) ? '删除分栏' : 'Delete column'),
            content: Text(
              _isZh(context)
                  ? '确定删除分栏“${column.displayTitle}”吗？'
                  : 'Delete column “${column.displayTitle}”?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(_isZh(context) ? '取消' : 'Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(_isZh(context) ? '删除' : 'Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    try {
      await ref
          .read(discourseServiceProvider)
          .deleteBoardColumn(board.id, column.id);
      if (mounted) await _loadBoard(showLoading: false);
    } catch (e) {
      ToastService.showError('操作失败: $e');
    }
  }

  Future<void> _toggleBoardArchived(DiscourseBoard board) async {
    if (!board.canManage) return;
    try {
      final service = ref.read(discourseServiceProvider);
      if (board.archived) {
        await service.unarchiveBoard(board.id);
      } else {
        await service.archiveBoard(board.id);
      }
      if (mounted) await _loadBoard(showLoading: false);
    } catch (e) {
      ToastService.showError('操作失败: $e');
    }
  }

  Future<void> _deleteBoard(DiscourseBoard board) async {
    if (!board.canManage) return;
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(_isZh(context) ? '删除看板' : 'Delete board'),
            content: Text(
              _isZh(context)
                  ? '确定永久删除“${board.displayName}”吗？'
                  : 'Permanently delete “${board.displayName}”?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(_isZh(context) ? '取消' : 'Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(_isZh(context) ? '删除' : 'Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    try {
      await ref.read(discourseServiceProvider).deleteBoard(board.id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      ToastService.showError('操作失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final board = _board;
    final title = board?.displayName ?? widget.initialName ?? 'Boards';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (board != null && board.canManage)
            PopupMenuButton<String>(
              tooltip: _isZh(context) ? '看板管理' : 'Board management',
              onSelected: (value) {
                switch (value) {
                  case 'add_column':
                    _addColumn(board);
                  case 'archive':
                    _toggleBoardArchived(board);
                  case 'delete':
                    _deleteBoard(board);
                }
              },
              itemBuilder: (_) => [
                if (!board.archived)
                  PopupMenuItem(
                    value: 'add_column',
                    child: Text(_isZh(context) ? '添加分栏' : 'Add column'),
                  ),
                PopupMenuItem(
                  value: 'archive',
                  child: Text(
                    board.archived
                        ? (_isZh(context) ? '取消归档' : 'Unarchive')
                        : (_isZh(context) ? '归档看板' : 'Archive board'),
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Text(_isZh(context) ? '删除看板' : 'Delete board'),
                ),
              ],
            ),
          IconButton(
            onPressed: () => _loadBoard(showLoading: false),
            icon: const Icon(Icons.refresh),
            tooltip: _isZh(context) ? '刷新' : 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _BoardsErrorView(error: _error, onRetry: () => _loadBoard())
          : board == null
          ? const SizedBox.shrink()
          : _buildBoard(context, board),
    );
  }

  Widget _buildBoard(BuildContext context, DiscourseBoard board) {
    if (board.columns.isEmpty) {
      return Center(child: Text(_isZh(context) ? '这个看板还没有分栏' : 'No columns'));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final mobile = constraints.maxWidth < 700;
        final width = mobile
            ? (constraints.maxWidth - 28).clamp(280.0, 420.0)
            : 340.0;
        return RefreshIndicator(
          onRefresh: () => _loadBoard(showLoading: false),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            itemCount: board.columns.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final column = board.columns[index];
              return SizedBox(
                width: width,
                child: _BoardColumnView(
                  board: board,
                  column: column,
                  canAssign: (card) => _canAssign(board, column, card),
                  onCardTap: _openCard,
                  onAssign: (card) => _assign(board, column, card),
                  onAddCard: () => _addCard(board, column),
                  onMoveCard: (card) => _moveCard(board, card),
                  onDeleteCard: (card) => _deleteCard(board, card),
                  onClearColumn: () => _clearColumn(board, column),
                  onDeleteColumn: () => _deleteColumn(board, column),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _BoardColumnView extends StatelessWidget {
  const _BoardColumnView({
    required this.board,
    required this.column,
    required this.canAssign,
    required this.onCardTap,
    required this.onAssign,
    required this.onAddCard,
    required this.onMoveCard,
    required this.onDeleteCard,
    required this.onClearColumn,
    required this.onDeleteColumn,
  });

  final DiscourseBoard board;
  final BoardColumn column;
  final bool Function(BoardCard card) canAssign;
  final ValueChanged<BoardCard> onCardTap;
  final ValueChanged<BoardCard> onAssign;
  final VoidCallback onAddCard;
  final ValueChanged<BoardCard> onMoveCard;
  final ValueChanged<BoardCard> onDeleteCard;
  final VoidCallback onClearColumn;
  final VoidCallback onDeleteColumn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _parseHexColor(column.color) ?? theme.colorScheme.primary;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    column.displayTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '${column.cards.length}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (board.canWrite && !board.archived)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: _isZh(context) ? '添加卡片' : 'Add card',
                    onPressed: onAddCard,
                    icon: const Icon(Icons.add_rounded, size: 20),
                  ),
                if (board.canManage && !board.archived)
                  PopupMenuButton<String>(
                    tooltip: _isZh(context) ? '分栏管理' : 'Column management',
                    onSelected: (value) {
                      if (value == 'clear') onClearColumn();
                      if (value == 'delete') onDeleteColumn();
                    },
                    itemBuilder: (_) => [
                      if (column.cards.isNotEmpty)
                        PopupMenuItem(
                          value: 'clear',
                          child: Text(_isZh(context) ? '清空分栏' : 'Clear column'),
                        ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(_isZh(context) ? '删除分栏' : 'Delete column'),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          Expanded(
            child: column.cards.isEmpty
                ? Center(
                    child: Text(
                      _isZh(context) ? '暂无卡片' : 'No cards',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                    itemCount: column.cards.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final card = column.cards[index];
                      return _BoardCardTile(
                        board: board,
                        card: card,
                        canAssign: canAssign(card),
                        canManageCard: board.canWrite && !board.archived,
                        onTap: () => onCardTap(card),
                        onAssign: () => onAssign(card),
                        onMove: () => onMoveCard(card),
                        onDelete: () => onDeleteCard(card),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _BoardCardTile extends StatelessWidget {
  const _BoardCardTile({
    required this.board,
    required this.card,
    required this.canAssign,
    required this.canManageCard,
    required this.onTap,
    required this.onAssign,
    required this.onMove,
    required this.onDelete,
  });

  final DiscourseBoard board;
  final BoardCard card;
  final bool canAssign;
  final bool canManageCard;
  final VoidCallback onTap;
  final VoidCallback onAssign;
  final VoidCallback onMove;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final topic = card.topic;
    final users = card.assignedUsers;
    final group = card.assignedGroupName;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 11, 10, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (topic?.closed == true) ...[
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(Icons.lock_outline, size: 16),
                    ),
                    const SizedBox(width: 5),
                  ],
                  Expanded(
                    child: Text(
                      card.displayTitle,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (canAssign)
                    IconButton(
                      onPressed: onAssign,
                      icon: Icon(
                        users.isEmpty && group == null
                            ? Icons.person_add_alt_1_outlined
                            : Icons.manage_accounts_outlined,
                        size: 20,
                      ),
                      visualDensity: VisualDensity.compact,
                      tooltip: _isZh(context) ? '指定负责人' : 'Assign',
                    ),
                  if (canManageCard)
                    PopupMenuButton<String>(
                      tooltip: _isZh(context) ? '卡片管理' : 'Card management',
                      onSelected: (value) {
                        if (value == 'move') onMove();
                        if (value == 'delete') onDelete();
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'move',
                          child: Text(_isZh(context) ? '移动卡片' : 'Move card'),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text(_isZh(context) ? '删除卡片' : 'Delete card'),
                        ),
                      ],
                    ),
                ],
              ),
              if (card.displayTags.isNotEmpty && board.showTags) ...[
                const SizedBox(height: 7),
                Wrap(
                  spacing: 5,
                  runSpacing: 4,
                  children: card.displayTags
                      .take(4)
                      .map(
                        (tag) => Chip(
                          label: Text(tag.name),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          labelStyle: theme.textTheme.labelSmall,
                        ),
                      )
                      .toList(),
                ),
              ],
              if (board.showTopicThumbnail &&
                  card.topic?.imageUrl?.isNotEmpty == true) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    UrlHelper.resolveUrlWithCdn(card.topic!.imageUrl!),
                    height: 132,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  if (users.isNotEmpty) ...[
                    _AssigneeAvatars(users: users),
                    const SizedBox(width: 7),
                  ] else if (group != null) ...[
                    const Icon(Icons.group_outlined, size: 16),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        group,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall,
                      ),
                    ),
                    const SizedBox(width: 7),
                  ],
                  if (card.isTopic && topic != null) ...[
                    const Icon(Icons.chat_bubble_outline, size: 14),
                    const SizedBox(width: 3),
                    Text(
                      '${(topic.postsCount - 1).clamp(0, 999999)}',
                      style: theme.textTheme.labelSmall,
                    ),
                    const SizedBox(width: 8),
                  ],
                  const Spacer(),
                  RelativeTimeText(
                    dateTime: card.activityAt,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AssigneeAvatars extends StatelessWidget {
  const _AssigneeAvatars({required this.users});

  final List<BoardAssignee> users;

  @override
  Widget build(BuildContext context) {
    final shown = users.take(3).toList();
    return SizedBox(
      width: 22.0 + (shown.length - 1) * 14.0,
      height: 22,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * 14.0,
              child: SmartAvatar(
                imageUrl: _boardAssigneeAvatarUrl(shown[i], size: 48),
                fallbackText: shown[i].displayName,
                radius: 11,
              ),
            ),
        ],
      ),
    );
  }
}

class _FloaterDetailSheet extends StatelessWidget {
  const _FloaterDetailSheet({required this.card});

  final BoardCard card;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final notes = card.notes?.trim() ?? '';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              card.displayTitle,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (card.assignedUsers.isNotEmpty ||
                card.assignedGroupName != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.person_outline, size: 18),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      card.assignedUsers.isNotEmpty
                          ? card.assignedUsers
                                .map((e) => e.displayName)
                                .join(', ')
                          : card.assignedGroupName!,
                    ),
                  ),
                ],
              ),
            ],
            if (notes.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(notes, style: theme.textTheme.bodyMedium),
            ],
          ],
        ),
      ),
    );
  }
}

class _BoardCardEditorDialog extends StatefulWidget {
  const _BoardCardEditorDialog();

  @override
  State<_BoardCardEditorDialog> createState() => _BoardCardEditorDialogState();
}

class _BoardCardEditorDialogState extends State<_BoardCardEditorDialog> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final zh = _isZh(context);
    return AlertDialog(
      title: Text(zh ? '添加卡片' : 'Add card'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: zh ? '标题' : 'Title',
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              minLines: 2,
              maxLines: 5,
              decoration: InputDecoration(
                labelText: zh ? '备注（可选）' : 'Notes (optional)',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(zh ? '取消' : 'Cancel'),
        ),
        FilledButton(
          onPressed: _titleController.text.trim().isEmpty
              ? null
              : () => Navigator.pop(context, (
                  title: _titleController.text.trim(),
                  notes: _notesController.text.trim(),
                )),
          child: Text(zh ? '添加' : 'Add'),
        ),
      ],
    );
  }
}

class _AssigneeSelection {
  const _AssigneeSelection(this.username);
  final String? username;
}

class _BoardAssigneeDialog extends ConsumerStatefulWidget {
  const _BoardAssigneeDialog({this.initialUsername});

  final String? initialUsername;

  @override
  ConsumerState<_BoardAssigneeDialog> createState() =>
      _BoardAssigneeDialogState();
}

class _BoardAssigneeDialogState extends ConsumerState<_BoardAssigneeDialog> {
  late final TextEditingController _controller;
  Timer? _debounce;
  List<MentionUser> _results = const [];
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialUsername ?? '');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final term = value.trim();
    if (term.isEmpty) {
      setState(() => _results = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 250), () => _search(term));
  }

  Future<void> _search(String term) async {
    if (mounted) setState(() => _searching = true);
    final result = await ref
        .read(discourseServiceProvider)
        .searchUsers(term: term, includeGroups: false, limit: 8);
    if (!mounted || _controller.text.trim() != term) return;
    setState(() {
      _searching = false;
      _results = result.users;
    });
  }

  @override
  Widget build(BuildContext context) {
    final zh = _isZh(context);
    return AlertDialog(
      title: Text(zh ? '指定负责人' : 'Assign user'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              onChanged: _onChanged,
              decoration: InputDecoration(
                hintText: zh ? '搜索用户名' : 'Search username',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(13),
                        child: SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
              ),
            ),
            if (_results.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _results.length,
                  itemBuilder: (context, index) {
                    final user = _results[index];
                    final hasName = user.name?.trim().isNotEmpty == true;
                    return ListTile(
                      leading: SmartAvatar(
                        imageUrl: user.getAvatarUrl('', size: 48),
                        fallbackText: user.username,
                        radius: 18,
                      ),
                      title: Text(hasName ? user.name! : user.username),
                      subtitle: hasName ? Text('@${user.username}') : null,
                      onTap: () {
                        _controller.text = user.username;
                        setState(() => _results = const []);
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      actions: [
        if (widget.initialUsername != null)
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(const _AssigneeSelection(null)),
            child: Text(zh ? '取消指定' : 'Unassign'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(zh ? '取消' : 'Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final name = _controller.text.trim();
            if (name.isEmpty) return;
            Navigator.of(context).pop(_AssigneeSelection(name));
          },
          child: Text(zh ? '保存' : 'Save'),
        ),
      ],
    );
  }
}

class _BoardsErrorView extends StatelessWidget {
  const _BoardsErrorView({required this.error, required this.onRetry});

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final zh = _isZh(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 40),
            const SizedBox(height: 12),
            Text(zh ? '看板加载失败' : 'Failed to load boards'),
            const SizedBox(height: 6),
            Text(
              '$error',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: onRetry,
              child: Text(zh ? '重试' : 'Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyBoardsView extends StatelessWidget {
  const _EmptyBoardsView({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final zh = _isZh(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.view_kanban_outlined, size: 48),
          const SizedBox(height: 12),
          Text(zh ? '暂无可见看板' : 'No visible boards'),
          TextButton(onPressed: onRetry, child: Text(zh ? '刷新' : 'Refresh')),
        ],
      ),
    );
  }
}

Color? _parseHexColor(String value) {
  final hex = value.replaceAll('#', '').trim();
  if (hex.length != 6) return null;
  final rgb = int.tryParse(hex, radix: 16);
  return rgb == null ? null : Color(0xFF000000 | rgb);
}

bool _isZh(BuildContext context) =>
    Localizations.localeOf(context).languageCode == 'zh';

Topic _topicFromBoardTopic(BoardTopic source) {
  final replyCount = source.postsCount > 0 ? source.postsCount - 1 : 0;
  return Topic.fromJson({
    'id': source.id,
    'title': source.displayTitle,
    'slug': source.slug,
    'category_id': source.categoryId,
    'posts_count': source.postsCount,
    'reply_count': replyCount,
    'views': 0,
    'like_count': 0,
    'tags': source.tags.map((tag) => tag.name).toList(),
    'last_posted_at': source.bumpedAt?.toUtc().toIso8601String(),
    'last_poster_username': source.lastPosterUsername,
    'closed': source.closed,
    'highest_post_number': source.highestPostNumber,
    'last_read_post_number': source.lastReadPostNumber,
  });
}

String? _boardAssigneeAvatarUrl(BoardAssignee assignee, {int size = 40}) {
  final template = assignee.avatarTemplate;
  if (template == null || template.isEmpty) return null;
  return UrlHelper.resolveUrlWithCdn(
    template.replaceAll('{size}', size.toString()),
  );
}
