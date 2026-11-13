import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/mini_app_runtime_repository.dart';

void main() {
  const id = '01a1af97-fc83-7be4-a73a-ddd34e2e3719';
  final site = Uri.parse('https://linux.do');

  test('fetches /info and never requests /launch or credentials', () async {
    final calls = <String>[];
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          calls.add(options.uri.toString());
          handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: {
              'app': {'app_id': id, 'name': '万年历拼图'},
              'configuration': {
                'appId': id,
                'channel': 'production',
                'embedUrl': 'https://linux.do/apps/$id?embed_mode=true',
                'runtimeAssets': {'loader': '/runtime/loader.js'},
              },
            },
          ));
        },
      ),
    );
    final repository = MiniAppRuntimeRepository(dio: dio, site: site);
    final runtime = await repository.resolve(id);
    expect(runtime.embedUrl.queryParameters['embed_mode'], 'true');
    expect(calls, ['https://linux.do/mini-app-api/production/$id/info']);
  });

  test('rejects malformed app IDs without making a network request', () async {
    final repository = MiniAppRuntimeRepository(dio: Dio(), site: site);
    await expectLater(repository.resolve('../other'), throwsArgumentError);
  });
}
