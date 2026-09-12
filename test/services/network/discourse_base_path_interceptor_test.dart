import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/network/interceptors/discourse_base_path_interceptor.dart';

void main() {
  group('DiscourseBasePathInterceptor.resolvePath', () {
    test('root-mounted discourse leaves paths unchanged', () {
      expect(
        DiscourseBasePathInterceptor.resolvePath('', '/latest.json'),
        '/latest.json',
      );
      expect(
        DiscourseBasePathInterceptor.resolvePath('/', '/session/csrf'),
        '/session/csrf',
      );
    });

    test('prefixes leading-slash API paths for relative-url-root', () {
      expect(
        DiscourseBasePathInterceptor.resolvePath('/forum', '/latest.json'),
        '/forum/latest.json',
      );
      expect(
        DiscourseBasePathInterceptor.resolvePath(
          '/forum',
          '/message-bus/client/poll',
        ),
        '/forum/message-bus/client/poll',
      );
    });

    test('prefixes non-leading relative paths and preserves query', () {
      expect(
        DiscourseBasePathInterceptor.resolvePath(
          '/forum/',
          'search.json?q=test',
        ),
        '/forum/search.json?q=test',
      );
    });

    test('does not double-prefix an already scoped path', () {
      expect(
        DiscourseBasePathInterceptor.resolvePath(
          '/forum',
          '/forum/latest.json',
        ),
        '/forum/latest.json',
      );
    });

    test('does not rewrite absolute URLs', () {
      expect(
        DiscourseBasePathInterceptor.resolvePath(
          '/forum',
          'https://cdn.example.com/file.png',
        ),
        'https://cdn.example.com/file.png',
      );
    });
  });
}
