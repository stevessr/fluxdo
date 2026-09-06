import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/discourse/solved_topics_extension.dart';

void main() {
  group('buildSolvedTopicListRequest', () {
    test('adds solved=yes to the global latest list', () {
      final request = buildSolvedTopicListRequest(
        filter: 'latest',
        solved: true,
      );

      expect(request.path, '/latest.json');
      expect(request.queryParameters, {'solved': 'yes'});
    });

    test('preserves category, tags, paging, and sort for unsolved list', () {
      final request = buildSolvedTopicListRequest(
        filter: 'latest',
        solved: false,
        categoryId: 3,
        categorySlug: 'support',
        parentCategorySlug: 'tech',
        tags: const ['flutter', 'bug'],
        page: 2,
        order: 'activity',
        ascending: false,
      );

      expect(request.path, '/c/tech/support/3/l/latest.json');
      expect(request.queryParameters['solved'], 'no');
      expect(request.queryParameters['tags[]'], ['flutter', 'bug']);
      expect(request.queryParameters['page'], 2);
      expect(request.queryParameters['order'], 'activity');
      expect(request.queryParameters['ascending'], 'false');
    });

    test('uses the first tag in the route and matches remaining tags', () {
      final request = buildSolvedTopicListRequest(
        filter: 'latest',
        solved: true,
        tags: const ['dart', 'flutter', 'mobile'],
      );

      expect(request.path, '/tag/dart/l/latest.json');
      expect(request.queryParameters['solved'], 'yes');
      expect(request.queryParameters['tags[]'], ['flutter', 'mobile']);
      expect(request.queryParameters['match_all_tags'], 'true');
    });
  });
}
