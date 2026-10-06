import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../controller/node_editor_controller.dart';
import '../geometry/node_geometry.dart';
import '../model/edge.dart';
import '../model/node.dart';
import '../model/port.dart';
import '../theme/node_editor_theme.dart';
import 'controls.dart';
import 'default_node.dart';
import 'editor_config.dart';
import 'minimap.dart';
import 'node_canvas.dart';
import 'painters.dart';
import 'scene_renderer.dart';

/// Editor visual de nodos.
///
/// ```dart
/// final controller = NodeEditorController<Empleado>();
/// NodeEditor<Empleado>(
///   controller: controller,
///   theme: NodeEditorTheme.dark(),
///   nodeBuilder: (context, node, state) => MiTarjeta(node.data!),
/// )
/// ```
class NodeEditor<T> extends StatefulWidget {
  const NodeEditor({
    super.key,
    required this.controller,
    this.theme,
    this.config = const NodeEditorConfig(),
    this.nodeBuilder,
    this.focusNode,
    this.autofocus = false,
    this.overlays = const [],
    this.onNodeTap,
    this.onNodeDoubleTap,
    this.onNodeContextMenu,
    this.onEdgeTap,
    this.onEdgeDoubleTap,
    this.onEdgeContextMenu,
    this.onCanvasTap,
    this.onCanvasDoubleTap,
    this.onCanvasContextMenu,
    this.onConnect,
    this.onConnectionRejected,
    this.onConnectionDropped,
    this.onNodesMoved,
    this.onParentChanged,
    this.canReparent,
  });

  final NodeEditorController<T> controller;

  /// `null` usa la extensión `NodeEditorTheme` del `Theme` o el tema
  /// claro/oscuro por defecto según el brillo.
  final NodeEditorTheme? theme;
  final NodeEditorConfig config;

  /// Cuerpo personalizado de cada nodo. Devuelve `null` para el de defecto.
  final NodeWidgetBuilder<T>? nodeBuilder;
  final FocusNode? focusNode;
  final bool autofocus;

  /// Widgets extra apilados sobre el lienzo (barras de herramientas...).
  final List<Widget> overlays;

  final void Function(NodeData<T> node)? onNodeTap;
  final void Function(NodeData<T> node)? onNodeDoubleTap;

  /// Clic derecho / pulsación larga sobre un nodo.
  final void Function(NodeData<T> node, Offset globalPosition)?
      onNodeContextMenu;
  final void Function(EdgeData edge)? onEdgeTap;
  final void Function(EdgeData edge)? onEdgeDoubleTap;
  final void Function(EdgeData edge, Offset globalPosition)? onEdgeContextMenu;
  final void Function(Offset worldPosition)? onCanvasTap;
  final void Function(Offset worldPosition)? onCanvasDoubleTap;
  final void Function(Offset worldPosition, Offset globalPosition)?
      onCanvasContextMenu;

  /// Se creó una conexión desde la UI.
  final void Function(EdgeData edge)? onConnect;

  /// Se intentó una conexión no válida (con el motivo).
  final void Function(String reason)? onConnectionRejected;

  /// Se soltó una conexión sobre el fondo vacío. Útil para ofrecer crear un
  /// nodo nuevo ya conectado.
  final void Function(ConnectionDropDetails<T> details)? onConnectionDropped;

  /// Terminó un arrastre de nodos.
  final void Function(List<String> nodeIds)? onNodesMoved;

  /// Cambió el padre de un nodo desde la UI.
  final void Function(String childId, String? parentId)? onParentChanged;

  /// Permite vetar re-parentados desde la UI.
  final bool Function(NodeData<T> child, NodeData<T> parent)? canReparent;

  @override
  State<NodeEditor<T>> createState() => NodeEditorState<T>();
}

enum _Mode { none, pan, dragNodes, connect, marquee, pinch }

class _NodeCacheEntry {
  _NodeCacheEntry(this.version, this.state, this.widget);
  final int version;
  final NodeViewState state;
  final Widget widget;
}

class NodeEditorState<T> extends State<NodeEditor<T>>
    with TickerProviderStateMixin {
  late SceneRenderer<T> _renderer;
  final InteractionState _interaction = InteractionState();
  final ValueNotifier<double> _dashPhase = ValueNotifier(0);
  late final Ticker _ticker;
  FocusNode? _ownFocus;
  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  NodeEditorController<T> get _c => widget.controller;
  late NodeEditorTheme _theme;

  // Culling
  Rect? _builtRegion;
  bool _lod = false;
  List<String> _visible = const [];
  Set<String> _visibleSet = const {};
  bool _visibilityCheckScheduled = false;
  final Map<String, _NodeCacheEntry> _nodeCache = {};
  Object _sceneVersion = Object();

  // Interacción
  final Map<int, Offset> _pointers = {};
  _Mode _mode = _Mode.none;
  int? _primaryPointer;
  Offset _downLocal = Offset.zero;
  Offset _downWorld = Offset.zero;
  bool _moved = false;
  PointerDeviceKind _downKind = PointerDeviceKind.mouse;
  String? _hitNode;
  EdgeData? _hitEdge;
  // Arrastre
  Set<String> _dragIds = const {};
  Offset _dragAccum = Offset.zero;
  Offset _dragStartPos = Offset.zero;
  bool _dragTx = false;
  String? _dropTargetId;
  // Conexión
  String? _connectNode;
  NodePort? _connectPort;
  String? _connectTargetNode;
  NodePort? _connectTargetPort;
  String? _connectInvalidReason;
  // Pinch
  double _pinchDist = 0;
  Offset _pinchFocal = Offset.zero;
  double _trackpadScale = 1;
  // Taps
  DateTime _lastTapTime = DateTime.fromMillisecondsSinceEpoch(0);
  Object? _lastTapTarget;
  Offset _lastTapPos = Offset.zero;
  // Long press (táctil → menú contextual)
  Timer? _longPressTimer;

  @override
  void initState() {
    super.initState();
    _renderer = SceneRenderer<T>(_c);
    _ticker = createTicker((elapsed) {
      _dashPhase.value = elapsed.inMicroseconds / 1e6 * 24;
    });
    _attach(_c);
  }

  @override
  void didUpdateWidget(NodeEditor<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      _detach(oldWidget.controller);
      _renderer = SceneRenderer<T>(widget.controller);
      _nodeCache.clear();
      _builtRegion = null;
      _attach(widget.controller);
    }
    if (!identical(oldWidget.nodeBuilder, widget.nodeBuilder) ||
        oldWidget.config.readOnly != widget.config.readOnly ||
        oldWidget.config.showPorts != widget.config.showPorts) {
      _nodeCache.clear();
    }
    if (oldWidget.config.showHierarchyLinks !=
            widget.config.showHierarchyLinks ||
        oldWidget.config.hierarchyAxis != widget.config.hierarchyAxis ||
        oldWidget.config.labelMinScale != widget.config.labelMinScale) {
      _sceneVersion = Object();
    }
    if (oldWidget.config.lodScale != widget.config.lodScale ||
        oldWidget.config.cullMargin != widget.config.cullMargin) {
      _builtRegion = null;
    }
  }

  void _attach(NodeEditorController<T> c) {
    c.structure.addListener(_onStructure);
    c.selection.addListener(_onStructure);
    c.edgesSignal.addListener(_onEdges);
    c.geometry.addListener(_scheduleVisibilityCheck);
    c.viewport.addListener(_onViewport);
    c.locked.addListener(_onLocked);
    _syncTicker();
  }

  void _detach(NodeEditorController<T> c) {
    c.structure.removeListener(_onStructure);
    c.selection.removeListener(_onStructure);
    c.edgesSignal.removeListener(_onEdges);
    c.geometry.removeListener(_scheduleVisibilityCheck);
    c.viewport.removeListener(_onViewport);
    c.locked.removeListener(_onLocked);
  }

  @override
  void dispose() {
    _detach(_c);
    _ticker.dispose();
    _longPressTimer?.cancel();
    _interaction.dispose();
    _dashPhase.dispose();
    _renderer.dispose();
    _ownFocus?.dispose();
    super.dispose();
  }

  bool get _readOnly => widget.config.readOnly || _c.locked.value;

  void _onLocked() {
    _nodeCache.clear();
    if (mounted) setState(() {});
  }

  void _onStructure() {
    _builtRegion = null; // fuerza recalcular visibles
    if (mounted) setState(() {});
  }

  void _onEdges() {
    _syncTicker();
    if (mounted) setState(() {});
  }

  void _syncTicker() {
    final animate = _renderer.hasAnimatedEdges;
    if (animate && !_ticker.isActive) {
      _ticker.start();
    } else if (!animate && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _onViewport() {
    final vp = _c.viewport;
    if (vp.size.isEmpty) return;
    final lod = vp.scale < widget.config.lodScale;
    final visible = vp.visibleWorldRect;
    final region = _builtRegion;
    if (lod != _lod ||
        region == null ||
        !region.contains(visible.topLeft) ||
        !region.contains(visible.bottomRight) ||
        // Al alejar mucho la región queda enorme comparada con la vista.
        region.width * region.height >
            visible.width *
                visible.height *
                (1 + 2 * widget.config.cullMargin) *
                (1 + 2 * widget.config.cullMargin) *
                2.5) {
      _builtRegion = null;
      setState(() {});
    }
  }

  /// Tras mover nodos por API (p. ej. un layout) puede que entren o salgan
  /// nodos de la región construida. Lo comprobamos como mucho una vez por
  /// frame.
  void _scheduleVisibilityCheck() {
    if (_visibilityCheckScheduled) return;
    _visibilityCheckScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _visibilityCheckScheduled = false;
      if (!mounted || _lod) return;
      final region = _builtRegion;
      if (region == null) return;
      final now = _c.queryNodes(region);
      now.removeWhere(_c.isHidden);
      if (now.length != _visibleSet.length || !_visibleSet.containsAll(now)) {
        setState(() => _builtRegion = null);
      }
    });
  }

  void _computeVisible() {
    final vp = _c.viewport;
    _lod = vp.scale < widget.config.lodScale;
    if (vp.size.isEmpty) {
      _visible = const [];
      _visibleSet = const {};
      _builtRegion = null;
      return;
    }
    final visible = vp.visibleWorldRect;
    final margin =
        math.max(visible.width, visible.height) * widget.config.cullMargin;
    _builtRegion = visible.inflate(margin);
    if (_lod) {
      _visible = const [];
      _visibleSet = const {};
      return;
    }
    final ids = _c.queryNodes(_builtRegion!)..removeWhere(_c.isHidden);
    _visibleSet = ids;
    _visible = ids.toList()..sort((a, b) => _c.zOf(a).compareTo(_c.zOf(b)));
    // Libera widgets cacheados de nodos que ya no están cerca.
    if (_nodeCache.length > ids.length * 2 + 64) {
      _nodeCache.removeWhere((id, _) => !ids.contains(id));
    }
  }

  // ===================================================================== API

  /// Convierte una posición global (p. ej. de un `DragTarget`) a coordenadas
  /// del mundo.
  Offset globalToWorld(Offset global) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return global;
    return _c.viewport.toWorld(box.globalToLocal(global));
  }

  Offset worldToGlobal(Offset world) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return world;
    return box.localToGlobal(_c.viewport.toScreen(world));
  }

  // ================================================================= hit-test

  ({String nodeId, NodePort port, Offset position})? _hitPort(Offset world,
      {String? excludeNode}) {
    final scale = _c.viewport.scale;
    final slop = _theme.portHitRadius / scale;
    ({String nodeId, NodePort port, Offset position})? best;
    var bestD = slop;
    var bestZ = -1;
    for (final id
        in _c.queryNodes(Rect.fromCircle(center: world, radius: slop))) {
      if (id == excludeNode || _c.isHidden(id)) continue;
      final n = _c.node(id)!;
      if (n.ports.isEmpty) continue;
      final rect = _c.rectOf(id);
      final z = _c.zOf(id);
      for (final p in n.ports) {
        final pos = rect.topLeft +
            NodeGeometry.portLocalPosition(n, rect.size, p.id,
                topInset: _theme.nodeHeaderHeight);
        final d = (pos - world).distance;
        if (d <= bestD + 0.001 && (d < bestD || z > bestZ)) {
          bestD = d;
          bestZ = z;
          best = (nodeId: id, port: p, position: pos);
        }
      }
    }
    return best;
  }

  // ================================================================ punteros

  bool get _shift => HardwareKeyboard.instance.isShiftPressed;
  bool get _alt => HardwareKeyboard.instance.isAltPressed;
  bool get _multiKey =>
      HardwareKeyboard.instance.isControlPressed ||
      HardwareKeyboard.instance.isMetaPressed ||
      _shift;

  double get _slop => _downKind == PointerDeviceKind.touch ? kTouchSlop : 3;

  void _onPointerDown(PointerDownEvent e) {
    if (!_focus.hasFocus) _focus.requestFocus();
    _pointers[e.pointer] = e.localPosition;

    if (_pointers.length == 2) {
      _cancelLongPress();
      _endCurrent(cancel: true);
      _mode = _Mode.pinch;
      final pts = _pointers.values.toList();
      _pinchDist = (pts[0] - pts[1]).distance;
      _pinchFocal = (pts[0] + pts[1]) / 2;
      return;
    }
    if (_pointers.length > 2 || _mode != _Mode.none) return;

    _primaryPointer = e.pointer;
    _downKind = e.kind;
    _downLocal = e.localPosition;
    _downWorld = _c.viewport.toWorld(e.localPosition);
    _moved = false;
    _hitNode = null;
    _hitEdge = null;

    final world = _downWorld;

    if (e.buttons & kSecondaryMouseButton != 0) {
      _mode = _Mode.none;
      _contextMenuAt(world, e.position);
      return;
    }
    if (e.buttons & kMiddleMouseButton != 0) {
      _mode = _Mode.pan;
      return;
    }

    if (!_readOnly) {
      final port = _hitPort(world);
      if (port != null) {
        _startConnection(port.nodeId, port.port, port.position);
        return;
      }
    }

    final node = _c.nodeAt(world);
    if (node != null) {
      _hitNode = node.id;
      if (_multiKey) {
        _c.toggleNodeSelection(node.id);
      } else if (!_c.isNodeSelected(node.id)) {
        _c.selectNode(node.id);
      }
      _c.bringToFront([node.id]);
      _mode = _Mode.dragNodes;
      if (e.kind == PointerDeviceKind.touch) _startLongPress(e.position);
      return;
    }

    final edge =
        _renderer.hitEdge(world, _theme.edgeHitWidth / _c.viewport.scale);
    if (edge != null) {
      _hitEdge = edge;
      if (_multiKey) {
        _c.toggleEdgeSelection(edge.id);
      } else {
        _c.selectEdges([edge.id]);
      }
      _mode = _Mode.pan;
      if (e.kind == PointerDeviceKind.touch) _startLongPress(e.position);
      return;
    }

    if (_shift ||
        widget.config.marqueeOnEmptyDrag && e.kind == PointerDeviceKind.mouse) {
      _mode = _Mode.marquee;
    } else {
      _mode = _Mode.pan;
      if (e.kind == PointerDeviceKind.touch) _startLongPress(e.position);
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.localPosition;

    if (_mode == _Mode.pinch) {
      if (_pointers.length < 2) return;
      final pts = _pointers.values.take(2).toList();
      final dist = (pts[0] - pts[1]).distance;
      final focal = (pts[0] + pts[1]) / 2;
      final vp = _c.viewport;
      vp.panBy(focal - _pinchFocal);
      if (_pinchDist > 0 && dist > 0) vp.zoomAt(focal, dist / _pinchDist);
      _pinchDist = dist;
      _pinchFocal = focal;
      return;
    }
    if (e.pointer != _primaryPointer) return;

    if (!_moved) {
      if ((e.localPosition - _downLocal).distance < _slop) return;
      _moved = true;
      _cancelLongPress();
      if (_mode == _Mode.dragNodes) _beginDrag();
    }
    final world = _c.viewport.toWorld(e.localPosition);

    switch (_mode) {
      case _Mode.pan:
        _c.viewport.panBy(e.localDelta);
      case _Mode.dragNodes:
        _updateDrag(e.localDelta, world);
      case _Mode.connect:
        _updateConnection(world);
      case _Mode.marquee:
        _interaction
          ..marquee = Rect.fromPoints(_downWorld, world)
          ..update();
      case _Mode.none:
      case _Mode.pinch:
        break;
    }
  }

  void _onPointerUp(PointerUpEvent e) {
    _pointers.remove(e.pointer);
    _cancelLongPress();
    if (_mode == _Mode.pinch) {
      if (_pointers.isEmpty) _mode = _Mode.none;
      return;
    }
    if (e.pointer != _primaryPointer) return;
    _primaryPointer = null;
    final world = _c.viewport.toWorld(e.localPosition);

    switch (_mode) {
      case _Mode.dragNodes:
        if (_moved) {
          _endDrag();
        } else {
          final id = _hitNode;
          if (id != null) {
            if (!_multiKey && _c.selectedNodeIds.length > 1) _c.selectNode(id);
            _handleTap(id, e.localPosition);
          }
        }
      case _Mode.connect:
        _finishConnection(world, e.position);
      case _Mode.marquee:
        final m = _interaction.marquee;
        if (m != null) {
          final ids = _c
              .queryNodes(m)
              .where((id) => !_c.isHidden(id) && m.overlaps(_c.rectOf(id)));
          _c.selectNodes(ids,
              additive: HardwareKeyboard.instance.isControlPressed ||
                  HardwareKeyboard.instance.isMetaPressed);
        } else if (!_moved) {
          _handleTap(null, e.localPosition);
        }
      case _Mode.pan:
        if (!_moved) _handleTap(_hitEdge ?? _canvasTapTarget, e.localPosition);
      case _Mode.none:
      case _Mode.pinch:
        break;
    }
    _resetInteraction();
  }

  void _onPointerCancel(PointerCancelEvent e) {
    _pointers.remove(e.pointer);
    _cancelLongPress();
    if (e.pointer == _primaryPointer ||
        _mode == _Mode.pinch && _pointers.isEmpty) {
      _endCurrent(cancel: true);
      _resetInteraction();
    }
  }

  static const Object _canvasTapTarget = Object();

  void _handleTap(Object? target, Offset local) {
    final now = DateTime.now();
    final world = _c.viewport.toWorld(local);
    final isDouble = now.difference(_lastTapTime) < kDoubleTapTimeout &&
        _lastTapTarget == target &&
        (local - _lastTapPos).distance < kDoubleTapSlop;
    _lastTapTime = isDouble ? DateTime.fromMillisecondsSinceEpoch(0) : now;
    _lastTapTarget = target;
    _lastTapPos = local;

    if (target is String) {
      final n = _c.node(target);
      if (n == null) return;
      if (isDouble) {
        widget.onNodeDoubleTap?.call(n);
      } else {
        widget.onNodeTap?.call(n);
      }
    } else if (target is EdgeData) {
      if (isDouble) {
        widget.onEdgeDoubleTap?.call(target);
      } else {
        widget.onEdgeTap?.call(target);
      }
    } else {
      if (!isDouble) _c.clearSelection();
      if (isDouble) {
        if (widget.config.doubleTapToFit) _c.fitView();
        widget.onCanvasDoubleTap?.call(world);
      } else {
        widget.onCanvasTap?.call(world);
      }
    }
  }

  void _contextMenuAt(Offset world, Offset global) {
    final node = _c.nodeAt(world);
    if (node != null) {
      if (!_c.isNodeSelected(node.id)) _c.selectNode(node.id);
      widget.onNodeContextMenu?.call(node, global);
      return;
    }
    final edge =
        _renderer.hitEdge(world, _theme.edgeHitWidth / _c.viewport.scale);
    if (edge != null) {
      _c.selectEdges([edge.id]);
      widget.onEdgeContextMenu?.call(edge, global);
      return;
    }
    widget.onCanvasContextMenu?.call(world, global);
  }

  void _startLongPress(Offset global) {
    _cancelLongPress();
    _longPressTimer = Timer(kLongPressTimeout, () {
      _longPressTimer = null;
      if (_moved || _mode == _Mode.pinch || _mode == _Mode.none) return;
      final world = _downWorld;
      _resetInteraction();
      _primaryPointer = null;
      HapticFeedback.mediumImpact();
      _contextMenuAt(world, global);
    });
  }

  void _cancelLongPress() {
    _longPressTimer?.cancel();
    _longPressTimer = null;
  }

  // ------------------------------------------------------------- arrastre

  void _beginDrag() {
    if (_readOnly) {
      _mode = _Mode.pan;
      return;
    }
    final ids =
        _c.selectedNodeIds.where((id) => _c.node(id)?.locked == false).toSet();
    if (ids.isEmpty) {
      _mode = _Mode.none;
      return;
    }
    if (widget.config.dragMovesDescendants) {
      // Incluimos subárboles (sin duplicados ni nodos bloqueados).
      for (final id in ids.toList()) {
        ids.addAll(
            _c.descendantsOf(id).where((d) => _c.node(d)?.locked == false));
      }
    }
    _dragIds = ids;
    _dragAccum = Offset.zero;
    final primary =
        _hitNode != null && ids.contains(_hitNode) ? _hitNode! : ids.first;
    _hitNode = primary;
    _dragStartPos = _c.node(primary)!.position;
    _c.beginTransaction();
    _dragTx = true;
  }

  void _updateDrag(Offset screenDelta, Offset world) {
    if (_dragIds.isEmpty) return;
    _dragAccum += screenDelta / _c.viewport.scale;
    var target = _dragStartPos + _dragAccum;
    if (widget.config.snapToGrid) {
      final g = _theme.gridSpacing;
      target = Offset((target.dx / g).round() * g, (target.dy / g).round() * g);
    }
    final current = _c.node(_hitNode!)?.position;
    if (current == null) return;
    final delta = target - current;
    if (delta != Offset.zero) _c.moveNodes(_dragIds, delta);

    // Re-parentado: destino bajo el puntero.
    final reparent = widget.config.reparentMode == ReparentMode.always ||
        (widget.config.reparentMode == ReparentMode.withModifier && _alt);
    String? targetId;
    if (reparent) {
      final candidate = _c.nodeAt(world, exclude: _dragIds);
      if (candidate != null &&
          _dragRoots().every((id) =>
              _c.canSetParent(id, candidate.id) &&
              (widget.canReparent?.call(_c.node(id)!, candidate) ?? true))) {
        targetId = candidate.id;
      }
    }
    if (targetId != _dropTargetId) {
      _dropTargetId = targetId;
      _interaction
        ..dropTarget = targetId == null ? null : _c.rectOf(targetId)
        ..update();
      _nodeCache.remove(targetId);
      setState(() {});
    }
  }

  /// Nodos arrastrados cuyo padre no se arrastra también.
  Iterable<String> _dragRoots() =>
      _dragIds.where((id) => !_dragIds.contains(_c.node(id)?.parentId));

  void _endDrag() {
    final target = _dropTargetId;
    if (target != null) {
      for (final id in _dragRoots().toList()) {
        if (_c.setParent(id, target)) widget.onParentChanged?.call(id, target);
      }
    }
    if (_dragTx) {
      _dragTx = false;
      _c.commitTransaction();
    }
    if (_dragIds.isNotEmpty) widget.onNodesMoved?.call(_dragIds.toList());
  }

  // ------------------------------------------------------------- conexión

  void _startConnection(String nodeId, NodePort port, Offset position) {
    _mode = _Mode.connect;
    _connectNode = nodeId;
    _connectPort = port;
    _interaction
      ..connectFrom = position
      ..connectFromSide = port.side
      // Arrastrar desde una entrada dibuja la línea "hacia atrás".
      ..connectReversed = !port.canSend
      ..connectTo = position
      ..connectCurve = _theme.edgeCurve
      ..update();
  }

  ({String sNode, String? sPort, String tNode, String? tPort}) _orient(
      String otherNode, NodePort? otherPort) {
    final reversed = !_connectPort!.canSend ||
        (_connectPort!.direction == PortDirection.both &&
            otherPort != null &&
            !otherPort.canReceive);
    return reversed
        ? (
            sNode: otherNode,
            sPort: otherPort?.id,
            tNode: _connectNode!,
            tPort: _connectPort!.id
          )
        : (
            sNode: _connectNode!,
            sPort: _connectPort!.id,
            tNode: otherNode,
            tPort: otherPort?.id
          );
  }

  void _updateConnection(Offset world) {
    final hit = _hitPort(world,
        excludeNode: _c.allowSelfConnections ? null : _connectNode);
    _connectTargetNode = null;
    _connectTargetPort = null;
    _connectInvalidReason = null;
    if (hit != null) {
      final o = _orient(hit.nodeId, hit.port);
      final check = _c.checkConnection(
          sourceNodeId: o.sNode,
          sourcePortId: o.sPort,
          targetNodeId: o.tNode,
          targetPortId: o.tPort);
      _connectTargetNode = hit.nodeId;
      _connectTargetPort = hit.port;
      _connectInvalidReason = check.reason;
      _interaction
        ..connectTo = hit.position
        ..connectToSide = hit.port.side
        ..connectValid = check.isValid;
    } else {
      // Nodo sin puertos bajo el puntero → conexión flotante.
      final n = _c.nodeAt(world);
      if (n != null && n.id != _connectNode && n.ports.isEmpty) {
        final o = _orient(n.id, null);
        final check = _c.checkConnection(
            sourceNodeId: o.sNode,
            sourcePortId: o.sPort,
            targetNodeId: o.tNode,
            targetPortId: o.tPort);
        _connectTargetNode = n.id;
        _connectInvalidReason = check.reason;
        _interaction.connectValid = check.isValid;
      } else {
        _interaction.connectValid = null;
      }
      _interaction
        ..connectTo = world
        ..connectToSide = null;
    }
    _interaction.update();
  }

  void _finishConnection(Offset world, Offset global) {
    final targetNode = _connectTargetNode;
    if (targetNode != null) {
      if (_connectInvalidReason != null) {
        widget.onConnectionRejected?.call(_connectInvalidReason!);
      } else {
        final o = _orient(targetNode, _connectTargetPort);
        final e = _c.connect(
          sourceNodeId: o.sNode,
          sourcePortId: o.sPort,
          targetNodeId: o.tNode,
          targetPortId: o.tPort,
        );
        if (e != null) widget.onConnect?.call(e);
      }
    } else if (_moved) {
      final n = _c.node(_connectNode!);
      if (n != null) {
        widget.onConnectionDropped?.call(ConnectionDropDetails<T>(
          node: n,
          port: _connectPort,
          worldPosition: world,
          globalPosition: global,
        ));
      }
    }
  }

  void _endCurrent({bool cancel = false}) {
    if (_mode == _Mode.dragNodes && _dragTx) {
      _dragTx = false;
      _c.commitTransaction();
    }
    if (cancel) _resetInteraction();
  }

  void _resetInteraction() {
    if (_dropTargetId != null) {
      _nodeCache.remove(_dropTargetId);
      _dropTargetId = null;
      if (mounted) setState(() {});
    }
    if (_dragTx) {
      _dragTx = false;
      _c.commitTransaction();
    }
    _mode = _Mode.none;
    _dragIds = const {};
    _connectNode = null;
    _connectPort = null;
    _connectTargetNode = null;
    _connectTargetPort = null;
    _connectInvalidReason = null;
    _interaction.clear();
  }

  // --------------------------------------------------- rueda / trackpad

  void _onPointerSignal(PointerSignalEvent e) {
    if (e is PointerScrollEvent) {
      GestureBinding.instance.pointerSignalResolver.register(e, (event) {
        final s = event as PointerScrollEvent;
        final ctrl = HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed;
        final zoom =
            (widget.config.wheelBehavior == WheelBehavior.zoom) != ctrl;
        if (zoom) {
          final factor = math.exp((-s.scrollDelta.dy / 400).clamp(-0.7, 0.7));
          _c.viewport.zoomAt(s.localPosition, factor);
        } else {
          var d = s.scrollDelta;
          if (_shift && d.dx == 0) d = Offset(d.dy, 0);
          _c.viewport.panBy(-d);
        }
      });
    } else if (e is PointerScaleEvent) {
      _c.viewport.zoomAt(e.localPosition, e.scale);
    }
  }

  void _onPanZoomStart(PointerPanZoomStartEvent e) => _trackpadScale = 1;

  void _onPanZoomUpdate(PointerPanZoomUpdateEvent e) {
    final vp = _c.viewport;
    vp.panBy(e.localPanDelta);
    if (e.scale != _trackpadScale && _trackpadScale > 0) {
      vp.zoomAt(e.localPosition, e.scale / _trackpadScale);
      _trackpadScale = e.scale;
    }
  }

  // ================================================================ teclado

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (!widget.config.enableKeyboardShortcuts) return KeyEventResult.ignored;
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final k = HardwareKeyboard.instance;
    final cmd = k.isControlPressed || k.isMetaPressed;
    final key = e.logicalKey;

    if (cmd && key == LogicalKeyboardKey.keyA) {
      _c.selectAll();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      if (_mode != _Mode.none) {
        _endCurrent(cancel: true);
      } else {
        _c.clearSelection();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyF && !cmd) {
      final sel = _c.selectedNodeIds;
      _c.fitView(ids: sel.isEmpty ? null : sel);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.equal ||
        key == LogicalKeyboardKey.add ||
        key == LogicalKeyboardKey.numpadAdd) {
      _c.viewport.zoomBy(widget.config.zoomStep);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.minus ||
        key == LogicalKeyboardKey.numpadSubtract) {
      _c.viewport.zoomBy(1 / widget.config.zoomStep);
      return KeyEventResult.handled;
    }
    if (_readOnly) return KeyEventResult.ignored;

    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      _c.deleteSelection();
      return KeyEventResult.handled;
    }
    if (cmd && key == LogicalKeyboardKey.keyZ) {
      k.isShiftPressed ? _c.redo() : _c.undo();
      return KeyEventResult.handled;
    }
    if (cmd && key == LogicalKeyboardKey.keyY) {
      _c.redo();
      return KeyEventResult.handled;
    }
    if (cmd && key == LogicalKeyboardKey.keyD) {
      _c.duplicate(_c.selectedNodeIds);
      return KeyEventResult.handled;
    }
    final step = k.isShiftPressed ? _theme.gridSpacing : 1.0;
    final nudge = switch (key) {
      LogicalKeyboardKey.arrowLeft => Offset(-step, 0),
      LogicalKeyboardKey.arrowRight => Offset(step, 0),
      LogicalKeyboardKey.arrowUp => Offset(0, -step),
      LogicalKeyboardKey.arrowDown => Offset(0, step),
      _ => null,
    };
    if (nudge != null && _c.selectedNodeIds.isNotEmpty) {
      _c.moveNodes(
          _c.selectedNodeIds.where((id) => _c.node(id)?.locked == false), nudge,
          includeDescendants: widget.config.dragMovesDescendants);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ================================================================== build

  Widget _buildNode(BuildContext context, String id) {
    final n = _c.node(id)!;
    final childCount = _c.childCount(id);
    final state = NodeViewState(
      selected: _c.isNodeSelected(id),
      dropTarget: _dropTargetId == id,
      childCount: childCount,
      connectedPorts: n.ports.isEmpty ? const {} : _c.connectedPorts(id),
      readOnly: _readOnly,
      onToggleCollapsed: childCount == 0 ? null : () => _c.toggleCollapsed(id),
    );
    final version = _c.contentVersionOf(id);
    final cached = _nodeCache[id];
    if (cached != null && cached.version == version && cached.state == state) {
      return cached.widget;
    }
    final body = widget.nodeBuilder?.call(context, n, state) ??
        DefaultNodeBody(node: n, state: state, theme: _theme);
    final w = NodeSlot(
      key: ValueKey<String>(id),
      nodeId: id,
      child: RepaintBoundary(
        child: NodeFrame(
          node: n,
          state: state,
          theme: _theme,
          showPorts: widget.config.showPorts,
          child: body,
        ),
      ),
    );
    _nodeCache[id] = _NodeCacheEntry(version, state, w);
    return w;
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme ?? NodeEditorTheme.of(context);
    if (!identical(theme, _renderer.currentTheme)) {
      _nodeCache.clear();
      _sceneVersion = Object();
    }
    _theme = theme;
    _renderer
      ..theme = theme
      ..showHierarchyLinks = widget.config.showHierarchyLinks
      ..hierarchyAxis = widget.config.hierarchyAxis
      ..labelMinScale = widget.config.labelMinScale;

    final config = widget.config;
    return NodeEditorScope(
      theme: theme,
      child: Focus(
        focusNode: _focus,
        autofocus: widget.autofocus,
        onKeyEvent: _onKey,
        child: LayoutBuilder(builder: (context, constraints) {
          _c.viewport.size = constraints.biggest;
          if (_builtRegion == null) _computeVisible();
          return ColoredBox(
            color: theme.backgroundColor,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (config.showGrid && theme.gridStyle != GridStyle.none)
                  RepaintBoundary(
                    child: CustomPaint(
                      painter: GridPainter(viewport: _c.viewport, theme: theme),
                    ),
                  ),
                Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: _onPointerDown,
                  onPointerMove: _onPointerMove,
                  onPointerUp: _onPointerUp,
                  onPointerCancel: _onPointerCancel,
                  onPointerSignal: _onPointerSignal,
                  onPointerPanZoomStart: _onPanZoomStart,
                  onPointerPanZoomUpdate: _onPanZoomUpdate,
                  child: NodeCanvas<T>(
                    controller: _c,
                    renderer: _renderer,
                    dashPhase: _dashPhase,
                    lodScale: config.lodScale,
                    cullMargin: config.cullMargin,
                    sceneVersion: _sceneVersion,
                    children: [
                      const SceneLayer(),
                      for (final id in _visible)
                        if (_c.containsNode(id)) _buildNode(context, id),
                    ],
                  ),
                ),
                IgnorePointer(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: InteractionPainter(
                        state: _interaction,
                        viewport: _c.viewport,
                        theme: theme,
                      ),
                    ),
                  ),
                ),
                if (config.showMinimap)
                  Align(
                    alignment: config.minimapAlignment,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: NodeEditorMinimap<T>(
                        controller: _c,
                        theme: theme,
                        size: config.minimapSize,
                      ),
                    ),
                  ),
                if (config.showControls)
                  Align(
                    alignment: config.controlsAlignment,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: NodeEditorControls<T>(
                        controller: _c,
                        theme: theme,
                        zoomStep: config.zoomStep,
                        showLock: !config.readOnly,
                      ),
                    ),
                  ),
                ...widget.overlays,
              ],
            ),
          );
        }),
      ),
    );
  }
}
