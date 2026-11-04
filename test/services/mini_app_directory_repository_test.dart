import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/mini_app_directory_repository.dart';

void main() {
  final site = Uri.parse('https://linux.do');

  Dio fakeDio({
    required List<String> calls,
    required Response<dynamic> Function(RequestOptions) respond,
  }) {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          calls.add('${options.uri.path}?page=${options.queryParameters['page']}');
          final response = respond(options);
          if ((response.statusCode ?? 0) >= 400) {
            handler.reject(
              DioException(
                requestOptions: options,
                response: response,
                type: DioExceptionType.badResponse,
              ),
            );
          } else {
            handler.resolve(response);
          }
        },
      ),
    );
    return dio;
  }

  test('falls back on 404 then reuses the working endpoint for next pages', () async {
    final calls = <String>[];
    final repository = MiniAppDirectoryRepository(
      dio: fakeDio(
        calls: calls,
        respond: (options) => Response(
          requestOptions: options,
          statusCode: options.uri.path == '/apps/directory.json' ? 404 : 200,
          data: options.uri.path == '/apps.json'
              ? {
                  'apps': [
                    {'id': 'app-${options.queryParameters['page']}'},
                  ],
                  'page': options.queryParameters['page'],
                  'per_page': 24,
                  'total': 48,
                }
              : null,
        ),
      ),
      site: site,
    );

    final first = await repository.fetchPage(0);
    final second = await repository.fetchPage(1);
    expect(first.apps.single.id, 'app-0');
    expect(first.hasNext, isTrue);
    expect(second.apps.single.id, 'app-1');
    expect(second.hasNext, isFalse);
    expect(calls, [
      '/apps/directory.json?page=0',
      '/apps.json?page=0',
      '/apps.json?page=1',
    ]);
  });

  test('never falls back on authorization or rate limit failures', () async {
    for (final status in [401, 403, 429]) {
      final calls = <String>[];
      final repository = MiniAppDirectoryRepository(
        dio: fakeDio(
          calls: calls,
          respond: (options) => Response(
            requestOptions: options,
            statusCode: status,
          ),
        ),
        site: site,
      );

      await expectLater(
        repository.fetchPage(0),
        throwsA(
          isA<DioException>().having(
            (error) => error.response?.statusCode,
            'status',
            status,
          ),
        ),
      );
      expect(calls, ['/apps/directory.json?page=0']);
    }
  });

  test('does not treat a 200 challenge HTML page as an empty directory', () async {
    final calls = <String>[];
    final repository = MiniAppDirectoryRepository(
      dio: fakeDio(
        calls: calls,
        respond: (options) => Response(
          requestOptions: options,
          statusCode: 200,
          data: '<html>Challenge</html>',
        ),
      ),
      site: site,
    );
    await expectLater(repository.fetchPage(0), throwsFormatException);
    expect(calls, ['/apps/directory.json?page=0']);
  });

  test('switches back if the cached legacy path is later removed', () async {
    final calls = <String>[];
    var legacyOnly = true;
    final repository = MiniAppDirectoryRepository(
      dio: fakeDio(
        calls: calls,
        respond: (options) {
          final legacy = options.uri.path == '/apps.json';
          final available = legacyOnly ? legacy : !legacy;
          return Response(
            requestOptions: options,
            statusCode: available ? 200 : 404,
            data: available ? {'apps': []} : null,
          );
        },
      ),
      site: site,
    );

    await repository.fetchPage(0);
    legacyOnly = false;
    await repository.fetchPage(0);
    expect(calls, [
      '/apps/directory.json?page=0',
      '/apps.json?page=0',
      '/apps.json?page=0',
      '/apps/directory.json?page=0',
    ]);
  });
}
