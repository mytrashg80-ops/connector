import 'dart:ui';

import 'package:flutter/foundation.dart';

/// Línea guía de alineación, en coordenadas del mundo.
@immutable
class AlignmentGuide {
  const AlignmentGuide({
    required this.vertical,
    required this.position,
    required this.start,
    required this.end,
  });

  /// `true` = línea vertical en x = [position]; `false` = horizontal en
  /// y = [position].
  final bool vertical;
  final double position;

  /// Extensión de la línea a lo largo del otro eje.
  final double start;
  final double end;

  @override
  bool operator ==(Object other) =>
      other is AlignmentGuide &&
      other.vertical == vertical &&
      other.position == position &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(vertical, position, start, end);

  @override
  String toString() =>
      'AlignmentGuide(${vertical ? 'x' : 'y'}=$position, $start..$end)';
}

/// Qué líneas de un rectángulo participan en la alineación.
@immutable
class AlignLines {
  const AlignLines({
    this.left = true,
    this.centerX = true,
    this.right = true,
    this.top = true,
    this.centerY = true,
    this.bottom = true,
  });

  /// Todas (mover un nodo).
  static const all = AlignLines();

  final bool left, centerX, right, top, centerY, bottom;
}

/// Resultado de [AlignmentSnapper.snap].
@immutable
class AlignmentResult {
  const AlignmentResult(this.delta, this.guides);

  /// Corrección a aplicar para quedar alineado (cero en el eje que no se
  /// ajustó).
  final Offset delta;
  final List<AlignmentGuide> guides;

  bool get snappedX => delta.dx != 0;
  bool get snappedY => delta.dy != 0;
}

/// Calcula el "imán" de alineación entre un rectángulo que se mueve y el
/// resto: bordes izquierdo/derecho/superior/inferior y centros.
///
/// Se crea una vez al empezar el gesto con los rectángulos cercanos y cada
/// llamada a [snap] es lineal en su número (6 × 6 comparaciones por nodo como
/// mucho), así que es barato incluso con cientos de nodos en pantalla.
class AlignmentSnapper {
  AlignmentSnapper(Iterable<Rect> others) : _rects = others.toList();

  final List<Rect> _rects;

  bool get isEmpty => _rects.isEmpty;

  static const double _eps = 0.5;

  /// Busca la alineación más cercana a [moving] (a menos de [tolerance]) y
  /// devuelve la corrección y las guías que quedan alineadas tras aplicarla.
  AlignmentResult snap(Rect moving, double tolerance,
      {AlignLines lines = AlignLines.all}) {
    final mx = _xs(moving, lines);
    final my = _ys(moving, lines);
    var dx = 0.0, dy = 0.0;
    var bestX = tolerance, bestY = tolerance;
    var hasX = false, hasY = false;
    for (final r in _rects) {
      for (final t in [r.left, r.center.dx, r.right]) {
        for (final m in mx) {
          final d = t - m;
          if (d.abs() < bestX || (!hasX && d.abs() <= bestX)) {
            bestX = d.abs();
            dx = d;
            hasX = true;
          }
        }
      }
      for (final t in [r.top, r.center.dy, r.bottom]) {
        for (final m in my) {
          final d = t - m;
          if (d.abs() < bestY || (!hasY && d.abs() <= bestY)) {
            bestY = d.abs();
            dy = d;
            hasY = true;
          }
        }
      }
    }
    final snapped = moving.shift(Offset(dx, dy));
    return AlignmentResult(Offset(dx, dy), guidesFor(snapped, lines: lines));
  }

  /// Guías de las líneas de [rect] que coinciden con las de otros nodos.
  List<AlignmentGuide> guidesFor(Rect rect,
      {AlignLines lines = AlignLines.all}) {
    final out = <AlignmentGuide>[];
    final seenX = <double>[], seenY = <double>[];
    for (final m in _xs(rect, lines)) {
      if (seenX.any((v) => (v - m).abs() < _eps)) continue;
      var start = rect.top, end = rect.bottom, found = false;
      for (final r in _rects) {
        if ((r.left - m).abs() < _eps ||
            (r.center.dx - m).abs() < _eps ||
            (r.right - m).abs() < _eps) {
          found = true;
          if (r.top < start) start = r.top;
          if (r.bottom > end) end = r.bottom;
        }
      }
      if (found) {
        seenX.add(m);
        out.add(AlignmentGuide(
            vertical: true, position: m, start: start, end: end));
      }
    }
    for (final m in _ys(rect, lines)) {
      if (seenY.any((v) => (v - m).abs() < _eps)) continue;
      var start = rect.left, end = rect.right, found = false;
      for (final r in _rects) {
        if ((r.top - m).abs() < _eps ||
            (r.center.dy - m).abs() < _eps ||
            (r.bottom - m).abs() < _eps) {
          found = true;
          if (r.left < start) start = r.left;
          if (r.right > end) end = r.right;
        }
      }
      if (found) {
        seenY.add(m);
        out.add(AlignmentGuide(
            vertical: false, position: m, start: start, end: end));
      }
    }
    return out;
  }

  static List<double> _xs(Rect r, AlignLines l) => [
        if (l.left) r.left,
        if (l.centerX) r.center.dx,
        if (l.right) r.right,
      ];

  static List<double> _ys(Rect r, AlignLines l) => [
        if (l.top) r.top,
        if (l.centerY) r.center.dy,
        if (l.bottom) r.bottom,
      ];
}
