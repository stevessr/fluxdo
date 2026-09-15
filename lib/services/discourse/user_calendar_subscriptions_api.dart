import 'package:dio/dio.dart';

import 'discourse_service.dart';

extension UserCalendarSubscriptionsApi on DiscourseService {
  Future<Map<String, dynamic>> getPreferenceCalendarSubscriptions() async {
    try {
      final response = await dio.get('/calendar-subscriptions.json');
      return _calendarMap(response.data);
    } on DioException catch (e) {
      throw Exception(_calendarError(e));
    }
  }

  Future<Map<String, dynamic>> createPreferenceCalendarSubscriptions() async {
    try {
      final response = await dio.post('/calendar-subscriptions.json');
      return _calendarMap(response.data);
    } on DioException catch (e) {
      throw Exception(_calendarError(e));
    }
  }

  Future<void> revokePreferenceCalendarSubscriptions() async {
    try {
      await dio.delete('/calendar-subscriptions.json');
    } on DioException catch (e) {
      throw Exception(_calendarError(e));
    }
  }
}

Map<String, dynamic> _calendarMap(dynamic data) {
  if (data is Map<String, dynamic>) return data;
  if (data is Map) return Map<String, dynamic>.from(data);
  return <String, dynamic>{};
}

String _calendarError(DioException error) {
  final data = error.response?.data;
  if (data is Map) {
    final errors = data['errors'];
    if (errors is List && errors.isNotEmpty) {
      return errors.map((e) => e.toString()).join('\n');
    }
    final value = data['error'] ?? data['message'];
    if (value != null) return value.toString();
  }
  return error.message ?? 'Discourse calendar subscription request failed';
}
