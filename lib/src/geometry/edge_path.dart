import 'dart:math' as math;
import 'dart:ui';

import '../model/edge.dart';
import '../model/port.dart';

/// Geometría precalculada de una conexión.
class EdgeGeometry {
  EdgeGeometry({
    required this.path,
    required this.polyline,
    required this.labelPosition,
    required this.bounds,
    required this.endDirection,
  });

  final Path path;

  /// Aproximación poligonal usada para hit-testing.
  final List<Offset> polyline;
  final Offset labelPosition;
  final Rect bounds;

  /// Dirección unitaria con la que la línea llega al destino (para flechas).
  final Offset endDirection;

  /// Distancia mínima de [p] a la conexión.
  double distanceTo(Offset p) {
    var best = double.infinity;
    for (var i = 0; i < polyline.length - 1; i++) {
      final d = _distToSegment(p, polyline[i], polyline[i + 1]);
      if (d < best) best = d;
    }
    return best;
  }

  static double _distToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (len2 == 0) return (p - a).distance;
    var t = ((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2;
    t = t.clamp(0.0, 1.0);
    return (p - (a + ab * t)).distance;
  }
}

Offset _normal(PortSide s) {
  final (x, y) = s.normal;
  return Offset(x, y);
}

/// Construye la geometría de una conexión entre [a] (saliendo por [aSide]) y
/// [b] (entrando por [bSide]).
EdgeGeometry buildEdgeGeometry(
  EdgeCurve curve,
  Offset a,
  PortSide aSide,
  Offset b,
  PortSide bSide, {
  double cornerRadius = 10,
  double stepGap = 24,
}) {
  switch (curve) {
    case EdgeCurve.bezier:
      return _bezier(a, aSide, b, bSide);
    case EdgeCurve.straight:
      return _fromPolyline([a, b], 0);
    case EdgeCurve.smoothStep:
      return _fromPolyline(
          _orthogonal(a, aSide, b, bSide, stepGap), cornerRadius);
    case EdgeCurve.step:
      return _fromPolyline(_orthogonal(a, aSide, b, bSide, stepGap), 0);
  }
}

EdgeGeometry _bezier(Offset a, PortSide aSide, Offset b, PortSide bSide) {
  final dist = (b - a).distance;
  final k = math.max(40.0, math.min(dist * 0.5, 240.0));
  final c1 = a + _normal(aSide) * k;
  final c2 = b + _normal(bSide) * k;
  final path = Path()
    ..moveTo(a.dx, a.dy)
    ..cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, b.dx, b.dy);
  const samples = 16;
  final poly = <Offset>[];
  for (var i = 0; i <= samples; i++) {
    poly.add(_cubic(a, c1, c2, b, i / samples));
  }
  final end = b - _cubic(a, c1, c2, b, 0.95);
  return EdgeGeometry(
    path: path,
    polyline: poly,
    labelPosition: _cubic(a, c1, c2, b, 0.5),
    bounds: _boundsOf([a, c1, c2, b]),
    endDirection: _unit(end),
  );
}

Offset _cubic(Offset p0, Offset p1, Offset p2, Offset p3, double t) {
  final mt = 1 - t;
  final a = mt * mt * mt,
      b = 3 * mt * mt * t,
      c = 3 * mt * t * t,
      d = t * t * t;
  return Offset(
    a * p0.dx + b * p1.dx + c * p2.dx + d * p3.dx,
    a * p0.dy + b * p1.dy + c * p2.dy + d * p3.dy,
  );
}

List<Offset> _orthogonal(
    Offset a, PortSide aSide, Offset b, PortSide bSide, double gap) {
  final p1 = a + _normal(aSide) * gap;
  final p4 = b + _normal(bSide) * gap;
  final pts = <Offset>[a, p1];
  if (aSide.isHorizontal && bSide.isHorizontal) {
    final mx = (p1.dx + p4.dx) / 2;
    final goesForward =
        aSide == PortSide.right ? p4.dx >= p1.dx : p4.dx <= p1.dx;
    if (goesForward || aSide == bSide) {
      final x = aSide == bSide
          ? (aSide == PortSide.right
              ? math.max(p1.dx, p4.dx)
              : math.min(p1.dx, p4.dx))
          : mx;
      pts
        ..add(Offset(x, p1.dy))
        ..add(Offset(x, p4.dy));
    } else {
      final my = (p1.dy + p4.dy) / 2;
      pts
        ..add(Offset(p1.dx, my))
        ..add(Offset(p4.dx, my));
    }
  } else if (!aSide.isHorizontal && !bSide.isHorizontal) {
    final my = (p1.dy + p4.dy) / 2;
    final goesForward =
        aSide == PortSide.bottom ? p4.dy >= p1.dy : p4.dy <= p1.dy;
    if (goesForward || aSide == bSide) {
      final y = aSide == bSide
          ? (aSide == PortSide.bottom
              ? math.max(p1.dy, p4.dy)
              : math.min(p1.dy, p4.dy))
          : my;
      pts
        ..add(Offset(p1.dx, y))
        ..add(Offset(p4.dx, y));
    } else {
      final mx = (p1.dx + p4.dx) / 2;
      pts
        ..add(Offset(mx, p1.dy))
        ..add(Offset(mx, p4.dy));
    }
  } else if (aSide.isHorizontal) {
    pts.add(Offset(p4.dx, p1.dy));
  } else {
    pts.add(Offset(p1.dx, p4.dy));
  }
  pts
    ..add(p4)
    ..add(b);
  return _simplify(pts);
}

List<Offset> _simplify(List<Offset> pts) {
  final out = <Offset>[];
  for (final p in pts) {
    if (out.isNotEmpty && (out.last - p).distanceSquared < 0.01) continue;
    if (out.length >= 2) {
      final a = out[out.length - 2], b = out.last;
      final cross =
          (b.dx - a.dx) * (p.dy - b.dy) - (b.dy - a.dy) * (p.dx - b.dx);
      final dot = (b.dx - a.dx) * (p.dx - b.dx) + (b.dy - a.dy) * (p.dy - b.dy);
      if (cross.abs() < 0.01 && dot >= 0) {
        out[out.length - 1] = p;
        continue;
      }
    }
    out.add(p);
  }
  return out;
}

EdgeGeometry _fromPolyline(List<Offset> pts, double radius) {
  final path = Path()..moveTo(pts.first.dx, pts.first.dy);
  for (var i = 1; i < pts.length; i++) {
    final p = pts[i];
    if (radius > 0 && i < pts.length - 1) {
      final prev = pts[i - 1], next = pts[i + 1];
      final r = math.min(
          radius, math.min((p - prev).distance, (next - p).distance) / 2);
      final inDir = _unit(p - prev), outDir = _unit(next - p);
      final s = p - inDir * r, e = p + outDir * r;
      path
        ..lineTo(s.dx, s.dy)
        ..quadraticBezierTo(p.dx, p.dy, e.dx, e.dy);
    } else {
      path.lineTo(p.dx, p.dy);
    }
  }
  // Punto medio a lo largo de la polilínea para la etiqueta.
  var total = 0.0;
  for (var i = 1; i < pts.length; i++) {
    total += (pts[i] - pts[i - 1]).distance;
  }
  var half = total / 2;
  var label = pts.first;
  for (var i = 1; i < pts.length; i++) {
    final seg = (pts[i] - pts[i - 1]).distance;
    if (half <= seg && seg > 0) {
      label = Offset.lerp(pts[i - 1], pts[i], half / seg)!;
      break;
    }
    half -= seg;
  }
  final end =
      pts.length >= 2 ? pts.last - pts[pts.length - 2] : const Offset(1, 0);
  return EdgeGeometry(
    path: path,
    polyline: pts,
    labelPosition: label,
    bounds: _boundsOf(pts),
    endDirection: _unit(end),
  );
}

Offset _unit(Offset o) {
  final d = o.distance;
  return d == 0 ? const Offset(1, 0) : o / d;
}

Rect _boundsOf(List<Offset> pts) {
  var l = pts.first.dx, t = pts.first.dy, r = l, b = t;
  for (final p in pts) {
    if (p.dx < l) l = p.dx;
    if (p.dx > r) r = p.dx;
    if (p.dy < t) t = p.dy;
    if (p.dy > b) b = p.dy;
  }
  return Rect.fromLTRB(l, t, r, b);
}

/// Convierte [source] en un trazo discontinuo.
Path dashPath(Path source, List<double> pattern, {double phase = 0}) {
  final out = Path();
  if (pattern.isEmpty) return source;
  final total = pattern.fold<double>(0, (a, b) => a + b);
  if (total <= 0) return source;
  for (final metric in source.computeMetrics()) {
    var distance = -(phase % total);
    var i = 0;
    var draw = true;
    while (distance < metric.length) {
      final len = pattern[i % pattern.length];
      final start = math.max(0.0, distance);
      final end = math.min(metric.length, distance + len);
      if (draw && end > start) {
        out.addPath(metric.extractPath(start, end), Offset.zero);
      }
      distance += len;
      draw = !draw;
      i++;
    }
  }
  return out;
}
