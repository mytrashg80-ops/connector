import 'dart:ui' show Offset, Rect;

/// Índice espacial de rejilla uniforme.
///
/// Permite consultar en O(celdas) qué nodos intersectan un rectángulo, de modo
/// que el culling del viewport y el hit-testing no dependan del número total
/// de nodos. Usa claves aritméticas (sin operadores de bits) para que sea
/// exacto también en web.
class SpatialIndex {
  SpatialIndex({this.cellSize = 256});

  final double cellSize;

  static const int _bias = 1 << 20;
  static const int _span = 1 << 21;

  final Map<String, Rect> _rects = {};
  final Map<String, _CellRange> _ranges = {};
  final Map<int, Set<String>> _cells = {};

  int get length => _rects.length;

  Rect? rectOf(String id) => _rects[id];

  int _cell(double v) {
    final c = (v / cellSize).floor();
    return c.clamp(-_bias + 1, _bias - 1);
  }

  _CellRange _rangeOf(Rect r) =>
      _CellRange(_cell(r.left), _cell(r.top), _cell(r.right), _cell(r.bottom));

  static int _key(int cx, int cy) => (cx + _bias) * _span + (cy + _bias);

  void insertOrUpdate(String id, Rect rect) {
    _rects[id] = rect;
    final range = _rangeOf(rect);
    final old = _ranges[id];
    if (old != null) {
      if (old == range) return;
      _removeFromCells(id, old);
    }
    _ranges[id] = range;
    for (var x = range.x0; x <= range.x1; x++) {
      for (var y = range.y0; y <= range.y1; y++) {
        (_cells[_key(x, y)] ??= <String>{}).add(id);
      }
    }
  }

  void remove(String id) {
    _rects.remove(id);
    final old = _ranges.remove(id);
    if (old != null) _removeFromCells(id, old);
  }

  void clear() {
    _rects.clear();
    _ranges.clear();
    _cells.clear();
  }

  void _removeFromCells(String id, _CellRange r) {
    for (var x = r.x0; x <= r.x1; x++) {
      for (var y = r.y0; y <= r.y1; y++) {
        final k = _key(x, y);
        final set = _cells[k];
        if (set == null) continue;
        set.remove(id);
        if (set.isEmpty) _cells.remove(k);
      }
    }
  }

  /// Ids cuyos rectángulos intersectan [area].
  Set<String> query(Rect area) {
    final out = <String>{};
    final r = _rangeOf(area);
    final cellCount = (r.x1 - r.x0 + 1) * (r.y1 - r.y0 + 1);
    // Si el área cubre más celdas que nodos existen, es más barato recorrer
    // todos los rectángulos.
    if (cellCount > _rects.length) {
      _rects.forEach((id, rect) {
        if (rect.overlaps(area)) out.add(id);
      });
      return out;
    }
    for (var x = r.x0; x <= r.x1; x++) {
      for (var y = r.y0; y <= r.y1; y++) {
        final set = _cells[_key(x, y)];
        if (set == null) continue;
        for (final id in set) {
          if (out.contains(id)) continue;
          if (_rects[id]!.overlaps(area)) out.add(id);
        }
      }
    }
    return out;
  }

  /// Ids cuyos rectángulos contienen [point] (con margen [slop]).
  Set<String> queryPoint(Offset point, [double slop = 0]) =>
      query(Rect.fromCircle(center: point, radius: slop == 0 ? 0.01 : slop));

  /// Rectángulo que envuelve todos los elementos. `null` si está vacío.
  Rect? bounds() {
    Rect? b;
    for (final r in _rects.values) {
      b = b == null ? r : b.expandToInclude(r);
    }
    return b;
  }
}

class _CellRange {
  const _CellRange(this.x0, this.y0, this.x1, this.y1);
  final int x0, y0, x1, y1;

  @override
  bool operator ==(Object other) =>
      other is _CellRange &&
      other.x0 == x0 &&
      other.y0 == y0 &&
      other.x1 == x1 &&
      other.y1 == y1;

  @override
  int get hashCode => Object.hash(x0, y0, x1, y1);
}
