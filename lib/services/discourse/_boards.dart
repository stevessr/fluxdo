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

  /// 获取当前话题可加入的 Boards。
  Future<List<DiscourseBoard>> getAvailableBoards({
    int? topicId,
    List<String> allowedPermissions = const ['edit', 'manage'],
  }) async {
    try {
      final response = await _dio.get(
        '/boards/api/boards/available.json',
        queryParameters: {
          if (topicId != null) 'topic_id': topicId,
          if (allowedPermissions.isNotEmpty)
            'allowed_permissions': allowedPermissions.join(','),
        },
      );
      final data = Map<String, dynamic>.from(response.data as Map);
      return (data['boards'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) => DiscourseBoard.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(growable: false);
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// 创建 Board。字段直接对齐 Boards::Board contract，便于兼容插件后续扩展。
  Future<DiscourseBoard> createBoard(Map<String, dynamic> board) async {
    try {
      final response = await _dio.post(
        '/boards/api/boards.json',
        data: {'board': board},
        options: Options(contentType: Headers.jsonContentType),
      );
      final root = Map<String, dynamic>.from(response.data as Map);
      return DiscourseBoard.fromJson(
        Map<String, dynamic>.from(root['board'] as Map),
      );
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  Future<DiscourseBoard> updateBoard(
    int boardId,
    Map<String, dynamic> updates,
  ) async {
    try {
      final response = await _dio.put(
        '/boards/api/boards/$boardId.json',
        data: {'board': updates},
      );
      final root = Map<String, dynamic>.from(response.data as Map);
      return DiscourseBoard.fromJson(
        Map<String, dynamic>.from(root['board'] as Map),
      );
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  Future<void> archiveBoard(int boardId) async {
    try {
      await _dio.post('/boards/api/boards/$boardId/archive.json');
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  Future<void> unarchiveBoard(int boardId) async {
    try {
      await _dio.post('/boards/api/boards/$boardId/unarchive.json');
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  Future<void> deleteBoard(int boardId) async {
    try {
      await _dio.delete('/boards/api/boards/$boardId.json');
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  Future<Map<String, dynamic>> createBoardColumn(
    int boardId,
    Map<String, dynamic> column,
  ) async {
    try {
      final response = await _dio.post(
        '/boards/api/boards/$boardId/columns.json',
        data: {'column': column},
      );
      return Map<String, dynamic>.from(response.data as Map);
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  Future<Map<String, dynamic>> updateBoardColumn(
    int boardId,
    int columnId,
    Map<String, dynamic> updates,
  ) async {
    try {
      final response = await _dio.put(
        '/boards/api/boards/$boardId/columns/$columnId.json',
        data: {'column': updates},
      );
      return Map<String, dynamic>.from(response.data as Map);
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  Future<void> deleteBoardColumn(int boardId, int columnId) async {
    try {
      await _dio.delete('/boards/api/boards/$boardId/columns/$columnId.json');
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// 调整列顺序。afterColumnId 为空表示移动到最前。
  Future<void> moveBoardColumn(
    int boardId, {
    required int columnId,
    int? afterColumnId,
  }) async {
    try {
      await _dio.post(
        '/boards/api/boards/$boardId/move-column.json',
        data: {'column_id': columnId, 'after_column_id': afterColumnId},
      );
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  Future<void> clearBoardColumn(int boardId, int columnId) async {
    try {
      await _dio.delete(
        '/boards/api/boards/$boardId/columns/$columnId/cards.json',
      );
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  Future<BoardCard> createBoardCard(
    int boardId, {
    required Map<String, dynamic> card,
    Map<String, dynamic>? constraintFix,
    String? clientId,
  }) async {
    try {
      final response = await _dio.post(
        '/boards/api/boards/$boardId/cards.json',
        data: {
          if (clientId != null) 'client_id': clientId,
          'card': card,
          if (constraintFix != null) 'constraint_fix': constraintFix,
        },
      );
      final root = Map<String, dynamic>.from(response.data as Map);
      return BoardCard.fromJson(Map<String, dynamic>.from(root['card'] as Map));
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  Future<BoardCard> updateBoardCard(
    int boardId,
    int cardId,
    Map<String, dynamic> updates, {
    String? clientId,
  }) async {
    try {
      final response = await _dio.put(
        '/boards/api/boards/$boardId/cards/$cardId.json',
        data: {if (clientId != null) 'client_id': clientId, 'card': updates},
      );
      final root = Map<String, dynamic>.from(response.data as Map);
      return BoardCard.fromJson(Map<String, dynamic>.from(root['card'] as Map));
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  Future<void> deleteBoardCard(
    int boardId,
    int cardId, {
    String? clientId,
  }) async {
    try {
      await _dio.delete(
        '/boards/api/boards/$boardId/cards/$cardId.json',
        data: {if (clientId != null) 'client_id': clientId},
      );
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  /// 将话题加入/移动到 Board 列。已存在卡片时服务端会更新其列。
  Future<BoardCard> moveTopicToBoardColumn({
    required int boardId,
    required int topicId,
    required int toColumnId,
  }) async {
    try {
      final response = await _dio.post(
        '/boards/api/boards/$boardId/topic-moves.json',
        data: {'topic_id': topicId, 'to_column_id': toColumnId},
      );
      final root = Map<String, dynamic>.from(response.data as Map);
      return BoardCard.fromJson(Map<String, dynamic>.from(root['card'] as Map));
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  Future<Map<String, dynamic>> previewBoardConstraints(
    int boardId, {
    required Map<String, dynamic> board,
  }) async {
    try {
      final response = await _dio.post(
        '/boards/api/boards/$boardId/constraint-preview.json',
        data: {'board': board},
      );
      return Map<String, dynamic>.from(response.data as Map);
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }

  Future<Map<String, dynamic>> checkBoardConstraintMismatches(
    int boardId, {
    Map<String, dynamic>? board,
  }) async {
    try {
      final response = await _dio.put(
        '/boards/api/boards/$boardId/check-constraint-mismatches.json',
        data: {if (board != null) 'board': board},
      );
      return Map<String, dynamic>.from(response.data as Map);
    } on DioException catch (e) {
      _throwApiError(e);
    }
  }
}
