import 'package:flutter/material.dart';

/// A shared, explicit confirmation for leaving a Discourse group.
///
/// Dismissing the dialog (including Back or tapping outside it) is cancellation.
/// Callers must only send the membership request when this returns true.
Future<bool> confirmLeaveGroup(
  BuildContext context, {
  required String groupLabel,
}) async {
  final zh = Localizations.localeOf(context).languageCode.toLowerCase() == 'zh';
  final scheme = Theme.of(context).colorScheme;

  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: Icon(Icons.logout_rounded, color: scheme.error),
          title: Text(zh ? '退出群组？' : 'Leave group?'),
          content: Text(
            zh
                ? '确定要退出「$groupLabel」吗？退出后将不再是该群组成员，能否重新加入取决于群组设置。'
                : 'Leave “$groupLabel”? You will no longer be a member. Rejoining depends on the group settings.',
          ),
          actions: [
            TextButton(
              key: const ValueKey('leave-group-cancel'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(zh ? '取消' : 'Cancel'),
            ),
            FilledButton(
              key: const ValueKey('leave-group-confirm'),
              style: FilledButton.styleFrom(
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(zh ? '确认退出' : 'Leave group'),
            ),
          ],
        ),
      ) ??
      false;
}
