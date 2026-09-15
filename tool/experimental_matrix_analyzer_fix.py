from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly one match, got {count}')
    return text.replace(old, new, 1)

room_path = Path('lib/pages/chat/matrix_room_page.dart')
room = room_path.read_text()
room = replace_once(
    room,
    "import 'matrix_thread_page.dart';\n",
    "import 'matrix_thread_page.dart' as thread_ui;\n",
    'thread UI import alias',
)
room = replace_once(
    room,
    '        builder: (_) => MatrixThreadPage(\n',
    '        builder: (_) => thread_ui.MatrixThreadPage(\n',
    'thread UI constructor alias',
)
room_path.write_text(room)

media_path = Path('lib/pages/chat/matrix_message_media_view.dart')
media = media_path.read_text()
media = replace_once(
    media,
    "import 'dart:typed_data';\n\n",
    '',
    'redundant typed_data import',
)
media_path.write_text(media)

client_path = Path('lib/services/matrix_client_service.dart')
client = client_path.read_text()
start = client.find('  static List<Map<String, dynamic>> _threadRelationsForRoot(')
end = client.find('  static String _newTransactionId()', start)
if start == -1 or end == -1 or end <= start:
    raise SystemExit('obsolete thread helper block not found')
client = client[:start] + client[end:]
client_path.write_text(client)

print('Matrix analyzer cleanup applied successfully')
