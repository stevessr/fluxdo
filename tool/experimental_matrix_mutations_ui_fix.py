from pathlib import Path
import re


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text()
    if old not in text:
        raise SystemExit(f'anchor not found in {path}: {old[:120]!r}')
    file.write_text(text.replace(old, new, 1))


def replace_method(path: str, method_name: str, next_method: str, replacement: str) -> None:
    file = Path(path)
    text = file.read_text()
    pattern = rf"  Future<void> {re.escape(method_name)}\(MatrixMessage message\) async \{{.*?(?=  Future<void> {re.escape(next_method)}\(MatrixMessage message\) async \{{)"
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.S)
    if count != 1:
        raise SystemExit(f'failed to replace {method_name} in {path}: {count}')
    file.write_text(updated)


room_edit = '''  Future<void> _editMessage(MatrixMessage message) async {
    if (!_canEditMessage(message)) return;
    var draft = message.body;
    try {
      final replacement = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('编辑消息'),
          content: TextFormField(
            initialValue: message.body,
            autofocus: true,
            minLines: 1,
            maxLines: 8,
            onChanged: (value) => draft = value,
            decoration: const InputDecoration(
              hintText: '新的消息内容',
              border: OutlineInputBorder(),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(draft.trim()),
              child: const Text('保存'),
            ),
          ],
        ),
      );
      if (!mounted || replacement == null || replacement.isEmpty) return;
      if (replacement == message.body.trim()) return;
      await widget.client.editText(
        widget.room.roomId,
        message.eventId,
        replacement,
      );
      await _loadLatest(
        showSpinner: false,
        scrollToBottom: false,
        preservePaginationCursor: true,
      );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

'''

thread_edit = '''  Future<void> _editMessage(MatrixMessage message) async {
    if (!_canEditMessage(message)) return;
    var draft = message.body;
    try {
      final replacement = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('编辑消息'),
          content: TextFormField(
            initialValue: message.body,
            autofocus: true,
            minLines: 1,
            maxLines: 8,
            onChanged: (value) => draft = value,
            decoration: const InputDecoration(
              hintText: '新的消息内容',
              border: OutlineInputBorder(),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(draft.trim()),
              child: const Text('保存'),
            ),
          ],
        ),
      );
      if (!mounted || replacement == null || replacement.isEmpty) return;
      if (replacement == message.body.trim()) return;
      await widget.client.editText(
        widget.room.roomId,
        message.eventId,
        replacement,
      );
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

'''

replace_method(
    'lib/pages/chat/matrix_room_page.dart',
    '_editMessage',
    '_redactMessage',
    room_edit,
)
replace_method(
    'lib/pages/chat/matrix_thread_page.dart',
    '_editMessage',
    '_redactMessage',
    thread_edit,
)

replace_once(
    'lib/pages/chat/matrix_room_page.dart',
    '''    final action = await showModalBottomSheet<_MessageAction>(
      context: context,
      showDragHandle: true,
''',
    '''    final action = await showModalBottomSheet<_MessageAction>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
''',
)
replace_once(
    'lib/pages/chat/matrix_thread_page.dart',
    '''    final action = await showModalBottomSheet<_ThreadMessageAction>(
      context: context,
      showDragHandle: true,
''',
    '''    final action = await showModalBottomSheet<_ThreadMessageAction>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
''',
)

for path in (
    'test/pages/chat/matrix_room_page_test.dart',
    'test/pages/chat/matrix_thread_page_test.dart',
):
    replace_once(
        path,
        'matching: find.byType(TextField),',
        'matching: find.byType(TextFormField),',
    )

print('Matrix mutation UI lifecycle fix applied successfully')
