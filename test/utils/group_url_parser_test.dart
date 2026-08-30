import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/utils/discourse_url_parser.dart';

void main() {
  test('parses native Discourse group links', () {
    expect(DiscourseUrlParser.parseGroup('/g/fish')?.name, 'fish');
    expect(
      DiscourseUrlParser.parseGroup('https://linux.do/g/fish/members')?.name,
      'fish',
    );
    expect(DiscourseUrlParser.parseGroup('/groups/fish'), isNull);
  });
}
