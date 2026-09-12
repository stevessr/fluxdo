import 'package:dio/dio.dart';

import 'discourse_service.dart';

extension UserPeoplePreferencesApi on DiscourseService {
  Future<List<Map<String, dynamic>>> searchPreferenceUsers(
    String query, {
    int limit = 20,
    Iterable<String> excludeUsernames = const [],
  }) async {
    final term = query.trim().replaceFirst(RegExp(r'^@'), '');
    if (term.isEmpty) return const [];
    try {
      final response = await dio.get(
        '/u/search/users',
        queryParameters: <String, dynamic>{
          'term': term,
          'include_groups': false,
          'include_mentionable_groups': false,
          'include_messageable_groups': false,
          'include_staged_users': false,
          'limit': limit,
        },
      );
      if (response.data is! Map) return const [];
      final data = Map<String, dynamic>.from(response.data as Map);
      final raw = data['users'];
      if (raw is! List) return const [];
      final excluded = excludeUsernames.map((e) => e.toLowerCase()).toSet();
      final seen = <String>{};
      final results = <Map<String, dynamic>>[];
      for (final entry in raw) {
        if (entry is! Map) continue;
        final user = Map<String, dynamic>.from(entry);
        final username = user['username']?.toString();
        if (username == null || username.isEmpty) continue;
        final lower = username.toLowerCase();
        if (excluded.contains(lower) || !seen.add(lower)) continue;
        results.add(user);
      }
      return results;
    } on DioException catch (e) {
      throw Exception(_peopleError(e));
    }
  }

  Future<void> setPreferenceUserNotificationLevel(
    String targetUsername, {
    required int actingUserId,
    required String level,
    DateTime? expiringAt,
  }) async {
    try {
      final encoded = Uri.encodeComponent(targetUsername);
      await dio.put(
        '/u/$encoded/notification_level.json',
        data: <String, dynamic>{
          'notification_level': level,
          'expiring_at': expiringAt?.toUtc().toIso8601String(),
          'acting_user_id': actingUserId,
        },
      );
    } on DioException catch (e) {
      throw Exception(_peopleError(e));
    }
  }
}

String _peopleError(DioException error) {
  final data = error.response?.data;
  if (data is Map) {
    final errors = data['errors'];
    if (errors is List && errors.isNotEmpty) {
      return errors.map((e) => e.toString()).join('\n');
    }
    final value = data['error'] ?? data['message'];
    if (value != null) return value.toString();
  }
  return error.message ?? 'Discourse user preference request failed';
}
