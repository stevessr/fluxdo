from pathlib import Path
import re

path = Path("lib/widgets/post/reply_sheet.dart")
s = path.read_text()


def replace_once(old: str, new: str) -> None:
    global s
    count = s.count(old)
    if count != 1:
        raise SystemExit(f"expected one match, got {count}: {old[:120]!r}")
    s = s.replace(old, new, 1)


replace_once(
    "  String _currentComposerActionLabel(BuildContext context) {\n",
    "  void _switchSourceToRichComposer() {\n"
    "    if (!mounted) return;\n"
    "    setState(() => _richFallback = false);\n"
    "  }\n\n"
    "  String _currentComposerActionLabel(BuildContext context) {\n",
)

pattern = re.compile(
    r"                                onSwitchToRich: ref\n"
    r"                                        \.watch\(preferencesProvider\)\n"
    r"                                        \.useRichComposer\n"
    r"                                    \? \(\) \{\n"
    r".*?"
    r"                                    : null,\n",
    re.DOTALL,
)
replacement = (
    "                                onSwitchToRich: ref\n"
    "                                        .watch(preferencesProvider)\n"
    "                                        .useRichComposer\n"
    "                                    ? _switchSourceToRichComposer\n"
    "                                    : null,\n"
)
s, count = pattern.subn(replacement, s, count=1)
if count != 1:
    raise SystemExit(f"expected one onSwitchToRich block, got {count}")

path.write_text(s)
