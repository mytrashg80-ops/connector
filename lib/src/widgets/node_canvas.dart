import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../controller/node_editor_controller.dart';
import 'effects.dart';
import 'scene_renderer.dart';

/// Datos de layout de cada hijo del lienzo.
class NodeCanvasParentData extends ContainerBoxParentData<RenderBox> {
  /// `null` para la capa de escena (conexiones).
  String? nodeId;
}

/// Asocia un widget hijo del lienzo a un nodo.
class NodeSlot extends ParentDataWidget<NodeCanvasParentData> {
  const NodeSlot({super.key, required this.nodeId, required super.child});

  final String nodeId;

  @override
  void applyParentData(RenderObject renderObject) {
    final pd = renderObject.parentData! as NodeCanvasParentData;
    if (pd.nodeId != nodeId) {
      pd.nodeId = nodeId;
      final parent = renderObject.parent;
      if (parent is RenderObject) parent.markNeedsLayout();
    }
  }

  @override
  Type get debugTypicalAncestorWidgetClass => NodeCanvas;
}

/// Lienzo infinito: coloca cada nodo en su posición del mundo y aplica la
/// cámara como una única transformación de capa.
///
/// * Pan/zoom → sólo se recompone (los nodos son `RepaintBoundary`).
/// * Mover nodos → relayout barato (los hijos no se vuelven a medir).
/// * Las conexiones viven en una capa propia cacheada que sólo se repinta
///   cuando cambia el grafo o la cámara sale de la región precalculada.
class NodeCanvas<T> extends MultiChildRenderObjectWidget {
  const NodeCanvas({
    super.key,
    required this.controller,
    required this.renderer,
    required this.dashPhase,
    required this.lodScale,
    required this.cullMargin,
    required this.sceneVersion,
    this.effects,
    super.children,
  });

  final NodeEditorController<T> controller;
  final SceneRenderer<T> renderer;
  final ValueListenable<double> dashPhase;
  final double lodScale;
  final double cullMargin;

  /// Cambia cuando algo externo (tema, configuración) obliga a repintar la
  /// escena.
  final Object sceneVersion;

  /// Animaciones en curso (desplazan nodos y repintan la escena).
  final EditorEffects? effects;

  @override
  RenderNodeCanvas<T> createRenderObject(BuildContext context) =>
      RenderNodeCanvas<T>(
        controller: controller,
        renderer: renderer,
        dashPhase: dashPhase,
        lodScale: lodScale,
        cullMargin: cullMargin,
        effects: effects,
      );

  @override
  void updateRenderObject(
      BuildContext context, RenderNodeCanvas<T> renderObject) {
    final ro = renderObject;
    final sceneChanged = ro._sceneVersion != sceneVersion;
    ro
      ..controller = controller
      ..renderer = renderer
      ..dashPhase = dashPhase
      ..lodScale = lodScale
      ..cullMargin = cullMargin
      ..effects = effects
      .._sceneVersion = sceneVersion;
    if (sceneChanged) ro.invalidateScene();
  }
}

/// Capa de escena (conexiones, jerarquía y nodos simplificados).
class SceneLayer extends LeafRenderObjectWidget {
  const SceneLayer({super.key});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderScene();
}

class _RenderScene extends RenderBox {
  Rect region = Rect.zero;
  double paintedScale = 1;
  bool lod = false;
  SceneRenderer<Object?>? renderer;
  double dashPhase = 0;

  @override
  bool get isRepaintBoundary => true;

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  bool hitTestSelf(Offset position) => false;

  @override
  void paint(PaintingContext context, Offset offset) {
    final r = renderer;
    if (r == null) return;
    final canvas = context.canvas;
    if (offset != Offset.zero) {
      canvas.save();
      canvas.translate(offset.dx, offset.dy);
    }
    r.paint(canvas, region,
        scale: paintedScale, lod: lod, dashPhase: dashPhase);
    if (offset != Offset.zero) canvas.restore();
  }
}

class RenderNodeCanvas<T> extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, NodeCanvasParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, NodeCanvasParentData> {
  RenderNodeCanvas({
    required NodeEditorController<T> controller,
    required SceneRenderer<T> renderer,
    required ValueListenable<double> dashPhase,
    required this.lodScale,
    required this.cullMargin,
    EditorEffects? effects,
  })  : _controller = controller,
        _renderer = renderer,
        _dashPhase = dashPhase,
        _effects = effects;

  EditorEffects? _effects;
  set effects(EditorEffects? value) {
    if (identical(value, _effects)) return;
    if (attached) _effects?.removeListener(_onEffects);
    _effects = value;
    if (attached) _effects?.addListener(_onEffects);
    _onEffects();
  }

  void _onEffects() {
    markNeedsLayout();
    _scene?.markNeedsPaint();
  }

  NodeEditorController<T> _controller;
  SceneRenderer<T> _renderer;
  ValueListenable<double> _dashPhase;
  double lodScale;
  double cullMargin;
  Object? _sceneVersion;

  NodeEditorController<T> get controller => _controller;
  set controller(NodeEditorController<T> value) {
    if (identical(value, _controller)) return;
    if (attached) _unlisten();
    _controller = value;
    if (attached) _listen();
    markNeedsLayout();
  }

  set renderer(SceneRenderer<T> value) {
    if (identical(value, _renderer)) return;
    _renderer = value;
    invalidateScene();
  }

  set dashPhase(ValueListenable<double> value) {
    if (identical(value, _dashPhase)) return;
    if (attached) _dashPhase.removeListener(_onDash);
    _dashPhase = value;
    if (attached) _dashPhase.addListener(_onDash);
  }

  _RenderScene? get _scene {
    final first = firstChild;
    return first is _RenderScene ? first : null;
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! NodeCanvasParentData) {
      child.parentData = NodeCanvasParentData();
    }
  }

  void _listen() {
    _controller.geometry.addListener(_onGeometry);
    _controller.edgesSignal.addListener(invalidateScene);
    _controller.selection.addListener(invalidateScene);
    _controller.structure.addListener(invalidateScene);
    _controller.viewport.addListener(_onViewport);
    _dashPhase.addListener(_onDash);
    _effects?.addListener(_onEffects);
  }

  void _unlisten() {
    _controller.geometry.removeListener(_onGeometry);
    _controller.edgesSignal.removeListener(invalidateScene);
    _controller.selection.removeListener(invalidateScene);
    _controller.structure.removeListener(invalidateScene);
    _controller.viewport.removeListener(_onViewport);
    _dashPhase.removeListener(_onDash);
    _effects?.removeListener(_onEffects);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _listen();
  }

  @override
  void detach() {
    _unlisten();
    super.detach();
  }

  void _onGeometry() {
    markNeedsLayout();
    invalidateScene();
  }

  void _onDash() {
    final s = _scene;
    if (s == null || s.lod) return;
    s.dashPhase = _dashPhase.value;
    s.markNeedsPaint();
  }

  /// Fuerza el repintado de la capa de conexiones.
  void invalidateScene() {
    final s = _scene;
    if (s == null) return;
    _updateSceneRegion(force: true);
  }

  void _onViewport() {
    _updateSceneRegion();
    markNeedsPaint();
  }

  /// Recalcula la región cacheada de la escena si la cámara salió de ella.
  void _updateSceneRegion({bool force = false}) {
    final s = _scene;
    if (s == null) return;
    final vp = _controller.viewport;
    if (vp.size.isEmpty) return;
    final visible = vp.visibleWorldRect;
    final lod = vp.scale < lodScale;
    final scaleRatio = vp.scale / s.paintedScale;
    final needs = force ||
        s.renderer == null ||
        s.lod != lod ||
        !s.region.contains(visible.topLeft) ||
        !s.region.contains(visible.bottomRight) ||
        scaleRatio > 1.6 ||
        scaleRatio < 1 / 1.6;
    if (!needs) return;
    final margin = math.max(visible.width, visible.height) * cullMargin;
    s
      ..renderer = _renderer
      ..region = visible.inflate(margin)
      ..paintedScale = vp.scale
      ..lod = lod
      ..dashPhase = _dashPhase.value
      ..markNeedsPaint();
  }

  @override
  void performLayout() {
    size = constraints.biggest;
    final vp = _controller.viewport;
    final sizeChanged = vp.size != size;
    vp.size = size;
    var child = firstChild;
    var measuredChanged = false;
    final fx = _effects;
    while (child != null) {
      final pd = child.parentData! as NodeCanvasParentData;
      final id = pd.nodeId;
      if (id == null) {
        child.layout(BoxConstraints.tight(size));
        pd.offset = Offset.zero;
      } else {
        final node = _controller.node(id);
        final shift = fx?.displacement(id) ?? Offset.zero;
        final ghost = node == null ? fx?.deletedGhost(id) : null;
        if (ghost != null) {
          // Nodo borrado que aún se desvanece: mismas restricciones que
          // tenía.
          final (at, size, auto) = ghost;
          child.layout(auto
              ? BoxConstraints(
                  minWidth: size.width,
                  minHeight: size.height,
                  maxWidth: math.max(size.width, 480))
              : BoxConstraints.tight(size));
          pd.offset = at + shift;
        } else if (node == null) {
          child.layout(BoxConstraints.tight(Size.zero));
        } else if (node.autoSize) {
          child.layout(
            BoxConstraints(
              minWidth: node.size.width,
              minHeight: node.size.height,
              maxWidth: math.max(node.size.width, 480),
            ),
            parentUsesSize: true,
          );
          if (_controller.reportMeasuredSize(id, child.size)) {
            measuredChanged = true;
          }
          pd.offset = node.position + shift;
        } else {
          child.layout(BoxConstraints.tight(node.size));
          pd.offset = node.position + shift;
        }
      }
      child = pd.nextSibling;
    }
    if (sizeChanged || measuredChanged) _updateSceneRegion(force: true);
  }

  Matrix4 get _viewMatrix {
    final vp = _controller.viewport;
    final s = vp.scale;
    return Matrix4(
      s, 0, 0, 0, //
      0, s, 0, 0, //
      0, 0, 1, 0, //
      vp.offset.dx, vp.offset.dy, 0, 1,
    );
  }

  @override
  bool get alwaysNeedsCompositing => true;

  final LayerHandle<ClipRectLayer> _clipLayer = LayerHandle();
  final LayerHandle<TransformLayer> _transformLayer = LayerHandle();

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_scene != null && _scene!.renderer == null) {
      // Primer pintado: aún no hay región.
      _scene!
        ..renderer = _renderer
        ..region = _controller.viewport.visibleWorldRect.inflate(
            math.max(size.width, size.height) *
                cullMargin /
                _controller.viewport.scale)
        ..paintedScale = _controller.viewport.scale
        ..lod = _controller.viewport.scale < lodScale;
    }
    _clipLayer.layer = context.pushClipRect(
      needsCompositing,
      offset,
      Offset.zero & size,
      (ctx, o) {
        _transformLayer.layer = ctx.pushTransform(
          needsCompositing,
          o,
          _viewMatrix,
          _paintChildren,
          oldLayer: _transformLayer.layer,
        );
      },
      oldLayer: _clipLayer.layer,
    );
  }

  void _paintChildren(PaintingContext context, Offset offset) {
    var child = firstChild;
    while (child != null) {
      final pd = child.parentData! as NodeCanvasParentData;
      context.paintChild(child, pd.offset + offset);
      child = pd.nextSibling;
    }
  }

  @override
  void dispose() {
    _clipLayer.layer = null;
    _transformLayer.layer = null;
    super.dispose();
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final pd = child.parentData! as NodeCanvasParentData;
    transform
      ..multiply(_viewMatrix)
      ..multiply(Matrix4.translationValues(pd.offset.dx, pd.offset.dy, 0));
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    if (!size.contains(position)) return false;
    final view = _viewMatrix;
    var child = lastChild;
    while (child != null) {
      final pd = child.parentData! as NodeCanvasParentData;
      if (pd.nodeId != null) {
        final m = view.clone()
          ..multiply(Matrix4.translationValues(pd.offset.dx, pd.offset.dy, 0));
        final c = child;
        final hit = result.addWithPaintTransform(
          transform: m,
          position: position,
          hitTest: (r, p) => c.hitTest(r, position: p),
        );
        if (hit) return true;
      }
      child = pd.previousSibling;
    }
    return false;
  }

  @override
  bool hitTestSelf(Offset position) => true;
}
