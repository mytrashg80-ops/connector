import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../controller/viewport.dart';
import '../geometry/edge_path.dart';
import '../model/edge.dart';
import '../model/port.dart';
import '../theme/node_editor_theme.dart';
import 'alignment_guides.dart';

/// Rejilla de fondo en coordenadas de pantalla. Adapta la densidad al zoom
/// para no dibujar nunca más puntos/líneas de los necesarios.
class GridPainter extends CustomPainter {
  GridPainter({required this.viewport, required this.theme})
      : super(repaint: viewport);

  final NodeViewport viewport;
  final NodeEditorTheme theme;

  final Paint _paint = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    if (theme.gridStyle == GridStyle.none) return;
    var spacing = theme.gridSpacing * viewport.scale;
    var majorEvery = theme.gridMajorEvery;
    // Agrupa celdas hasta que estén a una distancia razonable en pantalla.
    var step = 1;
    while (spacing < 12) {
      spacing *= 2;
      step *= 2;
    }
    if (majorEvery > 0 && step > 1) {
      majorEvery = math.max(1, majorEvery ~/ step);
    }
    final o = viewport.offset;
    final startX = o.dx % spacing;
    final startY = o.dy % spacing;
    // Índice de celda global (para saber cuál es "mayor").
    final ix0 = ((-o.dx) / spacing).ceil();
    final iy0 = ((-o.dy) / spacing).ceil();

    if (theme.gridStyle == GridStyle.dots) {
      final minor = <Offset>[];
      final major = <Offset>[];
      var ix = ix0;
      for (var x = startX; x <= size.width; x += spacing, ix++) {
        var iy = iy0;
        for (var y = startY; y <= size.height; y += spacing, iy++) {
          if (majorEvery > 0 && ix % majorEvery == 0 && iy % majorEvery == 0) {
            major.add(Offset(x, y));
          } else {
            minor.add(Offset(x, y));
          }
        }
      }
      final r = (viewport.scale.clamp(0.6, 1.4)) * 1.4;
      _paint
        ..strokeCap = StrokeCap.round
        ..strokeWidth = r
        ..color = theme.gridColor;
      canvas.drawPoints(ui.PointMode.points, minor, _paint);
      _paint
        ..strokeWidth = r * 1.5
        ..color = theme.gridMajorColor;
      canvas.drawPoints(ui.PointMode.points, major, _paint);
    } else {
      final minor = <Offset>[];
      final major = <Offset>[];
      var ix = ix0;
      for (var x = startX; x <= size.width; x += spacing, ix++) {
        final list = majorEvery > 0 && ix % majorEvery == 0 ? major : minor;
        list
          ..add(Offset(x, 0))
          ..add(Offset(x, size.height));
      }
      var iy = iy0;
      for (var y = startY; y <= size.height; y += spacing, iy++) {
        final list = majorEvery > 0 && iy % majorEvery == 0 ? major : minor;
        list
          ..add(Offset(0, y))
          ..add(Offset(size.width, y));
      }
      _paint
        ..strokeWidth = 1
        ..color = theme.gridColor;
      canvas.drawPoints(ui.PointMode.lines, minor, _paint);
      _paint.color = theme.gridMajorColor;
      canvas.drawPoints(ui.PointMode.lines, major, _paint);
    }
  }

  @override
  bool shouldRepaint(GridPainter old) =>
      !identical(old.theme, theme) || !identical(old.viewport, viewport);
}

/// Estado efímero de la interacción (conexión en curso, selección
/// rectangular, destino de re-parentado). Vive en coordenadas del mundo.
class InteractionState extends ChangeNotifier {
  Offset? connectFrom;
  PortSide connectFromSide = PortSide.right;
  bool connectReversed = false;
  Offset? connectTo;
  PortSide? connectToSide;
  bool? connectValid;
  EdgeCurve connectCurve = EdgeCurve.bezier;

  Rect? marquee;
  Rect? dropTarget;

  /// Conexión bajo el ratón.
  String? hoverEdgeId;

  /// Enlace de jerarquía (id del hijo) bajo el ratón.
  String? hoverLinkId;

  /// Conexión cuyo extremo se está arrastrando.
  String? reconnectingEdgeId;

  /// Enlace de jerarquía (id del hijo) cuyo extremo se está arrastrando.
  String? reconnectingLinkId;

  /// Nodo bajo el ratón que muestra sus tiradores de conector, y el
  /// tirador concreto bajo el ratón.
  String? handleNodeId;
  PortSide? hoverHandle;

  /// Oculta los tiradores durante un gesto.
  bool handlesHidden = false;

  /// Guías de alineación visibles.
  List<AlignmentGuide> guides = const [];

  /// Nodo que se está redimensionando.
  String? resizingNodeId;

  /// Vista previa de un elemento que se va a soltar (p. ej. desde una paleta).
  Rect? dropPreview;

  void update() => notifyListeners();

  void clear() {
    connectFrom = null;
    connectTo = null;
    connectToSide = null;
    connectValid = null;
    marquee = null;
    dropTarget = null;
    reconnectingEdgeId = null;
    reconnectingLinkId = null;
    resizingNodeId = null;
    guides = const [];
    handlesHidden = false;
    notifyListeners();
  }
}

/// Pinta la interacción en curso por encima de los nodos.
class InteractionPainter extends CustomPainter {
  InteractionPainter({
    required this.state,
    required this.viewport,
    required this.theme,
  }) : super(repaint: Listenable.merge([state, viewport]));

  final InteractionState state;
  final NodeViewport viewport;
  final NodeEditorTheme theme;

  @override
  void paint(Canvas canvas, Size size) {
    final s = viewport.scale;
    canvas.save();
    canvas.translate(viewport.offset.dx, viewport.offset.dy);
    canvas.scale(s);

    final drop = state.dropTarget;
    if (drop != null) {
      final rr = RRect.fromRectAndRadius(
          drop.inflate(6 / s), Radius.circular(theme.nodeRadius + 6 / s));
      canvas.drawRRect(
          rr, Paint()..color = theme.dropTargetColor.withValues(alpha: 0.12));
      canvas.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 / s
          ..color = theme.dropTargetColor,
      );
    }

    final from = state.connectFrom, to = state.connectTo;
    if (from != null && to != null) {
      final color = state.connectValid == false
          ? theme.invalidConnectionColor
          : theme.connectionPreviewColor;
      final toSide = state.connectToSide ?? _guessSide(from, to);
      final a = state.connectReversed ? to : from;
      final b = state.connectReversed ? from : to;
      final aSide = state.connectReversed ? toSide : state.connectFromSide;
      final bSide = state.connectReversed ? state.connectFromSide : toSide;
      final g = buildEdgeGeometry(state.connectCurve, a, aSide, b, bSide,
          cornerRadius: theme.edgeCornerRadius);
      canvas.drawPath(
        dashPath(g.path, const [8, 6]),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = theme.edgeWidth
          ..strokeCap = StrokeCap.round
          ..color = color,
      );
      if (state.connectToSide != null) {
        canvas.drawCircle(
          to,
          theme.portRadius + 4,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = color,
        );
      }
      canvas.drawCircle(from, theme.portRadius, Paint()..color = color);
    }

    final m = state.marquee;
    if (m != null) {
      canvas.drawRect(m, Paint()..color = theme.selectionFillColor);
      canvas.drawRect(
        m,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1 / s
          ..color = theme.selectionBorderColor,
      );
    }
    canvas.restore();
  }

  PortSide _guessSide(Offset from, Offset to) {
    final d = to - from;
    if (d.dx.abs() >= d.dy.abs()) {
      return d.dx >= 0 ? PortSide.left : PortSide.right;
    }
    return d.dy >= 0 ? PortSide.top : PortSide.bottom;
  }

  @override
  bool shouldRepaint(InteractionPainter old) =>
      !identical(old.theme, theme) ||
      !identical(old.state, state) ||
      !identical(old.viewport, viewport);
}
