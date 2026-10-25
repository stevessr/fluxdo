enum PluginRuntime { native, flutter }

class PluginDefinition {
  const PluginDefinition({
    required this.id,
    required this.name,
    required this.packageName,
    required this.runtime,
    required this.operations,
    this.activityClass,
  });

  final String id;
  final String name;
  final String packageName;
  final PluginRuntime runtime;
  final Set<String> operations;
  final String? activityClass;

  bool get hasNativeActivity =>
      runtime == PluginRuntime.native && activityClass != null;
}
