import 'package:dio/dio.dart';

import '../message_bus_service.dart';
import 'discourse_service.dart';

/// Native API helpers for Discourse profile media and featured-topic controls.
extension UserProfileExtrasApi on DiscourseService {
  Future<Map<String, dynamic>> uploadUserProfileImage(
    String filePath, {
    required String uploadType,
  }) async {
    if (uploadType != 'profile_background' &&
        uploadType != 'card_background') {
      throw ArgumentError.value(uploadType, 'uploadType');
    }

    try {
      final fileName = filePath.split(RegExp(r'[/\\]')).last;
      final formData = FormData.fromMap({
        'upload_type': uploadType,
        'synchronous': true,
        'file': await MultipartFile.fromFile(filePath, filename: fileName),
      });
      final response = await dio.post(
        '/uploads.json',
        queryParameters: {'client_id': MessageBusService().clientId},
        data: formData,
      );
      if (response.data is! Map) {
        throw Exception('Invalid upload response');
      }
      final data = Map<String, dynamic>.from(response.data as Map);
      final url = data['url']?.toString();
      if (url == null || url.isEmpty) {
        throw Exception('Discourse upload did not return a URL');
      }
      return data;
    } on DioException catch (e) {
      throw Exception(_profileExtrasError(e));
    }
  }

  Future<void> setFeaturedProfileTopic(
    String username,
    int topicId,
  ) async {
    try {
      await dio.put(
        '/u/${Uri.encodeComponent(username)}/feature-topic',
        data: {'topic_id': topicId},
      );
    } on DioException catch (e) {
      throw Exception(_profileExtrasError(e));
    }
  }

  Future<void> clearFeaturedProfileTopic(String username) async {
    try {
      await dio.put('/u/${Uri.encodeComponent(username)}/clear-featured-topic');
    } on DioException catch (e) {
      throw Exception(_profileExtrasError(e));
    }
  }

  Future<List<Map<String, dynamic>>> searchPublicTopicsForProfile(
    String query,
  ) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    try {
      final response = await dio.get(
        '/search.json',
        queryParameters: {
          'q': '$trimmed status:public',
          'type_filter': 'topic',
        },
      );
      if (response.data is! Map) return const [];
      final data = Map<String, dynamic>.from(response.data as Map);
      final rawTopics = data['topics'];
      if (rawTopics is! List) return const [];

      final seen = <int>{};
      final topics = <Map<String, dynamic>>[];
      for (final raw in rawTopics.whereType<Map>()) {
        final topic = Map<String, dynamic>.from(raw);
        final id = topic['id'];
        if (id is! int || !seen.add(id)) continue;
        topics.add(topic);
      }
      return topics;
    } on DioException catch (e) {
      throw Exception(_profileExtrasError(e));
    }
  }
}

String _profileExtrasError(DioException error) {
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
