import 'package:material_ui/material_ui.dart';

import '../l10n/s.dart';
import '../settings/definitions/reading_defs.dart';
import '../widgets/settings/settings_group_page.dart';
import 'appearance_page.dart';

class ReadingSettingsPage extends StatelessWidget {
  final String? highlightId;

  const ReadingSettingsPage({super.key, this.highlightId});

  @override
  Widget build(BuildContext context) {
    if (highlightId == 'emojiRenderStyle') {
      return const AppearancePage(highlightId: 'emojiRenderStyle');
    }
    return SettingsGroupPage(
      title: context.l10n.reading_title,
      groupsBuilder: buildReadingGroups,
      highlightId: highlightId,
    );
  }
}
