import 'dart:typed_data';

/// Web 没有可选本地资源包目录，始终使用 Flutter 内置资源。
Future<Uint8List?> readVerifiedAsset(String assetPath) async => null;

Future<void> installTrustedZip({
  required String packId,
  required Uint8List zipBytes,
  required String expectedSha256,
}) {
  throw UnsupportedError('此平台暂不支持本地静态资源包安装');
}

Future<List<Map<String, String>>> listInstalledPacks() async => [];

Future<bool> rollbackPack(String packId) async => false;

Future<bool> disablePack(String packId) async => false;

Future<int> pruneUnusedPacks({Duration minAge = const Duration(days: 1)}) async => 0;
