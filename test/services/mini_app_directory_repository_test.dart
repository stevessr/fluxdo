import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/mini_app_directory_repository.dart';

void main() {
  final site = Uri.parse('https://linux.do');

  test('uses official directory endpoint, sort, search and zero-based paging', () async {
    final calls = <Uri>[];
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      calls.add(options.uri);
      handler.resolve(Response(
        requestOptions: options,
        statusCode: 200,
        data: {
          'apps': [
            {
              'app_id': '01a19674-905b-7246-99ff-2f5e270a3f8f',
              'name': '能力测试',
              'rating_average': 5.0,
              'rating_count': 1,
              'usage_count': 3098,
              'author': {'username': 'neo'},
            },
          ],
          'page': options.queryParameters['page'],
          'total': 25,
          'per_page': 24,
        },
      ));
    }));
    final repository = MiniAppDirectoryRepository(dio: dio, site: site);
    final first = await repository.fetchPage(0);
    expect(first.apps.single.name, '能力测试');
    expect(first.apps.single.ratingAverage, 5.0);
    expect(first.apps.single.usageCount, 3098);
    expect(first.apps.single.authorName, 'neo');
    expect(first.hasNext, isTrue);
    await repository.fetchPage(1, sort: 'latest', query: '能力');
    await repository.fetchPage(0, sort: 'rating');
    await repository.fetchPage(0, sort: 'used');
    expect(calls.map((uri) => uri.path).toSet(), {
      '/mini-app-api/apps.json',
    });
    expect(calls.map((uri) => uri.queryParameters), [
      {'sort': 'hot', 'q': '', 'page': '0'},
      {'sort': 'latest', 'q': '能力', 'page': '1'},
      {'sort': 'rating', 'q': '', 'page': '0'},
      {'sort': 'used', 'q': '', 'page': '0'},
    ]);
  });

  test('rejects invalid sort and page without a network request', () async {
    final repository = MiniAppDirectoryRepository(dio: Dio(), site: site);
    await expectLater(repository.fetchPage(-1), throwsArgumentError);
    await expectLater(repository.fetchPage(0, sort: 'invalid'), throwsArgumentError);
  });

  test('rejects HTML challenges instead of showing an empty directory', () async {
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      handler.resolve(Response(
        requestOptions: options,
        statusCode: 200,
        data: '<html>Challenge</html>',
      ));
    }));
    final repository = MiniAppDirectoryRepository(dio: dio, site: site);
    await expectLater(repository.fetchPage(0), throwsFormatException);
  });
}
