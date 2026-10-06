import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter/foundation.dart';

/// Cámara del lienzo: desplazamiento + escala.
///
/// `pantalla = mundo * scale + offset`.
///
/// Cambiar el viewport sólo provoca un repintado del lienzo (no reconstruye
/// widgets), por lo que el pan/zoom es muy barato.
class NodeViewport extends ChangeNotifier {
  NodeViewport({
    Offset offset = Offset.zero,
    double scale = 1,
    this.minScale = 0.1,
    this.maxScale = 3,
  })  : _offset = offset,
        _scale = scale.clamp(minScale, maxScale);

  double minScale;
  double maxScale;

  Offset _offset;
  double _scale;
  Size _size = Size.zero;

  Offset get offset => _offset;
  double get scale => _scale;

  /// Tamaño en píxeles del widget que muestra el lienzo (lo asigna el editor).
  Size get size => _size;
  set size(Size value) {
    if (value == _size) return;
    _size = value;
    // No notificamos: el cambio de tamaño ya provoca relayout del editor.
  }

  Offset toWorld(Offset screen) => (screen - _offset) / _scale;
  Offset toScreen(Offset world) => world * _scale + _offset;

  /// Rectángulo del mundo actualmente visible.
  Rect get visibleWorldRect => Rect.fromPoints(
      toWorld(Offset.zero), toWorld(_size.bottomRight(Offset.zero)));

  void setView({Offset? offset, double? scale}) {
    final s = (scale ?? _scale).clamp(minScale, maxScale);
    final o = offset ?? _offset;
    if (s == _scale && o == _offset) return;
    _scale = s;
    _offset = o;
    notifyListeners();
  }

  void panBy(Offset screenDelta) {
    if (screenDelta == Offset.zero) return;
    _offset += screenDelta;
    notifyListeners();
  }

  /// Zoom manteniendo fijo el punto [focal] (en coordenadas de pantalla).
  void zoomAt(Offset focal, double factor) {
    final target = (_scale * factor).clamp(minScale, maxScale);
    if (target == _scale) return;
    final world = toWorld(focal);
    _scale = target;
    _offset = focal - world * _scale;
    notifyListeners();
  }

  /// Zoom alrededor del centro del viewport.
  void zoomBy(double factor) => zoomAt(_size.center(Offset.zero), factor);

  /// Centra el punto [world] del mundo en el viewport.
  void centerOn(Offset world, {double? scale}) {
    final s = (scale ?? _scale).clamp(minScale, maxScale);
    setView(scale: s, offset: _size.center(Offset.zero) - world * s);
  }

  /// Ajusta la cámara para que [worldRect] quepa entero.
  void fitRect(Rect worldRect, {double padding = 48, double? maxScale}) {
    if (_size.isEmpty || worldRect.isEmpty && worldRect.width == 0) {
      centerOn(worldRect.center);
      return;
    }
    final w = math.max(1.0, _size.width - padding * 2);
    final h = math.max(1.0, _size.height - padding * 2);
    var s = math.min(
        w / math.max(worldRect.width, 1), h / math.max(worldRect.height, 1));
    s = s.clamp(minScale, maxScale ?? this.maxScale);
    centerOn(worldRect.center, scale: s);
  }
}
