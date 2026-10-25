import 'dart:typed_data';

/// Reads a manually selected ZIP without materializing unbounded picker bytes.
/// Validates both the picker advertised length and actual streamed length.
Future<Uint8List> readBoundedPackStream(
  Stream<List<int>> stream, {
  required int expectedBytes,
  int maxBytes = 128 * 1024 * 1024,
}) async {
  if (maxBytes <= 0 || expectedBytes <= 0 || expectedBytes > maxBytes) {
    throw const FormatException('ZIP 超过安全导入上限或为空');
  }
  final builder = BytesBuilder(copy: false);
  var received = 0;
  await for (final chunk in stream) {
    if (chunk.length > maxBytes - received ||
        chunk.length > expectedBytes - received) {
      throw const FormatException('ZIP 实际内容超过声明大小或安全上限');
    }
    builder.add(chunk);
    received += chunk.length;
  }
  if (received != expectedBytes) {
    throw const FormatException('ZIP 文件读取不完整');
  }
  return builder.takeBytes();
}
