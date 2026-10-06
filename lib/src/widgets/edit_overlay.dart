import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../controller/node_editor_controller.dart';
import '../geometry/edge_path.dart';
import '../model/edge.dart';
import '../model/node.dart';
import '../model/port.dart';
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

  /// Radio (en pantalla) de los tiradores para crear conectores.
  static const double connectorHandleRadius = 6;

  /// Distancia (en pantalla) del borde del nodo al centro de su tirador.
  static const double connectorHandleGap = 13;

  /// Tiradores para crear conectores de un nodo: uno por lado, justo fuera
  /// del borde (así no se confunden con redimensionar; si coinciden con un
  /// puerto gana el más cercano al puntero).
  static List<(PortSide, Offset)> connectorHandles(Rect r, double scale) {
    final g = connectorHandleGap / scale;
    return [
      (PortSide.top, r.topCenter - Offset(0, g)),
      (PortSide.right, r.centerRight + Offset(g, 0)),
      (PortSide.bottom, r.bottomCenter + Offset(0, g)),
      (PortSide.left, r.centerLeft - Offset(g, 0)),
    ];
  }

  /// La única conexión `(edge, null)` o enlace de jerarquía `(null, hijo)`
  /// seleccionado, si no hay nada más seleccionado.
  static (EdgeData?, String?)? singleSelection(NodeEditorController c) {
    if (c.selectedNodeIds.isNotEmpty) return null;
    final edges = c.selectedEdgeIds, links = c.selectedLinkIds;
    if (edges.length + links.length != 1) return null;
    if (edges.isNotEmpty) {
      final e = c.edge(edges.first);
      return e == null ? null : (e, null);
    }
    return (null, links.first);
  }

  /// Centro (en el mundo) del botón de borrar de [e] (`null` = enlace de
  /// jerarquía, que no tiene etiqueta).
  static Offset deleteButtonCenter(
      EdgeData? e, EdgeGeometry g, double scale, bool labelsVisible) {
    final hasLabel = labelsVisible && e?.label != null && e!.label!.isNotEmpty;
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
    this.connectorHandleNodes = const [],
    Listenable? effects,
  }) : super(
          repaint: Listenable.merge([
            state,
            if (effects != null) effects,
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

  /// Nodos que muestran tiradores para crear conectores (además del que
  /// está bajo el ratón, que viene en [state]).
  final List<String> connectorHandleNodes;

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
    if (edgeEditing) {
      _paintSelectedEdges(canvas, s);
      _paintSelectedLinks(canvas, s);
      _paintSingleDelete(canvas, s);
    }
    if (nodeResize) _paintResize(canvas, s);
    _paintConnectorHandles(canvas, s);
    _paintGuides(canvas, s);

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

  void _paintConnectorHandles(Canvas canvas, double s) {
    if (state.handlesHidden) return;
    final ids = <String>{
      ...connectorHandleNodes,
      if (state.handleNodeId != null) state.handleNodeId!,
    };
    for (final id in ids) {
      if (!controller.containsNode(id) || controller.isHidden(id)) continue;
      final rect = renderer.rectOf(id);
      for (final (side, c) in EditHandles.connectorHandles(rect, s)) {
        final hot = state.handleNodeId == id && state.hoverHandle == side;
        final r = EditHandles.connectorHandleRadius * (hot ? 1.3 : 1) / s;
        _fill.color = hot ? theme.accentColor : theme.nodeColor;
        canvas.drawCircle(c, r, _fill);
        _stroke
          ..color = theme.accentColor
          ..strokeWidth = 1.5 / s;
        canvas.drawCircle(c, r, _stroke);
        // "+"
        final arm = r * 0.5;
        _stroke
          ..color = hot ? theme.nodeColor : theme.accentColor
          ..strokeWidth = 1.6 / s;
        canvas
          ..drawLine(c - Offset(arm, 0), c + Offset(arm, 0), _stroke)
          ..drawLine(c - Offset(0, arm), c + Offset(0, arm), _stroke);
      }
    }
  }

  void _paintHover(Canvas canvas, double s) {
    final linkId = state.hoverLinkId;
    if (linkId != null && !controller.isLinkSelected(linkId)) {
      final g = renderer.linkGeometryOf(linkId);
      if (g != null) _paintGlow(canvas, g, theme.hierarchyEdgeWidth, s);
    }
    final id = state.hoverEdgeId;
    if (id == null || controller.isEdgeSelected(id)) return;
    final e = controller.edge(id);
    if (e == null) return;
    final g = renderer.geometryOf(e);
    if (g == null) return;
    _paintGlow(canvas, g, e.width ?? theme.edgeWidth, s);
  }

  void _paintGlow(Canvas canvas, EdgeGeometry g, double w, double s) {
    _stroke
      ..strokeWidth = w + 8 / s
      ..color = theme.edgeSelectedColor.withValues(alpha: 0.22);
    canvas.drawPath(g.path, _stroke);
    _stroke
      ..strokeWidth = w * 1.4
      ..color = theme.edgeSelectedColor.withValues(alpha: 0.9);
    canvas.drawPath(g.path, _stroke);
    if (edgeEditing) _paintEndHandles(canvas, g, s);
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
      _paintEndHandles(canvas, g, s);
    }
  }

  void _paintSelectedLinks(Canvas canvas, double s) {
    final ids = controller.selectedLinkIds;
    if (ids.isEmpty || ids.length > EditHandles.maxEdgeHandles) return;
    for (final id in ids) {
      if (id == state.reconnectingLinkId) continue;
      final g = renderer.linkGeometryOf(id);
      if (g == null) continue;
      _stroke
        ..strokeWidth = theme.hierarchyEdgeWidth + 8 / s
        ..color = theme.edgeSelectedColor.withValues(alpha: 0.18);
      canvas.drawPath(g.path, _stroke);
      _paintEndHandles(canvas, g, s);
    }
  }

  /// Botón de borrar cuando hay exactamente una conexión o enlace
  /// seleccionado (y ningún nodo).
  void _paintSingleDelete(Canvas canvas, double s) {
    final single = EditHandles.singleSelection(controller);
    if (single == null) return;
    final (edge, link) = single;
    if (edge != null) {
      if (edge.id == state.reconnectingEdgeId) return;
      final g = renderer.geometryOf(edge);
      if (g != null) _paintDeleteButton(canvas, edge, g, s);
    } else if (link != state.reconnectingLinkId) {
      final g = renderer.linkGeometryOf(link!);
      if (g != null) _paintDeleteButton(canvas, null, g, s);
    }
  }

  void _paintGuides(Canvas canvas, double s) {
    final guides = state.guides;
    if (guides.isEmpty) return;
    _stroke
      ..strokeWidth = 1 / s
      ..color = theme.alignmentGuideColor;
    _fill.color = theme.alignmentGuideColor;
    final ext = 12 / s, dot = 2.2 / s;
    for (final g in guides) {
      final a = g.vertical
          ? Offset(g.position, g.start - ext)
          : Offset(g.start - ext, g.position);
      final b = g.vertical
          ? Offset(g.position, g.end + ext)
          : Offset(g.end + ext, g.position);
      canvas.drawLine(a, b, _stroke);
      canvas.drawCircle(a, dot, _fill);
      canvas.drawCircle(b, dot, _fill);
    }
  }

  void _paintEndHandles(Canvas canvas, EdgeGeometry g, double s) {
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

  void _paintDeleteButton(
      Canvas canvas, EdgeData? e, EdgeGeometry g, double s) {
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
    final rect = renderer.rectOf(id);
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
      old.canResize != canResize ||
      !listEquals(old.connectorHandleNodes, connectorHandleNodes);
}
