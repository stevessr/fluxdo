part of 'discourse_service.dart';

/// discourse-boards 插件接口。
mixin _BoardsMixin on _DiscourseServiceBase {
  Future<List<DiscourseBoard>> getBoards() async {
    try {
      final response = await _dio.get('/boards/api/boards.json');
      final data = response.data as Map<String, dynamic>;
      return (data['boards'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(DiscourseBoard.fromJson)
          .toList();
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  Future<DiscourseBoard> getBoard(int boardId) async {
    try {
      final response = await _dio.get('/boards/api/boards/$boardId.json');
      return DiscourseBoard.fromDetailResponse(
        response.data as Map<String, dynamic>,
      );
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// floater 卡片的负责人属于 Boards 自己；topic 卡片继续使用
  /// discourse-assign 的 /assign/assign，避免把两套 assignment 混在一起。
  Future<BoardCard> updateBoardCardAssignee({
    required int boardId,
    required int cardId,
    String? assignedToName,
  }) async {
    try {
      final response = await _dio.put(
        '/boards/api/boards/$boardId/cards/$cardId.json',
        data: {
          'card': {'assigned_to_name': assignedToName},
        },
      );
      final data = response.data as Map<String, dynamic>;
      return BoardCard.fromJson(data['card'] as Map<String, dynamic>);
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// 官方 Boards 用这个端点记录打开卡片历史；失败不应阻断预览。
  Future<void> recordBoardCardView({
    required int boardId,
    required int cardId,
  }) async {
    await _dio.post('/boards/api/boards/$boardId/cards/$cardId/view');
  }
}
