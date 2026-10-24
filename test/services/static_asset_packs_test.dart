import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/assets/static_asset_packs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('没有安装资源包时，Cook JS 回退到内置 Flutter asset', () async {
    const path = 'assets/cook/discourse-cook.js';
    final original = await rootBundle.loadString(path);
    expect(original, isNotEmpty);
    expect(await StaticAssetPacks.loadString(path), original);
  });
}
