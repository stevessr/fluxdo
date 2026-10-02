import 'package:flutter_test/flutter_test.dart';
import 'package:pangutext/pangutext.dart';

void main() {
  group('Pangu 裸 HTTP(S) URL 保护', () {
    test('不会向 https URL 内部插入空格', () {
      const input =
          '请访问https://example.com/foo-bar?q=a+b&lang=zh#section获取详情';

      expect(
        Pangu().spacingText(input),
        '请访问 https://example.com/foo-bar?q=a+b&lang=zh#section 获取详情',
      );
    });

    test('保留百分号编码、查询参数和片段', () {
      const url =
          'https://example.com/a-b/%E4%B8%AD%E6%96%87?q=hello-world&x=1%2B2#part-1';

      expect(Pangu().spacingText('中文${url}测试'), '中文 ${url} 测试');
    });

    test('同样保护 http URL', () {
      const url = 'http://example.com/path/to-file?foo=bar&n=1';

      expect(Pangu().spacingText('前缀${url}后缀'), '前缀 ${url} 后缀');
    });
  });
}
