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
