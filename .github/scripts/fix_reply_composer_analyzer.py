from pathlib import Path

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

replace_once(
    """                                onSwitchToRich: ref
                                        .watch(preferencesProvider)
                                        .useRichComposer
                                    ? () {
                                        if (mounted) {
                                          setState(
                                            () => _richFallback = false,
                                          );
                                        }
                                      }
                                    : null,
""",
    """                                onSwitchToRich: ref
                                        .watch(preferencesProvider)
                                        .useRichComposer
                                    ? _switchSourceToRichComposer
                                    : null,
""",
)

path.write_text(s)
