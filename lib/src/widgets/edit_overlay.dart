import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../controller/node_editor_controller.dart';
import '../geometry/edge_path.dart';
import '../model/edge.dart';
import '../model/node.dart';
import '../theme/node_editor_theme.dart';
import 'painters.dart';
import 'scene_renderer.dart';

/// Medidas (en píxeles de pantalla) de los controles de edición.
abstract final class EditHandles {
  /// Radio del botón de borrar de una conexión seleccionada.
  static const double deleteButtonRadius = 11;

  /// Lado de los cuadrados de las esquinas del nodo seleccionado.
  static const double cornerSize = 9;

  /// Máximo de conexiones seleccionadas que muestran tiradores.
  static const int maxEdgeHandles = 24;

  /// Centro (en el mundo) del botón de borrar de [e].
  static Offset deleteButtonCenter(
      EdgeData e, EdgeGeometry g, double scale, bool labelsVisible) {
    final hasLabel = labelsVisible && e.label != null && e.label!.isNotEmpty;
    // Con etiqueta, el botón va justo debajo para no taparla.
    return hasLabel
        ? g.labelPosition + Offset(0, 14 + deleteButtonRadius / scale)
        : g.labelPosition;
  }
}

/// Pinta las ayudas de edición por encima de los nodos: resaltado de la
/// conexión bajo el ratón, tiradores de las conexiones seleccionadas, botón
/// de borrar, esquinas de redimensionado, tamaño mientras se redimensiona y
/// la vista previa de lo que se va a soltar.
///
/// Sólo trabaja si hay algo que mostrar, así que en reposo no cuesta nada.
class EditOverlayPainter<T> extends CustomPainter {
  EditOverlayPainter({
    required this.controller,
    required this.renderer,
    required this.state,
    required this.theme,
    required this.edgeEditing,
    required this.nodeResize,
    required this.labelMinScale,
    required this.canResize,
  }) : super(
          repaint: Listenable.merge([
            state,
            controller.viewport,
            controller.geometry,
            controller.selection,
            controller.edgesSignal,
          ]),
        );

  final NodeEditorController<T> controller;
  final SceneRenderer<T> renderer;
  final InteractionState state;
  final NodeEditorTheme theme;
  final bool edgeEditing;
  final bool nodeResize;
  final double labelMinScale;
  final bool Function(NodeData<T> node) canResize;

  static final Paint _fill = Paint();
  static final Paint _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  @override
  void paint(Canvas canvas, Size size) {
    final vp = controller.viewport;
    final s = vp.scale;
    canvas.save();
    canvas.translate(vp.offset.dx, vp.offset.dy);
    canvas.scale(s);

    _paintDropPreview(canvas, s);
    _paintHover(canvas, s);
    if (edgeEditing) _paintSelectedEdges(canvas, s);
    if (nodeResize) _paintResize(canvas, s);

    canvas.restore();
  }

  void _paintDropPreview(Canvas canvas, double s) {
    final r = state.dropPreview;
    if (r == null) return;
    final rr = RRect.fromRectAndRadius(r, Radius.circular(theme.nodeRadius));
    _fill.color = theme.connectionPreviewColor.withValues(alpha: 0.12);
    canvas.drawRRect(rr, _fill);
    _stroke
      ..strokeWidth = 1.5 / s
      ..color = theme.connectionPreviewColor;
    canvas.drawPath(dashPath(Path()..addRRect(rr), [6 / s, 4 / s]), _stroke);
  }

  void _paintHover(Canvas canvas, double s) {
    final id = state.hoverEdgeId;
    if (id == null || controller.isEdgeSelected(id)) return;
    final e = controller.edge(id);
    if (e == null) return;
    final g = renderer.geometryOf(e);
    if (g == null) return;
    final w = e.width ?? theme.edgeWidth;
    _stroke
      ..strokeWidth = w + 8 / s
      ..color = theme.edgeSelectedColor.withValues(alpha: 0.22);
    canvas.drawPath(g.path, _stroke);
    _stroke
      ..strokeWidth = w * 1.4
      ..color = theme.edgeSelectedColor.withValues(alpha: 0.9);
    canvas.drawPath(g.path, _stroke);
    if (edgeEditing) _paintEndHandles(canvas, e, g, s);
  }

  void _paintSelectedEdges(Canvas canvas, double s) {
    final ids = controller.selectedEdgeIds;
    if (ids.isEmpty || ids.length > EditHandles.maxEdgeHandles) return;
    for (final id in ids) {
      if (id == state.reconnectingEdgeId) continue;
      final e = controller.edge(id);
      if (e == null) continue;
      final g = renderer.geometryOf(e);
      if (g == null) continue;
      // Halo suave para que la selección se distinga bien.
      _stroke
        ..strokeWidth = (e.width ?? theme.edgeWidth) + 8 / s
        ..color = theme.edgeSelectedColor.withValues(alpha: 0.18);
      canvas.drawPath(g.path, _stroke);
      _paintEndHandles(canvas, e, g, s);
    }
    if (ids.length == 1 && controller.selectedNodeIds.isEmpty) {
      final e = controller.edge(ids.first);
      final g = e == null ? null : renderer.geometryOf(e);
      if (e != null && g != null && e.id != state.reconnectingEdgeId) {
        _paintDeleteButton(canvas, e, g, s);
      }
    }
  }

  void _paintEndHandles(Canvas canvas, EdgeData e, EdgeGeometry g, double s) {
    final r = theme.portRadius + 3;
    for (final p in [g.polyline.first, g.polyline.last]) {
      _fill.color = theme.nodeColor;
      canvas.drawCircle(p, r, _fill);
      _stroke
        ..strokeWidth = 2
        ..color = theme.edgeSelectedColor;
      canvas.drawCircle(p, r, _stroke);
      _fill.color = theme.edgeSelectedColor;
      canvas.drawCircle(p, r * 0.45, _fill);
    }
  }

  void _paintDeleteButton(Canvas canvas, EdgeData e, EdgeGeometry g, double s) {
    final c = EditHandles.deleteButtonCenter(e, g, s, s >= labelMinScale);
    final r = EditHandles.deleteButtonRadius / s;
    _fill.color = theme.invalidConnectionColor;
    canvas.drawCircle(c, r, _fill);
    _stroke
      ..strokeWidth = 2 / s
      ..color = theme.nodeColor;
    canvas.drawCircle(c, r, _stroke);
    final k = r * 0.38;
    _stroke
      ..strokeWidth = 1.8 / s
      ..color = const Color(0xFFFFFFFF);
    canvas.drawLine(c + Offset(-k, -k), c + Offset(k, k), _stroke);
    canvas.drawLine(c + Offset(k, -k), c + Offset(-k, k), _stroke);
  }

  void _paintResize(Canvas canvas, double s) {
    final resizing = state.resizingNodeId;
    String? id = resizing;
    if (id == null) {
      final sel = controller.selectedNodeIds;
      if (sel.length != 1) return;
      id = sel.first;
      final n = controller.node(id);
      if (n == null || n.locked || !canResize(n)) return;
    }
    if (controller.isHidden(id)) return;
    final rect = controller.rectOf(id);
    final half = EditHandles.cornerSize / 2 / s;
    for (final p in [
      rect.topLeft,
      rect.topRight,
      rect.bottomLeft,
      rect.bottomRight
    ]) {
      final r = Rect.fromCenter(center: p, width: half * 2, height: half * 2);
      _fill.color = theme.nodeColor;
      canvas.drawRect(r, _fill);
      _stroke
        ..strokeWidth = 1.5 / s
        ..color = theme.nodeSelectedBorderColor;
      canvas.drawRect(r, _stroke);
    }
    if (resizing != null) _paintSizeLabel(canvas, rect, s);
  }

  void _paintSizeLabel(Canvas canvas, Rect rect, double s) {
    final text = '${rect.width.round()} × ${rect.height.round()}';
    final tp = TextPainter(
      text: TextSpan(
          text: text,
          style: theme.edgeLabelStyle
              .copyWith(fontSize: (theme.edgeLabelStyle.fontSize ?? 11) / s)),
      textDirection: TextDirection.ltr,
    )..layout();
    final pad = Offset(6 / s, 3 / s);
    final box = Rect.fromLTWH(
      rect.right - tp.width - pad.dx * 2,
      rect.bottom + 8 / s,
      tp.width + pad.dx * 2,
      tp.height + pad.dy * 2,
    );
    final rr =
        RRect.fromRectAndRadius(box, Radius.circular(math.max(4 / s, 1)));
    _fill.color = theme.edgeLabelBackground;
    canvas.drawRRect(rr, _fill);
    _stroke
      ..strokeWidth = 1 / s
      ..color = theme.nodeSelectedBorderColor;
    canvas.drawRRect(rr, _stroke);
    tp.paint(canvas, box.topLeft + pad);
    tp.dispose();
  }

  @override
  bool shouldRepaint(EditOverlayPainter<T> old) =>
      !identical(old.theme, theme) ||
      !identical(old.controller, controller) ||
      !identical(old.renderer, renderer) ||
      !identical(old.state, state) ||
      old.edgeEditing != edgeEditing ||
      old.nodeResize != nodeResize ||
      old.labelMinScale != labelMinScale ||
      old.canResize != canResize;
}
