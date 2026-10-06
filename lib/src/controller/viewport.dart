import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

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
    stopAnimation();
    _apply(offset ?? _offset, scale ?? _scale);
  }

  void _apply(Offset offset, double scale) {
    final s = scale.clamp(minScale, maxScale);
    if (s == _scale && offset == _offset) return;
    _scale = s;
    _offset = offset;
    notifyListeners();
  }

  // ------------------------------------------------------------- animación

  Ticker? _ticker;
  Object? _tickerOwner;
  Duration _animDuration = const Duration(milliseconds: 380);
  Curve _animCurve = Curves.easeInOutCubic;
  Offset _fromCenter = Offset.zero, _toCenter = Offset.zero;
  double _fromScale = 1, _toScale = 1;

  /// Activa las transiciones de cámara con el [vsync] dado (lo hace el
  /// editor según `NodeEditorAnimations.camera`). Con `null` se desactivan
  /// y `animate: true` pasa a ser un salto directo.
  void configureAnimation(
    TickerProvider? vsync, {
    Object? owner,
    Duration duration = const Duration(milliseconds: 380),
    Curve curve = Curves.easeInOutCubic,
  }) {
    _animDuration = duration;
    _animCurve = curve;
    if (vsync == null) {
      // Sólo quien la configuró puede quitarla (varios editores pueden
      // compartir controlador).
      if (owner != null && !identical(owner, _tickerOwner)) return;
      _ticker?.dispose();
      _ticker = null;
      _tickerOwner = null;
      return;
    }
    if (identical(owner, _tickerOwner) && _ticker != null) return;
    _ticker?.dispose();
    _ticker = vsync.createTicker(_onTick);
    _tickerOwner = owner;
  }

  /// `true` mientras hay una transición de cámara en curso.
  bool get isAnimating => _ticker?.isActive ?? false;

  /// Detiene la transición de cámara en curso (los gestos del usuario lo
  /// hacen solos).
  void stopAnimation() {
    if (_ticker?.isActive ?? false) _ticker!.stop();
  }

  /// Lleva la cámara a [offset]/[scale] con una transición si están
  /// activadas (si no, salta directamente).
  void animateTo({Offset? offset, double? scale}) {
    final s = (scale ?? _scale).clamp(minScale, maxScale);
    final o = offset ?? _offset;
    final ticker = _ticker;
    if (ticker == null || _size.isEmpty || _animDuration == Duration.zero) {
      setView(offset: o, scale: s);
      return;
    }
    stopAnimation();
    final c = _size.center(Offset.zero);
    _fromCenter = toWorld(c);
    _fromScale = _scale;
    _toCenter = (c - o) / s;
    _toScale = s;
    if (_fromCenter == _toCenter && _fromScale == _toScale) return;
    ticker.start();
  }

  void _onTick(Duration elapsed) {
    final total = _animDuration.inMicroseconds;
    final raw = total <= 0 ? 1.0 : elapsed.inMicroseconds / total;
    final t = _animCurve.transform(raw.clamp(0.0, 1.0));
    // La escala se interpola en logaritmos para que el zoom se perciba
    // uniforme; el centro, linealmente.
    final s = math.exp(_lerp(math.log(_fromScale), math.log(_toScale), t));
    final center = Offset.lerp(_fromCenter, _toCenter, t)!;
    _apply(_size.center(Offset.zero) - center * s, s);
    if (raw >= 1) _ticker?.stop();
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  @override
  void dispose() {
    _ticker?.dispose();
    _ticker = null;
    super.dispose();
  }

  void panBy(Offset screenDelta) {
    if (screenDelta == Offset.zero) return;
    stopAnimation();
    _offset += screenDelta;
    notifyListeners();
  }

  /// Zoom manteniendo fijo el punto [focal] (en coordenadas de pantalla).
  void zoomAt(Offset focal, double factor) {
    stopAnimation();
    final target = (_scale * factor).clamp(minScale, maxScale);
    if (target == _scale) return;
    final world = toWorld(focal);
    _scale = target;
    _offset = focal - world * _scale;
    notifyListeners();
  }

  /// Zoom alrededor del centro del viewport.
  ///
  /// Con [animate] usa una transición (si el editor las tiene activadas).
  void zoomBy(double factor, {bool animate = false}) {
    if (!animate) return zoomAt(_size.center(Offset.zero), factor);
    // Encadena con la transición en curso para que varios clics seguidos
    // acumulen el zoom.
    final base = isAnimating ? _toScale : _scale;
    final center = isAnimating ? _toCenter : toWorld(_size.center(Offset.zero));
    final s = (base * factor).clamp(minScale, maxScale);
    animateTo(scale: s, offset: _size.center(Offset.zero) - center * s);
  }

  /// Centra el punto [world] del mundo en el viewport.
  void centerOn(Offset world, {double? scale, bool animate = false}) {
    final s = (scale ?? _scale).clamp(minScale, maxScale);
    final o = _size.center(Offset.zero) - world * s;
    animate ? animateTo(scale: s, offset: o) : setView(scale: s, offset: o);
  }

  /// Ajusta la cámara para que [worldRect] quepa entero.
  void fitRect(Rect worldRect,
      {double padding = 48, double? maxScale, bool animate = false}) {
    if (_size.isEmpty || worldRect.isEmpty && worldRect.width == 0) {
      centerOn(worldRect.center, animate: animate);
      return;
    }
    final w = math.max(1.0, _size.width - padding * 2);
    final h = math.max(1.0, _size.height - padding * 2);
    var s = math.min(
        w / math.max(worldRect.width, 1), h / math.max(worldRect.height, 1));
    s = s.clamp(minScale, maxScale ?? this.maxScale);
    centerOn(worldRect.center, scale: s, animate: animate);
  }
}
