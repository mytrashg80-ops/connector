import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../controller/node_editor_controller.dart';
import '../theme/node_editor_theme.dart';

/// Minimapa navegable. Los nodos se graban en una `Picture` cacheada que sólo
/// se regenera cuando cambia el grafo: desplazar la cámara apenas cuesta.
class NodeEditorMinimap<T> extends StatefulWidget {
  const NodeEditorMinimap({
    super.key,
    required this.controller,
    this.theme,
    this.size = const Size(200, 136),
    this.borderRadius = 10,
  });

  final NodeEditorController<T> controller;
  final NodeEditorTheme? theme;
  final Size size;
  final double borderRadius;

  @override
  State<NodeEditorMinimap<T>> createState() => _NodeEditorMinimapState<T>();
}

class _MinimapCache {
  ui.Picture? picture;
  Object? key;
  Rect world = Rect.zero;
  double scale = 1;
  Offset origin = Offset.zero;

  void dispose() {
    picture?.dispose();
    picture = null;
  }
}

class _NodeEditorMinimapState<T> extends State<NodeEditorMinimap<T>> {
  final _MinimapCache _cache = _MinimapCache();
  late Listenable _repaint = _changesOf(widget.controller);

  static Listenable _changesOf(NodeEditorController<Object?> c) =>
      Listenable.merge([c.geometry, c.structure, c.selection, c.viewport]);

  @override
  void didUpdateWidget(NodeEditorMinimap<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      _repaint = _changesOf(widget.controller);
      _cache.dispose();
      _cache.key = null;
    }
  }

  @override
  void dispose() {
    _cache.dispose();
    super.dispose();
  }

  void _navigate(Offset local) {
    if (_cache.scale <= 0) return;
    final world = (local - _cache.origin) / _cache.scale + _cache.world.topLeft;
    widget.controller.viewport.centerOn(world);
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme ?? NodeEditorTheme.of(context);
    final c = widget.controller;
    return SizedBox.fromSize(
      size: widget.size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.minimapBackground,
          borderRadius: BorderRadius.circular(widget.borderRadius),
          border: Border.all(color: theme.minimapBorderColor),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => _navigate(d.localPosition),
            onPanStart: (d) => _navigate(d.localPosition),
            onPanUpdate: (d) => _navigate(d.localPosition),
            child: RepaintBoundary(
              child: CustomPaint(
                size: widget.size,
                painter: _MinimapPainter<T>(
                  controller: c,
                  theme: theme,
                  cache: _cache,
                  repaint: _repaint,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MinimapPainter<T> extends CustomPainter {
  _MinimapPainter({
    required this.controller,
    required this.theme,
    required this.cache,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final NodeEditorController<T> controller;
  final NodeEditorTheme theme;
  final _MinimapCache cache;

  @override
  void paint(Canvas canvas, Size size) {
    final c = controller;
    final key = (
      c.geometryRevision,
      c.structureRevision,
      c.selectionRevision,
      size,
      theme,
    );
    if (cache.key != key || cache.picture == null) {
      _record(size);
      cache.key = key;
    }
    canvas.drawPicture(cache.picture!);

    // Rectángulo de la vista actual.
    final v = c.viewport.visibleWorldRect;
    final r = Rect.fromPoints(
      (v.topLeft - cache.world.topLeft) * cache.scale + cache.origin,
      (v.bottomRight - cache.world.topLeft) * cache.scale + cache.origin,
    );
    canvas.drawRect(r, Paint()..color = theme.minimapViewportColor);
    canvas.drawRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = theme.minimapSelectedNodeColor.withValues(alpha: 0.6),
    );
  }

  void _record(Size size) {
    final c = controller;
    var world = c.bounds ?? (Offset.zero & const Size(400, 300));
    final pad = math.max(world.width, world.height) * 0.08 + 40;
    world = world.inflate(pad);
    final scale =
        math.min(size.width / world.width, size.height / world.height);
    final origin = Offset(
      (size.width - world.width * scale) / 2,
      (size.height - world.height * scale) / 2,
    );
    cache
      ..world = world
      ..scale = scale
      ..origin = origin;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final normal = Paint()..color = theme.minimapNodeColor;
    final selected = Paint()..color = theme.minimapSelectedNodeColor;
    final radius = Radius.circular(math.max(1.0, theme.nodeRadius * scale));
    for (final n in c.nodes) {
      if (c.isHidden(n.id)) continue;
      final r = c.rectOf(n.id);
      final mr = Rect.fromLTWH(
        (r.left - world.left) * scale + origin.dx,
        (r.top - world.top) * scale + origin.dy,
        math.max(1.5, r.width * scale),
        math.max(1.5, r.height * scale),
      );
      final color = n.color ?? theme.nodeTypes[n.type]?.color;
      final paint = c.isNodeSelected(n.id)
          ? selected
          : color != null
              ? (Paint()..color = color.withValues(alpha: 0.75))
              : normal;
      canvas.drawRRect(RRect.fromRectAndRadius(mr, radius), paint);
    }
    cache.picture?.dispose();
    cache.picture = recorder.endRecording();
  }

  @override
  bool shouldRepaint(_MinimapPainter<T> old) =>
      !identical(old.controller, controller) || !identical(old.theme, theme);
}
