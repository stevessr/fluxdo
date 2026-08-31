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
      return _normalizeUserPreferences(Map<String, dynamic>.from(user));
    } on DioException catch (e) {
      throw Exception(_discoursePreferenceError(e));
    }
  }

  Future<Map<String, dynamic>> updateUserPreferences(
    String username,
    Map<String, dynamic> attributes,
  ) async {
    if (attributes.isEmpty) return getUserPreferences(username);
    final payload = _serializeUserPreferences(attributes);
    try {
      final response = await dio.put(
        '/u/${Uri.encodeComponent(username)}.json',
        data: payload,
      );
      if (response.data is Map) {
        final data = Map<String, dynamic>.from(response.data as Map);
        if (data['user'] is Map) {
          return _normalizeUserPreferences(
            Map<String, dynamic>.from(data['user'] as Map),
          );
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

  Future<void> addPreferenceEmail(String username, String email) async {
    try {
      await dio.post(
        '/u/${Uri.encodeComponent(username)}/preferences/email',
        data: {'email': email},
      );
    } on DioException catch (e) {
      throw Exception(_discoursePreferenceError(e));
    }
  }

  Future<void> setPreferencePrimaryEmail(String username, String email) async {
    try {
      await dio.put(
        '/u/${Uri.encodeComponent(username)}/preferences/primary-email.json',
        data: {'email': email},
      );
    } on DioException catch (e) {
      throw Exception(_discoursePreferenceError(e));
    }
  }

  Future<void> deletePreferenceEmail(String username, String email) async {
    try {
      await dio.delete(
        '/u/${Uri.encodeComponent(username)}/preferences/email.json',
        data: {'email': email},
      );
    } on DioException catch (e) {
      throw Exception(_discoursePreferenceError(e));
    }
  }

  Future<void> requestPreferencePasswordReset({required String login}) async {
    try {
      await dio.post('/session/forgot_password.json', data: {'login': login});
    } on DioException catch (e) {
      throw Exception(_discoursePreferenceError(e));
    }
  }

  Future<void> removePreferencePassword(String username) async {
    try {
      await dio.put('/u/${Uri.encodeComponent(username)}/remove-password');
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

  Future<void> revokePreferenceAssociatedAccount(
    String username,
    String providerName,
  ) async {
    try {
      await dio.post(
        '/u/${Uri.encodeComponent(username)}/preferences/revoke-account',
        data: {'provider_name': providerName},
      );
    } on DioException catch (e) {
      throw Exception(_discoursePreferenceError(e));
    }
  }

  Future<void> exportPreferenceUserArchive() async {
    try {
      await dio.post(
        '/export_csv/export_entity.json',
        data: {'entity': 'user_archive', 'args': null},
      );
    } on DioException catch (e) {
      throw Exception(_discoursePreferenceError(e));
    }
  }

  Future<Map<String, dynamic>> loadPreferenceSecondFactors() async {
    try {
      final response = await dio.post('/u/second_factors.json');
      return response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : <String, dynamic>{};
    } on DioException catch (e) {
      throw Exception(_discoursePreferenceError(e));
    }
  }

  Future<Map<String, dynamic>> createPreferenceTotp() async {
    try {
      final response = await dio.post('/u/create_second_factor_totp.json');
      return response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : <String, dynamic>{};
    } on DioException catch (e) {
      throw Exception(_discoursePreferenceError(e));
    }
  }

  Future<Map<String, dynamic>> enablePreferenceTotp({
    required String token,
    required String name,
  }) async {
    try {
      final response = await dio.post(
        '/u/enable_second_factor_totp.json',
        data: {'second_factor_token': token, 'name': name},
      );
      return response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : <String, dynamic>{};
    } on DioException catch (e) {
      throw Exception(_discoursePreferenceError(e));
    }
  }

  Future<void> updatePreferenceSecondFactor({
    required int id,
    required String name,
    required bool disable,
    required int targetMethod,
  }) async {
    try {
      await dio.put(
        '/u/second_factor.json',
        data: {
          'second_factor_target': targetMethod,
          'name': name,
          'disable': disable,
          'id': id,
        },
      );
    } on DioException catch (e) {
      throw Exception(_discoursePreferenceError(e));
    }
  }

  Future<void> disableAllPreferenceSecondFactors() async {
    try {
      await dio.put('/u/disable_second_factor.json');
    } on DioException catch (e) {
      throw Exception(_discoursePreferenceError(e));
    }
  }

  Future<Map<String, dynamic>> generatePreferenceBackupCodes() async {
    try {
      final response = await dio.put('/u/second_factors_backup.json');
      return response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : <String, dynamic>{};
    } on DioException catch (e) {
      throw Exception(_discoursePreferenceError(e));
    }
  }
}

/// Discourse stores interface color mode as 1/2/3. The native page uses the
/// readable auto/light/dark values internally, so normalize only at this API
/// boundary and keep the wire format exactly aligned with upstream.
Map<String, dynamic> _normalizeUserPreferences(Map<String, dynamic> user) {
  final rawOptions = user['user_option'];
  if (rawOptions is Map) {
    final options = Map<String, dynamic>.from(rawOptions);
    if (options.containsKey('interface_color_mode')) {
      options['interface_color_mode'] = switch (options['interface_color_mode']) {
        1 => 'auto',
        2 => 'light',
        3 => 'dark',
        final value => value,
      };
    }
    user['user_option'] = options;
  }
  return user;
}

Map<String, dynamic> _serializeUserPreferences(
  Map<String, dynamic> attributes,
) {
  final payload = Map<String, dynamic>.from(attributes);

  if (payload.containsKey('interface_color_mode')) {
    payload['interface_color_mode'] = switch (payload['interface_color_mode']) {
      'auto' => 1,
      'light' => 2,
      'dark' => 3,
      final value => value,
    };
  }

  // Discourse's UserUpdater treats these values as comma-separated strings and
  // calls `split(",")` itself. Ember's normal form serialization produces that
  // shape, while Flutter's JSON requests preserve List<String>, so normalize at
  // the boundary for every native caller (including the legacy field editor).
  const commaSeparatedFields = <String>{
    'watched_tags',
    'tracked_tags',
    'watching_first_post_tags',
    'muted_tags',
    'muted_usernames',
    'allowed_pm_usernames',
  };
  for (final field in commaSeparatedFields) {
    final value = payload[field];
    if (value is Iterable && value is! String) {
      payload[field] = value.map((e) => e.toString()).join(',');
    }
  }

  // These fields use an empty string as an explicit clear signal in
  // UserUpdater. JSON null is falsey in Ruby and would skip the clear branch.
  for (final field in const <String>{
    'profile_background_upload_url',
    'card_background_upload_url',
    'primary_group_id',
    'flair_group_id',
  }) {
    if (payload.containsKey(field) && payload[field] == null) {
      payload[field] = '';
    }
  }

  // The server special-cases the string "-1" to mean "use the site default"
  // homepage before assigning the integer column. JSON keeps -1 as an int, so
  // preserve the same semantics explicitly.
  if (payload['homepage_id'] == -1) {
    payload['homepage_id'] = '-1';
  }

  return payload;
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
