import 'catalog.g.dart';

class AndroidOptionalPlugin {
  const AndroidOptionalPlugin({
    required this.id,
    required this.name,
    required this.packageName,
    required this.installed,
    required this.compatible,
    required this.reason,
    this.version,
  });

  final String id;
  final String name;
  final String packageName;
  final bool installed;
  final bool compatible;
  final String reason;
  final String? version;

  factory AndroidOptionalPlugin.fromMap(Map<dynamic, dynamic> data) {
    final id = data['id'];
    final definition = id is String ? androidPluginCatalog[id] : null;
    if (definition == null || data['package'] != definition.packageName) {
      throw const FormatException('Unknown or mismatched plugin identity');
    }
    final installed = data['installed'];
    final compatible = data['compatible'];
    final reason = data['reason'];
    final version = data['version'];
    if (installed is! bool ||
        compatible is! bool ||
        reason is! String ||
        (version != null && version is! String)) {
      throw const FormatException('Invalid plugin status types');
    }
    if (compatible && (!installed || reason != 'ready')) {
      throw const FormatException('Contradictory compatible plugin status');
    }
    // Unknown reasons remain visible for diagnostics, but can never activate
    // a module. Only the native host's explicit ready result is usable.
    return AndroidOptionalPlugin(
      id: definition.id,
      name: definition.name,
      packageName: definition.packageName,
      installed: installed,
      compatible: installed && compatible && reason == 'ready',
      reason: reason,
      version: version as String?,
    );
  }

  static List<AndroidOptionalPlugin> parseList(Iterable<dynamic> items) {
    final seen = <String>{};
    final result = <AndroidOptionalPlugin>[];
    for (final item in items) {
      if (item is! Map) {
        throw const FormatException('Plugin status entry is not an object');
      }
      final plugin = AndroidOptionalPlugin.fromMap(item);
      if (!seen.add(plugin.id)) {
        throw FormatException('Duplicate plugin status: ${plugin.id}');
      }
      result.add(plugin);
    }
    return List.unmodifiable(result);
  }
}
