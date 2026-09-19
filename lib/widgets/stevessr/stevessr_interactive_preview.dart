import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../models/stevessr_render_params.dart';
import 'stevessr_canvas.dart';

/// What a pointer gesture should edit. Canvas gestures are viewport-only and
/// never change the pixels or coordinates used by the exported image.
enum StevessrEditTarget { canvas, character, bubble }

/// WYSIWYG editor surrounding the export-only [StevessrCanvas].
///
/// The selection outline and resize handle deliberately live *outside* the
/// canvas' RepaintBoundary so they cannot leak into PNG/WebP screenshots.
class StevessrInteractivePreview extends StatefulWidget {
  const StevessrInteractivePreview({
    super.key,
    required this.params,
    required this.logicalWidth,
    required this.repaintBoundaryKey,
    required this.onCharacterRectChanged,
    required this.onBubbleRectChanged,
  });

  final StevessrRenderParams params;
  final double logicalWidth;
  final GlobalKey repaintBoundaryKey;
  final ValueChanged<StevessrRect> onCharacterRectChanged;
  final ValueChanged<StevessrRect> onBubbleRectChanged;

  @override
  State<StevessrInteractivePreview> createState() =>
      _StevessrInteractivePreviewState();
}

class _StevessrInteractivePreviewState
    extends State<StevessrInteractivePreview> {
  final TransformationController _viewport = TransformationController();
  StevessrEditTarget _target = StevessrEditTarget.character;
  StevessrRect? _gestureRect;
  Offset _gestureFocalPoint = Offset.zero;
  Offset? _resizeLastGlobalPoint;
  bool _resizing = false;
  double _gestureViewportScale = 1;
  double _sceneScaleX = 1;
  double _sceneScaleY = 1;
  Size _viewportSize = Size.zero;

  @override
  void dispose() {
    _viewport.dispose();
    super.dispose();
  }

  StevessrRect get _selectedRect => _target == StevessrEditTarget.character
      ? widget.params.characterRect
      : widget.params.bubbleRect;

  void _commitRect(StevessrRect rect) {
    if (_target == StevessrEditTarget.character) {
      widget.onCharacterRectChanged(rect);
    } else if (_target == StevessrEditTarget.bubble) {
      widget.onBubbleRectChanged(rect);
    }
  }

  void _startElementGesture(ScaleStartDetails details) {
    if (_resizing) return;
    _gestureRect = _selectedRect;
    _gestureFocalPoint = details.focalPoint;
    _gestureViewportScale = _viewport.value.getMaxScaleOnAxis();
  }

  void _updateElementGesture(ScaleUpdateDetails details) {
    if (_resizing) return;
    final start = _gestureRect;
    if (start == null) return;
    final dx =
        (details.focalPoint.dx - _gestureFocalPoint.dx) /
        (_sceneScaleX * _gestureViewportScale);
    final dy =
        (details.focalPoint.dy - _gestureFocalPoint.dy) /
        (_sceneScaleY * _gestureViewportScale);
    // Scaling around the original center prevents a two-finger pinch from
    // jumping to a new position. Focal-point translation is applied once.
    final width = start.width * details.scale;
    final height = start.height * details.scale;
    _commitRect(
      start.copyWith(
        x: start.x + dx - (width - start.width) / 2,
        y: start.y + dy - (height - start.height) / 2,
        width: width,
        height: height,
      ),
    );
  }

  void _resizeWithPointer(PointerMoveEvent event) {
    final previous = _resizeLastGlobalPoint ?? event.position;
    _resizeLastGlobalPoint = event.position;
    final delta = event.position - previous;
    final scale = _viewport.value.getMaxScaleOnAxis();
    final current = _selectedRect;
    // Use global pointer movement to avoid applying the viewport zoom twice.
    final dx = delta.dx / (_sceneScaleX * scale);
    final dy = delta.dy / (_sceneScaleY * scale);
    // Retain the element's aspect ratio when resizing by its bottom-right
    // handle. A two-finger pinch on the element also scales uniformly.
    final ratio = current.width / current.height;
    // Follow the dominant drag axis so moving just left *or* just up can
    // shrink the object, without forcing both pointer axes to move at once.
    final effectiveDelta = dx.abs() >= (dy * ratio).abs() ? dx : dy * ratio;
    final width = math.max(1.0, current.width + effectiveDelta);
    _commitRect(current.copyWith(width: width, height: width / ratio));
  }

  void _zoom(double factor) {
    final scale = _viewport.value.getMaxScaleOnAxis();
    final next = (scale * factor).clamp(0.25, 6.0).toDouble();
    final applied = next / scale;
    final center = Offset(_viewportSize.width / 2, _viewportSize.height / 2);
    final zoom = Matrix4.identity()
      ..setEntry(0, 0, applied)
      ..setEntry(1, 1, applied)
      ..setEntry(0, 3, center.dx * (1 - applied))
      ..setEntry(1, 3, center.dy * (1 - applied));
    _viewport.value = zoom..multiply(_viewport.value);
  }

  Widget _buildElementOverlay(
    StevessrRect rect,
    double scaleX,
    double scaleY,
    Color color,
  ) {
    return Positioned(
      left: rect.x * scaleX,
      top: rect.y * scaleY,
      width: rect.width * scaleX,
      height: rect.height * scaleY,
      child: GestureDetector(
        key: const ValueKey('stevessr-element-overlay'),
        behavior: HitTestBehavior.opaque,
        onScaleStart: _startElementGesture,
        onScaleUpdate: _updateElementGesture,
        onScaleEnd: (_) => _gestureRect = null,
        child: DecoratedBox(
          decoration: BoxDecoration(border: Border.all(color: color, width: 2)),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                right: 0,
                bottom: 0,
                child: Listener(
                  key: const ValueKey('stevessr-element-resize'),
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (event) {
                    _resizing = true;
                    _resizeLastGlobalPoint = event.position;
                  },
                  onPointerMove: _resizeWithPointer,
                  onPointerUp: (_) {
                    _resizing = false;
                    _resizeLastGlobalPoint = null;
                  },
                  onPointerCancel: (_) {
                    _resizing = false;
                    _resizeLastGlobalPoint = null;
                  },
                  child: Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(8),
                      ),
                    ),
                    child: const Icon(
                      Icons.open_in_full,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final p = widget.params;
    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Row(
            children: [
              for (final target in StevessrEditTarget.values) ...[
                ChoiceChip(
                  label: Text(switch (target) {
                    StevessrEditTarget.canvas => '画布',
                    StevessrEditTarget.character => '角色',
                    StevessrEditTarget.bubble => '气泡',
                  }),
                  selected: _target == target,
                  onSelected: (_) => setState(() => _target = target),
                ),
                const SizedBox(width: 6),
              ],
              const SizedBox(width: 12),
              IconButton(
                tooltip: '缩小画布视图',
                onPressed: () => _zoom(1 / 1.25),
                icon: const Icon(Icons.zoom_out),
              ),
              IconButton(
                tooltip: '放大画布视图',
                onPressed: () => _zoom(1.25),
                icon: const Icon(Icons.zoom_in),
              ),
              IconButton(
                tooltip: '重置画布视图',
                onPressed: () => _viewport.value = Matrix4.identity(),
                icon: const Icon(Icons.center_focus_strong),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            _target == StevessrEditTarget.canvas
                ? '拖动空白处平移画布，双指或滚轮缩放；画布视图不影响导出。'
                : '拖动选中元素移动，拖动右下角调整大小，双指捏合可缩放；切换到「画布」可平移和缩放画布。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              _viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
              final width = math.max(
                1.0,
                math.min(
                  widget.logicalWidth,
                  math.min(
                    constraints.maxWidth - 24,
                    (constraints.maxHeight - 24) * p.width / p.height,
                  ),
                ),
              );
              final height = width * p.height / p.width;
              _sceneScaleX = width / p.width;
              _sceneScaleY = height / p.height;
              return ClipRect(
                child: ColoredBox(
                  color: scheme.surfaceContainerLowest,
                  child: InteractiveViewer(
                    key: const ValueKey('stevessr-viewport'),
                    transformationController: _viewport,
                    constrained: false,
                    alignment: Alignment.center,
                    minScale: 0.25,
                    maxScale: 6.0,
                    // Do not let the parent viewport's ScaleGestureRecognizer
                    // compete with object drag/pinch recognizers.
                    panEnabled: _target == StevessrEditTarget.canvas,
                    scaleEnabled: _target == StevessrEditTarget.canvas,
                    boundaryMargin: const EdgeInsets.all(1200),
                    child: SizedBox(
                      width: width,
                      height: height,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          StevessrCanvas(
                            key: ValueKey(
                              'canvas-${p.character.key}-${p.expression.key}',
                            ),
                            repaintBoundaryKey: widget.repaintBoundaryKey,
                            params: p,
                            logicalWidth: width,
                          ),
                          if (_target != StevessrEditTarget.canvas)
                            _buildElementOverlay(
                              _selectedRect,
                              _sceneScaleX,
                              _sceneScaleY,
                              _target == StevessrEditTarget.character
                                  ? scheme.primary
                                  : scheme.tertiary,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
