import 'package:flutter/material.dart';

/// Shared navigation for public site information and policy documents.
class SiteInfoTabs extends StatelessWidget {
  const SiteInfoTabs({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  /// 0 = About, 1 = Guidelines, 2 = Terms, 3 = Privacy.
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final labels = zh
        ? const ['关于', '准则', '服务条款', '隐私']
        : const ['About', 'Guidelines', 'Terms', 'Privacy'];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var index = 0; index < labels.length; index++) ...[
            if (index > 0) const SizedBox(width: 8),
            ChoiceChip(
              label: Text(labels[index]),
              selected: index == selected,
              onSelected: (_) {
                if (index != selected) onSelected(index);
              },
            ),
          ],
        ],
      ),
    );
  }
}
