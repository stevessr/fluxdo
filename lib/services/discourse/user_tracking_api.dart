import 'package:dio/dio.dart';

import 'discourse_service.dart';

extension UserTrackingApi on DiscourseService {
  Future<List<Map<String, dynamic>>> searchPreferenceTags(
    String query, {
    int limit = 30,
    Iterable<String> selectedTags = const [],
  }) async {
    try {
      final params = <String, dynamic>{
        'q': query.trim(),
        'limit': limit,
        'filterForInput': true,
      };
      final selected = selectedTags.where((e) => e.isNotEmpty).take(100).toList();
      if (selected.isNotEmpty) params['selected_tags'] = selected;

      final response = await dio.get(
        '/tags/filter/search',
        queryParameters: params,
      );
      if (response.data is! Map) return const [];
      final data = Map<String, dynamic>.from(response.data as Map);
      final raw = data['results'];
      if (raw is! List) return const [];

      final names = <String>{};
      final results = <Map<String, dynamic>>[];
      for (final entry in raw) {
        if (entry is String) {
          if (entry.isNotEmpty && names.add(entry)) {
            results.add({'name': entry});
          }
          continue;
        }
        if (entry is! Map) continue;
        final item = Map<String, dynamic>.from(entry);
        final name = item['name']?.toString() ?? item['id']?.toString();
        if (name == null || name.isEmpty || !names.add(name)) continue;
        item['name'] = name;
        results.add(item);
      }
      return results;
    } on DioException catch (e) {
      throw Exception(_trackingError(e));
    }
  }
}

String _trackingError(DioException error) {
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
  return error.message ?? 'Discourse tag search failed';
}
