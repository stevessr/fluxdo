import 'package:dio/dio.dart';

import 'discourse_service.dart';

extension UserSecurityExtrasApi on DiscourseService {
  Future<void> revokePreferenceApiKey(int id) async {
    try {
      await dio.post('/user-api-key/revoke', data: {'id': id});
    } on DioException catch (e) {
      throw Exception(_securityExtrasError(e));
    }
  }

  Future<void> undoRevokePreferenceApiKey(int id) async {
    try {
      await dio.post('/user-api-key/undo-revoke', data: {'id': id});
    } on DioException catch (e) {
      throw Exception(_securityExtrasError(e));
    }
  }

  /// Matches Discourse's native ConfirmSession password flow.
  ///
  /// A successful request marks the current server session as confirmed/trusted
  /// so sensitive preference actions (2FA, security keys, Passkey deletion,
  /// password removal, etc.) can proceed without signing out and back in.
  Future<Map<String, dynamic>> confirmPreferenceSessionWithPassword(
    String password,
  ) async {
    try {
      final response = await dio.post(
        '/u/confirm-session.json',
        data: {'password': password},
      );
      return response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : <String, dynamic>{};
    } on DioException catch (e) {
      throw Exception(_securityExtrasError(e));
    }
  }

  Future<void> renamePreferencePasskey(int id, String name) async {
    try {
      await dio.put('/u/rename_passkey/$id', data: {'name': name});
    } on DioException catch (e) {
      throw Exception(_securityExtrasError(e));
    }
  }

  Future<void> deletePreferencePasskey(int id) async {
    try {
      await dio.delete('/u/delete_passkey/$id');
    } on DioException catch (e) {
      throw Exception(_securityExtrasError(e));
    }
  }

  Future<void> deletePreferenceAccount(String username) async {
    final currentUsername = await getCurrentUsername();
    if (currentUsername == null ||
        currentUsername.toLowerCase() != username.toLowerCase()) {
      throw Exception(
        'Account deletion from preferences is restricted to the current user',
      );
    }

    try {
      final encoded = Uri.encodeComponent(username);
      await dio.delete('/u/$encoded');
    } on DioException catch (e) {
      throw Exception(_securityExtrasError(e));
    }
  }
}

String _securityExtrasError(DioException error) {
  final data = error.response?.data;
  if (data is Map) {
    final errors = data['errors'];
    if (errors is List && errors.isNotEmpty) {
      return errors.map((e) => e.toString()).join('\n');
    }
    final message = data['message'] ?? data['error'];
    if (message != null) return message.toString();
  }
  return error.message ?? 'Discourse security request failed';
}
