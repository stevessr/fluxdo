import 'package:flutter/foundation.dart';

import '../../models/topic.dart';
import 'discourse_service.dart';

/// Parameters for Discourse topic-list solved filtering.
///
/// `discourse-solved` is part of Discourse core and augments normal topic-list
/// endpoints with `solved=yes|no`. Keeping this as an extension avoids
/// duplicating the whole topics mixin while still using the same authenticated
/// Dio instance and response model as the rest of the app.
extension SolvedTopicsExtension on DiscourseService {
  Future<TopicListResponse> getSolvedFilteredTopics({
    required String filter,
    required bool solved,
    int? categoryId,
    String? categorySlug,
    String? parentCategorySlug,
    List<String>? tags,
    String? period,
    int page = 0,
    String? order,
    bool? ascending,
    String? subset,
  }) async {
    final request = buildSolvedTopicListRequest(
      filter: filter,
      solved: solved,
      categoryId: categoryId,
      categorySlug: categorySlug,
      parentCategorySlug: parentCategorySlug,
      tags: tags,
      period: period,
      page: page,
      order: order,
      ascending: ascending,
      subset: subset,
    );

    final response = await dio.get(
      request.path,
      queryParameters: request.queryParameters.isEmpty
          ? null
          : request.queryParameters,
    );
    return compute(
      _parseSolvedTopicListResponse,
      response.data as Map<String, dynamic>,
    );
  }
}

@visibleForTesting
SolvedTopicListRequest buildSolvedTopicListRequest({
  required String filter,
  required bool solved,
  int? categoryId,
  String? categorySlug,
  String? parentCategorySlug,
  List<String>? tags,
  String? period,
  int page = 0,
  String? order,
  bool? ascending,
  String? subset,
}) {
  final queryParameters = <String, dynamic>{
    'solved': solved ? 'yes' : 'no',
  };

  if (page > 0) queryParameters['page'] = page;
  if (period != null) queryParameters['period'] = period;
  if (order != null) queryParameters['order'] = order;
  if (ascending != null) {
    queryParameters['ascending'] = ascending.toString();
  }
  if (subset != null) queryParameters['subset'] = subset;

  late final String path;
  if (categoryId != null && categorySlug != null) {
    path = parentCategorySlug != null
        ? '/c/$parentCategorySlug/$categorySlug/$categoryId/l/$filter.json'
        : '/c/$categorySlug/$categoryId/l/$filter.json';
    if (tags != null && tags.isNotEmpty) {
      queryParameters['tags[]'] = tags;
    }
  } else if (tags != null && tags.isNotEmpty) {
    path = '/tag/${tags.first}/l/$filter.json';
    if (tags.length > 1) {
      queryParameters['tags[]'] = tags.skip(1).toList();
      queryParameters['match_all_tags'] = 'true';
    }
  } else {
    path = '/$filter.json';
  }

  return SolvedTopicListRequest(path, queryParameters);
}

@visibleForTesting
class SolvedTopicListRequest {
  final String path;
  final Map<String, dynamic> queryParameters;

  const SolvedTopicListRequest(this.path, this.queryParameters);
}

TopicListResponse _parseSolvedTopicListResponse(Map<String, dynamic> data) {
  return TopicListResponse.fromJson(data);
}
