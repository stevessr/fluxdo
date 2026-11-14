import 'dart:io';

/// Absolute package root derived from this source file, independent of cwd.
final packageRoot = File.fromUri(Platform.script).parent.parent.path;

String packagePath(String relative) => '$packageRoot/$relative';

Future<void> runOrExit({
  required String title,
  required String executable,
  required List<String> arguments,
}) async {
  stdout.writeln(title);
  final result = await Process.run(executable, arguments);
  if (result.stdout case final String output when output.isNotEmpty) {
    stdout.write(output);
  }
  if (result.stderr case final String output when output.isNotEmpty) {
    stderr.write(output);
  }
  if (result.exitCode != 0) {
    throw ProcessException(executable, arguments, '执行失败: $title', result.exitCode);
  }
}
