import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'editor_config.dart';

/// Progreso de una animación medido con el reloj compartido de
/// [EditorEffects]. El inicio se fija en el primer frame (así no importa que
/// el ticker se reinicie entre animaciones).
class _Track {
  _Track(this.duration, this.curve);

  final Duration duration;
  final Curve curve;
  Duration? _start;
  double raw = 0;

  double get t => curve.transform(raw);
  bool get done => raw >= 1;

  void advance(Duration now) {
    final start = _start ??= now;
    final total = duration.inMicroseconds;
    raw = total <= 0
        ? 1
        : ((now - start).inMicroseconds / total).clamp(0.0, 1.0).toDouble();
  }
}

/// Transición de un nodo: desplazamiento (respecto a su posición real),
/// escala y opacidad.
class _NodeFx {
  _NodeFx(
    this.track, {
    this.from = Offset.zero,
    this.to = Offset.zero,
    this.scaleFrom = 1,
    this.scaleTo = 1,
    this.opacityFrom = 1,
    this.opacityTo = 1,
    this.ghost = false,
    this.origin,
    this.ghostSize,
    this.ghostAutoSize = false,
  });

  final _Track track;
  final Offset from, to;
  final double scaleFrom, scaleTo, opacityFrom, opacityTo;

  /// El nodo ya no se ve (borrado o plegado) y se pinta sólo para la salida.
  final bool ghost;

  /// Posición y tamaño de un nodo borrado (ya no está en el controlador).
  final Offset? origin;
  final Size? ghostSize;
  final bool ghostAutoSize;

  Offset get displacement => Offset.lerp(from, to, track.t)!;
  double get scale => ui.lerpDouble(scaleFrom, scaleTo, track.t)!;
  double get opacity =>
      ui.lerpDouble(opacityFrom, opacityTo, track.t)!.clamp(0.0, 1.0);
}

/// "Levantar" un nodo al arrastrarlo: 0 = en reposo, 1 = levantado.
class _Lift {
  _Lift(this.from, this.up, this.track);
  final double from;
  final bool up;
  final _Track track;

  double get value => ui.lerpDouble(from, up ? 1 : 0, track.t)!;
}

/// Línea que se desvanece (conexión o enlace eliminado).
class GhostLine {
  GhostLine._(this.path, this.color, this.width, this._track);
  final Path path;
  final Color color;
  final double width;
  final _Track _track;

  double get opacity => 1 - _track.t;
}

/// Estado de todas las animaciones visuales del editor. No toca el modelo:
/// el lienzo, la escena y cada nodo lo consultan al pintar.
///
/// Un único ticker las mueve todas y se detiene en cuanto no queda ninguna,
/// así que sin animaciones en curso el coste es cero.
class EditorEffects extends ChangeNotifier {
  EditorEffects(TickerProvider vsync) {
    _ticker = vsync.createTicker(_tick);
  }

  late final Ticker _ticker;
  NodeEditorAnimations config = const NodeEditorAnimations();

  /// Se llama cuando cambia la lista de nodos fantasma (hay que reconstruir).
  VoidCallback? onGhostsChanged;

  final Map<String, _NodeFx> _nodes = {};
  final Map<String, _Lift> _lifts = {};
  final Map<String, _Track> _edgesIn = {};
  final Map<String, _Track> _linksIn = {};
  final List<GhostLine> _lines = [];

  static const _maxGhostLines = 300;

  // ------------------------------------------------------------- consulta

  /// `true` si hay algo que pintar distinto del estado normal.
  bool get isIdle =>
      _nodes.isEmpty &&
      _lifts.isEmpty &&
      _edgesIn.isEmpty &&
      _linksIn.isEmpty &&
      _lines.isEmpty;

  /// `true` si el nodo tiene alguna transición.
  bool touches(String id) => _nodes.containsKey(id) || _lifts.containsKey(id);

  bool isGhost(String id) => _nodes[id]?.ghost ?? false;

  Iterable<String> get ghostIds =>
      _nodes.entries.where((e) => e.value.ghost).map((e) => e.key);

  /// Posición, tamaño (mínimo si `autoSize`) y `autoSize` de un nodo
  /// borrado que aún se está desvaneciendo.
  (Offset, Size, bool)? deletedGhost(String id) {
    final f = _nodes[id];
    final o = f?.origin;
    if (o == null) return null;
    return (o, f!.ghostSize ?? Size.zero, f.ghostAutoSize);
  }

  Offset displacement(String id) => _nodes[id]?.displacement ?? Offset.zero;
  double scaleOf(String id) => _nodes[id]?.scale ?? 1;
  double opacityOf(String id) => _nodes[id]?.opacity ?? 1;
  double liftOf(String id) => _lifts[id]?.value ?? 0;

  /// `true` si el nodo está desplazado o escalado (afecta a sus líneas).
  bool movesNode(String id) => _nodes.containsKey(id);

  /// Fracción dibujada (0‥1) de una conexión que está apareciendo.
  double? edgeProgress(String id) => _edgesIn[id]?.t;

  /// Fracción dibujada del enlace de jerarquía de [childId].
  double? linkProgress(String childId) => _linksIn[childId]?.t;

  List<GhostLine> get ghostLines => _lines;

  // ----------------------------------------------------------- disparadores

  _Track _track([Curve? curve, Duration? duration]) =>
      _Track(duration ?? config.duration, curve ?? config.curve);

  /// Aparece: crece desde [scaleFrom] y, si se indica, se desliza desde
  /// [from] (desplazamiento respecto a su posición final).
  void nodeEnter(String id,
      {Offset from = Offset.zero, double scaleFrom = 0.6}) {
    final prev = _nodes[id];
    final wasGhost = prev?.ghost ?? false;
    _nodes[id] = _NodeFx(
      _track(Curves.easeOutBack),
      from: prev?.displacement ?? from,
      scaleFrom: prev?.scale ?? scaleFrom,
      opacityFrom: prev?.opacity ?? 0,
    );
    _start();
    if (wasGhost) onGhostsChanged?.call();
  }

  /// Desaparece encogiéndose y, si se indica, deslizándose hacia [to].
  /// [origin], [size] y [autoSize] describen un nodo que ya no está en el
  /// controlador.
  void nodeExit(String id,
      {Offset to = Offset.zero,
      double scaleTo = 0.6,
      Offset? origin,
      Size? size,
      bool autoSize = false}) {
    final prev = _nodes[id];
    _lifts.remove(id);
    _nodes[id] = _NodeFx(
      _track(Curves.easeInCubic, config.duration * 0.8),
      from: prev?.displacement ?? Offset.zero,
      to: to,
      scaleFrom: prev?.scale ?? 1,
      scaleTo: scaleTo,
      opacityFrom: prev?.opacity ?? 1,
      opacityTo: 0,
      ghost: true,
      origin: origin,
      ghostSize: size,
      ghostAutoSize: autoSize,
    );
    _start();
    onGhostsChanged?.call();
  }

  /// El nodo saltó [jump] (posición anterior − nueva): se pinta en la
  /// posición anterior y se desliza hasta la nueva.
  void glide(String id, Offset jump) {
    final prev = _nodes[id];
    if (prev != null && prev.ghost) return;
    _nodes[id] = _NodeFx(
      _track(),
      from: (prev?.displacement ?? Offset.zero) + jump,
      scaleFrom: prev?.scale ?? 1,
      opacityFrom: prev?.opacity ?? 1,
    );
    _start();
  }

  /// Levanta los nodos que se empiezan a arrastrar.
  void lift(Iterable<String> ids) {
    for (final id in ids) {
      _lifts[id] = _Lift(liftOf(id), true,
          _track(Curves.easeOutCubic, const Duration(milliseconds: 140)));
    }
    _start();
  }

  /// Suelta todos los nodos levantados (se asientan con un pequeño rebote).
  void dropAll() {
    if (_lifts.isEmpty) return;
    for (final id in _lifts.keys.toList()) {
      final l = _lifts[id]!;
      if (!l.up) continue;
      _lifts[id] = _Lift(l.value, false,
          _track(Curves.easeOutBack, const Duration(milliseconds: 280)));
    }
    _start();
  }

  void edgeEnter(String id) {
    _edgesIn[id] = _track(Curves.easeInOutCubic);
    _start();
  }

  void linkEnter(String childId) {
    _linksIn[childId] = _track(Curves.easeInOutCubic);
    _start();
  }

  void addGhostLine(Path path, Color color, double width) {
    if (_lines.length >= _maxGhostLines) return;
    _lines.add(GhostLine._(path, color, width, _track(Curves.easeIn)));
    _start();
  }

  /// Cancela todo (p. ej. al cambiar de controlador).
  void clear() {
    final hadGhosts = _nodes.values.any((f) => f.ghost);
    _nodes.clear();
    _lifts.clear();
    _edgesIn.clear();
    _linksIn.clear();
    _lines.clear();
    if (_ticker.isActive) _ticker.stop();
    notifyListeners();
    if (hadGhosts) onGhostsChanged?.call();
  }

  // ---------------------------------------------------------------- reloj

  void _start() {
    if (!_ticker.isActive) _ticker.start();
  }

  void _tick(Duration now) {
    var ghostsChanged = false;
    var running = false;
    _nodes.removeWhere((id, f) {
      f.track.advance(now);
      if (!f.track.done) {
        running = true;
        return false;
      }
      if (f.ghost) ghostsChanged = true;
      return true;
    });
    _lifts.removeWhere((id, l) {
      l.track.advance(now);
      if (!l.track.done) {
        running = true;
        return false;
      }
      // Levantado y quieto: se mantiene hasta soltarlo.
      return !l.up;
    });
    bool advance(String _, _Track t) {
      t.advance(now);
      if (t.done) return true;
      running = true;
      return false;
    }

    _edgesIn.removeWhere(advance);
    _linksIn.removeWhere(advance);
    _lines.removeWhere((l) {
      l._track.advance(now);
      if (l._track.done) return true;
      running = true;
      return false;
    });
    notifyListeners();
    if (ghostsChanged) onGhostsChanged?.call();
    if (!running) _ticker.stop();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}

/// Aplica a un nodo su transición (escala, opacidad y sombra al levantarlo)
/// sin reconstruir su widget: sólo se repinta mientras dura.
class NodeEffect extends SingleChildRenderObjectWidget {
  const NodeEffect({
    super.key,
    required this.nodeId,
    required this.effects,
    required this.radius,
    required this.shadowColor,
    super.child,
  });

  final String nodeId;
  final EditorEffects effects;
  final double radius;
  final Color shadowColor;

  @override
  RenderNodeEffect createRenderObject(BuildContext context) =>
      RenderNodeEffect(nodeId, effects, radius, shadowColor);

  @override
  void updateRenderObject(BuildContext context, RenderNodeEffect renderObject) {
    renderObject
      ..nodeId = nodeId
      ..effects = effects
      ..radius = radius
      ..shadowColor = shadowColor;
  }
}

class RenderNodeEffect extends RenderProxyBox {
  RenderNodeEffect(this._nodeId, this._effects, this.radius, this.shadowColor);

  String _nodeId;
  EditorEffects _effects;
  double radius;
  Color shadowColor;
  bool _painted = false;

  set nodeId(String value) {
    if (value == _nodeId) return;
    _nodeId = value;
    markNeedsPaint();
  }

  EditorEffects get effects => _effects;
  String get nodeId => _nodeId;

  set effects(EditorEffects value) {
    if (identical(value, _effects)) return;
    if (attached) _effects.removeListener(_onEffects);
    _effects = value;
    if (attached) _effects.addListener(_onEffects);
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _effects.addListener(_onEffects);
  }

  @override
  void detach() {
    _effects.removeListener(_onEffects);
    super.detach();
  }

  void _onEffects() {
    // Un repintado más al terminar para volver al estado normal.
    if (_painted || _effects.touches(_nodeId)) markNeedsPaint();
  }

  // Cada nodo es su propia capa: animarlo no repinta a los demás.
  @override
  bool get isRepaintBoundary => true;

  final LayerHandle<OpacityLayer> _opacity = LayerHandle();
  final LayerHandle<TransformLayer> _transform = LayerHandle();
  final Paint _shadow = Paint();

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (_effects.isGhost(_nodeId)) return false;
    return super.hitTest(result, position: position);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    final fx = _effects;
    final lift = fx.liftOf(_nodeId);
    final scale = fx.scaleOf(_nodeId) * (1 + (fx.config.liftScale - 1) * lift);
    final alpha = (fx.opacityOf(_nodeId) * 255).round();
    _painted = fx.touches(_nodeId);
    if (!_painted || (scale == 1 && alpha >= 255 && lift <= 0)) {
      _opacity.layer = null;
      _transform.layer = null;
      context.paintChild(child, offset);
      return;
    }
    void paintScaled(PaintingContext ctx, Offset o) {
      if (lift > 0) {
        final l = math.min(lift, 1.0);
        final rect = (o & size).shift(Offset(0, 4 + 6 * l));
        _shadow
          ..color = shadowColor.withValues(alpha: shadowColor.a * l)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6 + 8 * l);
        ctx.canvas.drawRRect(
            RRect.fromRectAndRadius(rect, Radius.circular(radius)), _shadow);
      }
      ctx.paintChild(child, o);
    }

    void paintTransformed(PaintingContext ctx, Offset o) {
      if (scale == 1) {
        _transform.layer = null;
        paintScaled(ctx, o);
        return;
      }
      final c = size.center(Offset.zero);
      final m = Matrix4.identity()
        ..translateByDouble(c.dx, c.dy, 0, 1)
        ..scaleByDouble(scale, scale, 1, 1)
        ..translateByDouble(-c.dx, -c.dy, 0, 1);
      _transform.layer = ctx.pushTransform(needsCompositing, o, m, paintScaled,
          oldLayer: _transform.layer);
    }

    if (alpha < 255) {
      _opacity.layer = context.pushOpacity(offset, alpha, paintTransformed,
          oldLayer: _opacity.layer);
    } else {
      _opacity.layer = null;
      paintTransformed(context, offset);
    }
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final scale = _effects.scaleOf(_nodeId) *
        (1 + (_effects.config.liftScale - 1) * _effects.liftOf(_nodeId));
    if (scale != 1) {
      final c = size.center(Offset.zero);
      transform
        ..translateByDouble(c.dx, c.dy, 0, 1)
        ..scaleByDouble(scale, scale, 1, 1)
        ..translateByDouble(-c.dx, -c.dy, 0, 1);
    }
  }

  @override
  void dispose() {
    _opacity.layer = null;
    _transform.layer = null;
    super.dispose();
  }
}
