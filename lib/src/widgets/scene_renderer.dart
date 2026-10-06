import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../controller/node_editor_controller.dart';
import '../geometry/edge_path.dart';
import '../geometry/node_geometry.dart';
import '../model/edge.dart';
import '../model/port.dart';
import '../theme/node_editor_theme.dart';

class _CachedEdge {
  _CachedEdge(this.a, this.aSide, this.b, this.bSide, this.curve, this.via,
      this.geometry);
  final Offset a;
  final PortSide aSide;
  final Offset b;
  final PortSide bSide;
  final EdgeCurve curve;
  final Offset? via;
  final EdgeGeometry geometry;
  Path? dashed;

  bool matches(Offset a, PortSide aSide, Offset b, PortSide bSide,
          EdgeCurve curve, Offset? via) =>
      this.a == a &&
      this.b == b &&
      this.aSide == aSide &&
      this.bSide == bSide &&
      this.curve == curve &&
      this.via == via;
}

/// Pinta conexiones, enlaces de jerarquía y la vista simplificada (LOD) de
/// los nodos. Cachea la geometría de cada conexión y sólo la recalcula cuando
/// se mueve alguno de sus extremos.
class SceneRenderer<T> {
  SceneRenderer(this.controller);

  NodeEditorController<T> controller;
  NodeEditorTheme? _theme;
  bool showHierarchyLinks = true;
  Axis hierarchyAxis = Axis.vertical;
  double labelMinScale = 0.45;

  /// Conexión que no se pinta (la que se está reconectando: la dibuja la capa
  /// de interacción).
  String? hiddenEdgeId;

  /// Enlace de jerarquía (id del hijo) que no se pinta.
  String? hiddenLinkId;

  final Map<String, _CachedEdge> _edgeCache = {};
  final Map<String, _CachedEdge> _hierarchyCache = {};
  final Map<String, TextPainter> _labelCache = {};

  final Paint _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  final Paint _fill = Paint();
  final Paint _labelBorder = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;

  NodeEditorTheme get theme => _theme!;
  NodeEditorTheme? get currentTheme => _theme;
  set theme(NodeEditorTheme value) {
    if (identical(_theme, value)) return;
    _theme = value;
    _edgeCache.clear();
    _hierarchyCache.clear();
    _disposeLabels();
  }

  void _disposeLabels() {
    for (final tp in _labelCache.values) {
      tp.dispose();
    }
    _labelCache.clear();
  }

  void dispose() => _disposeLabels();

  /// `true` si hay conexiones animadas.
  bool get hasAnimatedEdges => controller.edges.any((e) => e.animated);

  // ------------------------------------------------------------- geometría

  /// Punto de referencia de los puntos de paso: el medio entre los centros
  /// de ambos nodos.
  Offset referenceBetween(String a, String b) =>
      (controller.rectOf(a).center + controller.rectOf(b).center) / 2;

  /// Punto de paso (en el mundo) de una conexión doblada por el usuario.
  Offset? viaOf(EdgeData e) {
    final bend = e.bend;
    if (bend == null) return null;
    return referenceBetween(e.sourceNodeId, e.targetNodeId) + bend;
  }

  /// Rectángulo que contiene seguro la conexión (descarte barato).
  Rect _roughBox(String a, String b, Offset? via) {
    var box = controller.rectOf(a).expandToInclude(controller.rectOf(b));
    if (via != null) {
      box = box.expandToInclude(Rect.fromCircle(center: via, radius: 1));
    }
    return box.inflate(260);
  }

  /// Extremo de una conexión: posición y lado por el que sale/entra.
  (Offset, PortSide)? endpoint(EdgeData e, {required bool source}) {
    final nodeId = source ? e.sourceNodeId : e.targetNodeId;
    final otherId = source ? e.targetNodeId : e.sourceNodeId;
    final portId = source ? e.sourcePortId : e.targetPortId;
    final n = controller.node(nodeId);
    if (n == null) return null;
    final rect = controller.rectOf(nodeId);
    if (portId != null) {
      final port = n.port(portId);
      if (port != null) {
        final local = NodeGeometry.portLocalPosition(n, rect.size, portId,
            topInset: theme.nodeHeaderHeight);
        return (rect.topLeft + local, port.side);
      }
    }
    // Sin puerto: el lado que mira al otro nodo (o al punto de paso).
    final toward = viaOf(e) ?? controller.rectOf(otherId).center;
    return NodeGeometry.floatingAnchor(rect, toward);
  }

  /// Geometría (cacheada) de una conexión.
  EdgeGeometry? geometryOf(EdgeData e) {
    final s = endpoint(e, source: true);
    final t = endpoint(e, source: false);
    if (s == null || t == null) return null;
    final curve = e.curve ?? theme.edgeCurve;
    final via = viaOf(e);
    final c = _edgeCache[e.id];
    if (c != null && c.matches(s.$1, s.$2, t.$1, t.$2, curve, via)) {
      return c.geometry;
    }
    final g = buildEdgeGeometry(curve, s.$1, s.$2, t.$1, t.$2,
        cornerRadius: theme.edgeCornerRadius, via: via);
    _edgeCache[e.id] = _CachedEdge(s.$1, s.$2, t.$1, t.$2, curve, via, g);
    return g;
  }

  /// Geometría que tendría [e] sin punto de paso (para "enderezar" al
  /// arrastrar la línea de vuelta a su sitio).
  EdgeGeometry? straightGeometryOf(EdgeData e) {
    if (e.bend == null) return geometryOf(e);
    final plain = e.copyWith(clearBend: true);
    final s = endpoint(plain, source: true);
    final t = endpoint(plain, source: false);
    if (s == null || t == null) return null;
    return buildEdgeGeometry(e.curve ?? theme.edgeCurve, s.$1, s.$2, t.$1, t.$2,
        cornerRadius: theme.edgeCornerRadius);
  }

  /// Punto de paso (en el mundo) del enlace de [childId] con su padre.
  Offset? linkViaOf(String childId) {
    final n = controller.node(childId);
    final bend = n?.linkBend;
    if (bend == null) return null;
    return referenceBetween(n!.parentId!, childId) + bend;
  }

  /// `true` si el enlace de [childId] con su padre existe y se ve.
  bool hasVisibleLink(String childId) {
    if (!showHierarchyLinks) return false;
    final pid = controller.node(childId)?.parentId;
    return pid != null &&
        controller.node(pid) != null &&
        !controller.isHidden(childId);
  }

  /// Geometría del enlace de jerarquía de [childId] (va del padre al hijo).
  EdgeGeometry? linkGeometryOf(String childId, {bool straight = false}) {
    if (!hasVisibleLink(childId)) return null;
    final pid = controller.node(childId)!.parentId!;
    return _hierarchyGeometry(
        childId, controller.rectOf(pid), controller.rectOf(childId),
        via: straight ? null : linkViaOf(childId), cache: !straight);
  }

  /// Extremos del enlace de [childId]: (padre, hijo), con su lado.
  ((Offset, PortSide), (Offset, PortSide))? linkEnds(String childId) {
    final pid = controller.node(childId)?.parentId;
    if (pid == null || controller.node(pid) == null) return null;
    final (a, aSide, b, bSide) = _linkAnchors(
        controller.rectOf(pid), controller.rectOf(childId), linkViaOf(childId));
    return ((a, aSide), (b, bSide));
  }

  /// Anclajes de un enlace. Sin punto de paso, el padre sale hacia el hijo;
  /// con él, cada extremo sale por el lado que mira al punto (así la línea
  /// no atraviesa los nodos cuando se lleva por detrás de ellos).
  (Offset, PortSide, Offset, PortSide) _linkAnchors(
      Rect parent, Rect child, Offset? via) {
    final vertical = hierarchyAxis == Axis.vertical;
    if (vertical) {
      final down =
          child.top >= parent.bottom || child.center.dy >= parent.center.dy;
      final pDown = via == null ? down : via.dy >= parent.center.dy;
      final cUp = via == null ? down : via.dy <= child.center.dy;
      return (
        pDown ? parent.bottomCenter : parent.topCenter,
        pDown ? PortSide.bottom : PortSide.top,
        cUp ? child.topCenter : child.bottomCenter,
        cUp ? PortSide.top : PortSide.bottom,
      );
    }
    final right = child.center.dx >= parent.center.dx;
    final pRight = via == null ? right : via.dx >= parent.center.dx;
    final cLeft = via == null ? right : via.dx <= child.center.dx;
    return (
      pRight ? parent.centerRight : parent.centerLeft,
      pRight ? PortSide.right : PortSide.left,
      cLeft ? child.centerLeft : child.centerRight,
      cLeft ? PortSide.left : PortSide.right,
    );
  }

  EdgeGeometry _hierarchyGeometry(String childId, Rect parent, Rect child,
      {Offset? via, bool cache = true}) {
    final (a, aSide, b, bSide) = _linkAnchors(parent, child, via);
    final curve = theme.hierarchyEdgeCurve;
    final c = _hierarchyCache[childId];
    if (cache && c != null && c.matches(a, aSide, b, bSide, curve, via)) {
      return c.geometry;
    }
    final g = buildEdgeGeometry(curve, a, aSide, b, bSide,
        cornerRadius: theme.edgeCornerRadius, via: via);
    if (cache) {
      _hierarchyCache[childId] = _CachedEdge(a, aSide, b, bSide, curve, via, g);
    }
    return g;
  }

  /// Conexión visible más cercana a [world] dentro de [tolerance].
  EdgeData? hitEdge(Offset world, double tolerance) {
    EdgeData? best;
    var bestD = tolerance;
    for (final e in controller.edges) {
      if (e.id == hiddenEdgeId ||
          controller.isHidden(e.sourceNodeId) ||
          controller.isHidden(e.targetNodeId)) {
        continue;
      }
      // Descarte barato (sin calcular la curva) para conexiones lejanas.
      final box = _roughBox(e.sourceNodeId, e.targetNodeId, viaOf(e))
          .inflate(tolerance);
      if (!box.contains(world)) continue;
      final g = geometryOf(e);
      if (g == null || !g.bounds.inflate(tolerance).contains(world)) continue;
      final d = g.distanceTo(world);
      if (d <= bestD) {
        bestD = d;
        best = e;
      }
    }
    return best;
  }

  /// Enlace de jerarquía (id del hijo) más cercano a [world].
  String? hitLink(Offset world, double tolerance) {
    if (!showHierarchyLinks) return null;
    String? best;
    var bestD = tolerance;
    for (final n in controller.nodes) {
      final pid = n.parentId;
      if (pid == null || n.id == hiddenLinkId) continue;
      if (controller.node(pid) == null || controller.isHidden(n.id)) continue;
      final box = _roughBox(pid, n.id, linkViaOf(n.id)).inflate(tolerance);
      if (!box.contains(world)) continue;
      final g = linkGeometryOf(n.id);
      if (g == null || !g.bounds.inflate(tolerance).contains(world)) continue;
      final d = g.distanceTo(world);
      if (d <= bestD) {
        bestD = d;
        best = n.id;
      }
    }
    return best;
  }

  void _purgeCaches() {
    if (_edgeCache.length > controller.edgeCount * 2 + 64) {
      _edgeCache.removeWhere((id, _) => controller.edge(id) == null);
    }
    if (_hierarchyCache.length > controller.nodeCount * 2 + 64) {
      _hierarchyCache.removeWhere((id, _) => controller.node(id) == null);
    }
    if (_labelCache.length > 512) _disposeLabels();
  }

  // ------------------------------------------------------------- pintado

  /// Pinta todo lo que cae dentro de [region] (coordenadas del mundo).
  void paint(
    Canvas canvas,
    Rect region, {
    required double scale,
    required bool lod,
    double dashPhase = 0,
  }) {
    _purgeCaches();
    if (showHierarchyLinks) _paintHierarchy(canvas, region, lod);
    _paintEdges(canvas, region, scale, lod, dashPhase);
    if (lod) _paintLodNodes(canvas, region);
  }

  void _paintHierarchy(Canvas canvas, Rect region, bool lod) {
    final t = theme;
    _stroke
      ..color = t.hierarchyEdgeColor
      ..strokeWidth = lod ? t.hierarchyEdgeWidth * 1.5 : t.hierarchyEdgeWidth;
    final baseWidth = _stroke.strokeWidth;
    for (final n in controller.nodes) {
      final pid = n.parentId;
      if (pid == null || n.id == hiddenLinkId) continue;
      if (controller.node(pid) == null) continue;
      if (controller.isHidden(n.id)) continue;
      final pr = controller.rectOf(pid);
      final cr = controller.rectOf(n.id);
      final via = linkViaOf(n.id);
      var box = pr.expandToInclude(cr);
      if (via != null) {
        box = box.expandToInclude(Rect.fromCircle(center: via, radius: 1));
      }
      if (!box.inflate(32).overlaps(region)) continue;
      final g = _hierarchyGeometry(n.id, pr, cr, via: via);
      final selected = controller.isLinkSelected(n.id);
      final accent = n.color ?? t.nodeTypes[n.type]?.color;
      if (selected) {
        _stroke.color = t.edgeSelectedColor;
      } else if (accent != null && !lod) {
        _stroke.color = Color.lerp(t.hierarchyEdgeColor, accent, 0.45)!;
      } else {
        _stroke.color = t.hierarchyEdgeColor;
      }
      _stroke.strokeWidth = selected ? baseWidth * 1.5 : baseWidth;
      if (t.hierarchyEdgeDashed && !lod) {
        final c = _hierarchyCache[n.id]!;
        canvas.drawPath(
            c.dashed ??= dashPath(g.path, t.edgeDashPattern), _stroke);
      } else {
        canvas.drawPath(g.path, _stroke);
      }
    }
  }

  void _paintEdges(
      Canvas canvas, Rect region, double scale, bool lod, double phase) {
    final t = theme;
    final selectedNodes = controller.selectedNodeIds;
    final showLabels = !lod && scale >= labelMinScale;
    final labels = <(EdgeData, EdgeGeometry, Color)>[];
    for (final e in controller.edges) {
      if (e.id == hiddenEdgeId ||
          controller.isHidden(e.sourceNodeId) ||
          controller.isHidden(e.targetNodeId)) {
        continue;
      }
      // Descarte barato antes de calcular la curva.
      if (!_roughBox(e.sourceNodeId, e.targetNodeId, viaOf(e))
          .overlaps(region)) {
        continue;
      }
      final g = geometryOf(e);
      if (g == null || !g.bounds.inflate(16).overlaps(region)) continue;

      final selected = controller.isEdgeSelected(e.id) ||
          selectedNodes.contains(e.sourceNodeId) ||
          selectedNodes.contains(e.targetNodeId);
      final color = selected
          ? t.edgeSelectedColor
          : (e.color ?? controller.sourcePortOf(e)?.color ?? t.edgeColor);
      final width = (e.width ?? t.edgeWidth) *
          (controller.isEdgeSelected(e.id) ? 1.5 : 1) *
          (lod ? 1.5 : 1);
      _stroke
        ..color = color
        ..strokeWidth = width;

      final dashed = e.dashed ?? t.edgeDashed;
      if (lod) {
        canvas.drawPath(g.path, _stroke);
      } else if (e.animated) {
        canvas.drawPath(
            dashPath(g.path, t.edgeDashPattern, phase: -phase), _stroke);
      } else if (dashed) {
        final c = _edgeCache[e.id]!;
        canvas.drawPath(
            c.dashed ??= dashPath(g.path, t.edgeDashPattern), _stroke);
      } else {
        canvas.drawPath(g.path, _stroke);
      }

      if (!lod && (e.arrow ?? t.edgeArrow)) {
        _paintArrow(canvas, g, color, t.edgeArrowSize);
      }
      if (showLabels && e.label != null && e.label!.isNotEmpty) {
        labels.add((e, g, color));
      }
    }
    // Las etiquetas van por encima de todas las líneas.
    for (final (e, g, color) in labels) {
      _paintLabel(canvas, e, g, color);
    }
  }

  void _paintArrow(Canvas canvas, EdgeGeometry g, Color color, double size) {
    final tip = g.polyline.last;
    final dir = g.endDirection;
    final normal = Offset(-dir.dy, dir.dx);
    final base = tip - dir * size;
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(
          base.dx + normal.dx * size * 0.55, base.dy + normal.dy * size * 0.55)
      ..lineTo(
          base.dx - normal.dx * size * 0.55, base.dy - normal.dy * size * 0.55)
      ..close();
    _fill.color = color;
    canvas.drawPath(path, _fill);
  }

  void _paintLabel(Canvas canvas, EdgeData e, EdgeGeometry g, Color color) {
    final t = theme;
    final tp = _labelCache.putIfAbsent(
      e.label!,
      () => TextPainter(
        text: TextSpan(text: e.label, style: t.edgeLabelStyle),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: 220),
    );
    final pad = const EdgeInsets.symmetric(horizontal: 10, vertical: 4);
    final w = tp.width + pad.horizontal;
    final h = tp.height + pad.vertical;
    final rect = Rect.fromCenter(center: g.labelPosition, width: w, height: h);
    final rr = RRect.fromRectAndRadius(rect, Radius.circular(h / 2));
    _fill.color = t.edgeLabelBackground;
    canvas.drawRRect(rr, _fill);
    _labelBorder.color =
        controller.isEdgeSelected(e.id) ? color : t.edgeLabelBorderColor;
    canvas.drawRRect(rr, _labelBorder);
    tp.paint(canvas, rect.topLeft + Offset(pad.left, pad.top));
  }

  void _paintLodNodes(Canvas canvas, Rect region) {
    final t = theme;
    final ids = controller.queryNodes(region).toList()
      ..sort((a, b) => controller.zOf(a).compareTo(controller.zOf(b)));
    final radius = Radius.circular(math.max(t.nodeRadius, 6));
    _stroke.strokeWidth = math.max(2, t.nodeBorderWidth * 2);
    for (final id in ids) {
      if (controller.isHidden(id)) continue;
      final n = controller.node(id)!;
      final rect = controller.rectOf(id);
      final rr = RRect.fromRectAndRadius(rect, radius);
      final accent = t.accentFor(n.type, n.color);
      _fill.color = t.nodeTypes[n.type]?.backgroundColor ?? t.nodeColor;
      canvas.drawRRect(rr, _fill);
      // Banda superior con el color del tipo para distinguir nodos de lejos.
      _fill.color = accent;
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(
              rect.left, rect.top, rect.width, math.min(rect.height, 14)),
          topLeft: radius,
          topRight: radius,
        ),
        _fill,
      );
      _stroke.color = controller.isNodeSelected(id)
          ? t.nodeSelectedBorderColor
          : t.nodeBorderColor;
      canvas.drawRRect(rr, _stroke);
    }
  }
}
