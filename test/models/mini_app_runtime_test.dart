import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/mini_app_runtime.dart';

void main() {
  final site = Uri.parse('https://linux.do');
  const id = '01a1af97-fc83-7be4-a73a-ddd34e2e3719';

  Map<String, Object?> response(String embedUrl) => {
    'configuration': {
      'appId': id,
      'channel': 'production',
      'embedUrl': embedUrl,
      'launchUrl': '/mini-app-api/production/$id/launch',
      'runtimeAssets': {
        'loader': '/plugins/discourse-mini-app/runtime/loader.js',
      },
    },
  };

  test('resolves official production embed URL from info response', () {
    final runtime = MiniAppRuntime.parse(
      response('https://linux.do/apps/$id?embed_mode=true'),
      site: site,
      appId: id,
    );
    expect(runtime.embedUrl.toString(),
        'https://linux.do/apps/$id?embed_mode=true');
  });

  test('does not accept different app, channel or missing configuration', () {
    expect(
      () => MiniAppRuntime.parse(
        {
          'configuration': {
            'appId': 'different',
            'channel': 'production',
            'embedUrl': 'https://linux.do/apps/$id?embed_mode=true',
          },
        },
        site: site,
        appId: id,
      ),
      throwsFormatException,
    );
    expect(
      () => MiniAppRuntime.parse(
        {'configuration': {'appId': id, 'channel': 'sandbox'}},
        site: site,
        appId: id,
      ),
      throwsFormatException,
    );
    expect(
      () => MiniAppRuntime.parse({}, site: site, appId: id),
      throwsFormatException,
    );
  });

  test('rejects foreign origin, arbitrary paths and missing embed mode', () {
    for (final url in [
      'https://evil.example/apps/$id?embed_mode=true',
      'http://linux.do/apps/$id?embed_mode=true',
      'https://linux.do.tld/apps/$id?embed_mode=true',
      'https://linux.do/t/3123326?embed_mode=true',
      'https://linux.do/apps/other?embed_mode=true',
      'https://linux.do/apps/$id',
      'https://linux.do/apps/$id?embed_mode=false',
    ]) {
      expect(
        () => MiniAppRuntime.parse(response(url), site: site, appId: id),
        throwsFormatException,
        reason: url,
      );
    }
  });
}
