import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../message_bus_service.dart';
import 'discourse_service.dart';

extension UserAvatarApi on DiscourseService {
  Future<Map<String, dynamic>> uploadPreferenceAvatar(
    String filePath, {
    required int userId,
  }) async {
    final fileName = filePath.split(RegExp(r'[/\\]')).last;
    return _uploadAvatarMultipart(
      userId: userId,
      file: await MultipartFile.fromFile(filePath, filename: fileName),
    );
  }

  Future<Map<String, dynamic>> uploadPreferenceAvatarBytes(
    Uint8List bytes, {
    required String fileName,
    required int userId,
  }) => _uploadAvatarMultipart(
    userId: userId,
    file: MultipartFile.fromBytes(bytes, filename: fileName),
  );

  Future<Map<String, dynamic>> _uploadAvatarMultipart({
    required int userId,
    required MultipartFile file,
  }) async {
    try {
      final response = await dio.post(
        '/uploads.json',
        queryParameters: {'client_id': MessageBusService().clientId},
        data: FormData.fromMap({
          'upload_type': 'avatar',
          'synchronous': true,
          'user_id': userId,
          'file': file,
        }),
      );
      if (response.data is! Map) {
        throw Exception('Invalid avatar upload response');
      }
      final data = Map<String, dynamic>.from(response.data as Map);
      if (data['id'] is! int || data['url']?.toString().isEmpty != false) {
        throw Exception('Discourse avatar upload returned incomplete data');
      }
      return data;
    } on DioException catch (e) {
      throw Exception(_avatarError(e));
    }
  }

  Future<void> pickPreferenceAvatar(
    String username, {
    required int uploadId,
    required String type,
  }) async {
    try {
      await dio.put(
        '/u/${Uri.encodeComponent(username)}/preferences/avatar/pick',
        data: {'upload_id': uploadId, 'type': type},
      );
    } on DioException catch (e) {
      throw Exception(_avatarError(e));
    }
  }

  Future<void> selectPreferenceAvatarUrl(
    String username,
    String url,
  ) async {
    try {
      await dio.put(
        '/u/${Uri.encodeComponent(username)}/preferences/avatar/select',
        data: {'url': url},
      );
    } on DioException catch (e) {
      throw Exception(_avatarError(e));
    }
  }

  Future<Map<String, dynamic>> refreshPreferenceGravatar(String username) async {
    try {
      final response = await dio.post(
        '/user_avatar/${Uri.encodeComponent(username)}/refresh_gravatar.json',
      );
      return response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : <String, dynamic>{};
    } on DioException catch (e) {
      throw Exception(_avatarError(e));
    }
  }
}

String _avatarError(DioException error) {
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
  return error.message ?? 'Discourse avatar request failed';
}
