import 'dart:convert';

/// Normalizes the legacy multi-account registry before it reaches
/// [AccountManager].
///
/// Older builds could leave more than one registry entry for the same
/// Discourse username. AccountManager only refreshed the first exact match,
/// so the remaining copies stayed visible forever. Discourse usernames are
/// case-insensitive, therefore whitespace/case-only variants must also share
/// one identity.
class MultiAccountRegistryNormalizer {
  const MultiAccountRegistryNormalizer._();

  static const String registryKey = 'multi_account_registry';

  /// Returns [raw] unchanged when it is not a valid registry payload. This
  /// deliberately preserves AccountManager's existing malformed-registry
  /// recovery behavior instead of silently accepting corrupt data here.
  static String normalize(String raw) {
    if (raw.isEmpty) return raw;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return raw;

      final entriesByIdentity = <String, Map<String, dynamic>>{};
      final identityOrder = <String>[];
      var changed = false;

      for (final item in decoded) {
        if (item is! Map) return raw;
        final entry = Map<String, dynamic>.from(item);
        final rawUsername = entry['username'];
        if (rawUsername is! String) return raw;

        final username = rawUsername.trim();
        if (username.isEmpty) return raw;
        if (username != rawUsername) changed = true;

        final identity = username.toLowerCase();
        final normalizedEntry = <String, dynamic>{
          ...entry,
          'username': username,
        };
        final previous = entriesByIdentity[identity];
        if (previous == null) {
          entriesByIdentity[identity] = normalizedEntry;
          identityOrder.add(identity);
          continue;
        }

        changed = true;
        if (_savedAt(normalizedEntry).isAfter(_savedAt(previous))) {
          entriesByIdentity[identity] = normalizedEntry;
        }
      }

      if (!changed) return raw;
      return jsonEncode(
        identityOrder.map((identity) => entriesByIdentity[identity]!).toList(),
      );
    } catch (_) {
      return raw;
    }
  }

  static DateTime _savedAt(Map<String, dynamic> entry) {
    final value = entry['saved_at'];
    if (value is! String) return DateTime.fromMillisecondsSinceEpoch(0);
    return DateTime.tryParse(value) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }
}
