import 'package:dio/dio.dart';

import 'discourse_service.dart';

/// Native API surface for Discourse user preferences.
///
/// Discourse's frontend flattens `user_option` values into the same payload as
/// regular user fields when saving `/u/:username.json`. Keep the same contract
/// here so the Flutter UI can mirror the official preferences pages without a
/// WebView.
extension UserPreferencesApi on DiscourseService {
  Future<Map<String, dynamic>> getUserPreferences(String username) async {
    try {
      final response = await dio.get('/u/${Uri.encodeComponent(username)}.json');
      final data = Map<String, dynamic>.from(response.data as Map);
      final user = data['user'] is Map ? data['user'] as Map : data;
      return Map<String, dynamic>.from(user);
    } on DioException catch (e) {
      throw Exception(_discoursePreferenceError(e));
    }
  }

  Future<Map<String, dynamic>> updateUserPreferences(
    String username,
    Map<String, dynamic> attributes,
  ) async {
    if (attributes.isEmpty) return getUserPreferences(username);
    try {
      final response = await dio.put(
        '/u/${Uri.encodeComponent(username)}.json',
        data: attributes,
      );
      if (response.data is Map) {
        final data = Map<String, dynamic>.from(response.data as Map);
        if (data['user'] is Map) {
          return Map<String, dynamic>.from(data['user'] as Map);
        }
      }
      return getUserPreferences(username);
    } on DioException catch (e) {
      throw Exception(_discoursePreferenceError(e));
    }
  }

  Future<void> changePreferenceUsername(
    String username,
    String newUsername,
  ) async {
    try {
      await dio.put(
        '/u/${Uri.encodeComponent(username)}/preferences/username',
        data: {'new_username': newUsername},
      );
    } on DioException catch (e) {
      throw Exception(_discoursePreferenceError(e));
    }
  }

  Future<void> changePreferenceEmail(String username, String email) async {
    try {
      await dio.put(
        '/u/${Uri.encodeComponent(username)}/preferences/email',
        data: {'email': email},
      );
    } on DioException catch (e) {
      throw Exception(_discoursePreferenceError(e));
    }
  }

  Future<void> requestPreferencePasswordReset({
    required String login,
  }) async {
    try {
      await dio.post('/session/forgot_password.json', data: {'login': login});
    } on DioException catch (e) {
      throw Exception(_discoursePreferenceError(e));
    }
  }

  Future<Map<String, dynamic>> getTrustedSession() async {
    try {
      final response = await dio.get('/u/trusted-session.json');
      return response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : <String, dynamic>{};
    } on DioException catch (e) {
      throw Exception(_discoursePreferenceError(e));
    }
  }

  Future<void> revokePreferenceAuthToken(
    String username, {
    int? tokenId,
  }) async {
    try {
      await dio.post(
        '/u/${Uri.encodeComponent(username)}/preferences/revoke-auth-token',
        data: tokenId == null ? <String, dynamic>{} : {'token_id': tokenId},
      );
    } on DioException catch (e) {
      throw Exception(_discoursePreferenceError(e));
    }
  }
}

String _discoursePreferenceError(DioException error) {
  final data = error.response?.data;
  if (data is Map) {
    final errors = data['errors'];
    if (errors is List && errors.isNotEmpty) {
      return errors.map((e) => e.toString()).join('\n');
    }
    final error = data['error'];
    if (error != null) return error.toString();
    final message = data['message'];
    if (message != null) return message.toString();
  }
  return error.message ?? 'Discourse request failed';
}
