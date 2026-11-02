import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/utils/discourse_url_parser.dart';

void main() {
  test('recognizes UUID and slug mini apps', () {
    expect(
      DiscourseUrlParser.parseMiniApp(
        'https://linux.do/apps/01a19674-905b-7246-99ff-2f5e270a3f8f',
      )?.id,
      '01a19674-905b-7246-99ff-2f5e270a3f8f',
    );
    expect(DiscourseUrlParser.parseMiniApp('/apps/example-app?q=1')?.id,
        'example-app');
  });

  test('excludes directory and API paths', () {
    for (final path in [
      '/apps',
      '/apps/directory',
      '/apps/directory.json',
      '/apps/installs/current',
      '/apps/api',
      '/apps/../settings',
      '/apps/foo/bar',
    ]) {
      expect(DiscourseUrlParser.parseMiniApp(path), isNull, reason: path);
    }
    expect(DiscourseUrlParser.isMiniAppsDirectory('/apps'), isTrue);
    expect(DiscourseUrlParser.isMiniAppsDirectory('/apps/directory'),
        isTrue);
    expect(DiscourseUrlParser.isMiniAppsDirectory('/apps/demo'), isFalse);
  });
}
