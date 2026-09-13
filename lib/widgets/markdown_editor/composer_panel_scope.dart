import 'package:flutter/material.dart';

typedef ComposerPanelBuilder = Widget Function(ValueChanged<Object?> close);

/// Compatibility scope for fork composer integrations that still open
/// metadata panels through the legacy panel handoff API.
class ComposerPanelScope extends InheritedWidget {
  const ComposerPanelScope({
    super.key,
    required this.open,
    required super.child,
  });

  final Future<Object?> Function(ComposerPanelBuilder builder) open;

  static ComposerPanelScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ComposerPanelScope>();

  @override
  bool updateShouldNotify(ComposerPanelScope oldWidget) => open != oldWidget.open;
}
