import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../controller/node_editor_controller.dart';
import '../geometry/edge_path.dart';
import '../geometry/node_geometry.dart';
import '../model/connector_style.dart';
import '../model/edge.dart';
import '../model/node.dart';
import '../model/port.dart';
import '../theme/node_editor_theme.dart';
import 'controls.dart';
import 'alignment_guides.dart';
import 'default_node.dart';
import 'edit_overlay.dart';
import 'effects.dart';
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
    this.onNodeResized,
    this.canResize,
    this.onEdgeReconnected,
    this.onEdgeDisconnected,
    this.onLinkTap,
    this.onLinkContextMenu,
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

  /// Terminó un redimensionado desde la UI (con el rectángulo final).
  final void Function(String nodeId, Rect rect)? onNodeResized;

  /// Permite vetar el redimensionado de nodos concretos.
  final bool Function(NodeData<T> node)? canResize;

  /// Se movió un extremo de una conexión a otro nodo/puerto.
  final void Function(EdgeData before, EdgeData after)? onEdgeReconnected;

  /// Se soltó el extremo de una conexión en el vacío y se eliminó.
  final void Function(EdgeData edge)? onEdgeDisconnected;

  /// Toque sobre un enlace de jerarquía (recibe el nodo hijo).
  final void Function(NodeData<T> child)? onLinkTap;

  /// Clic derecho / pulsación larga sobre un enlace de jerarquía.
  final void Function(NodeData<T> child, Offset globalPosition)?
      onLinkContextMenu;

  @override
  State<NodeEditor<T>> createState() => NodeEditorState<T>();
}

enum _Mode {
  none,
  pan,
  dragNodes,
  connect,
  marquee,
  pinch,
  resize,
  bend,
  relink
}

/// Enlace de jerarquía como destino de un toque (por el id del hijo).
@immutable
class _LinkTarget {
  const _LinkTarget(this.childId);
  final String childId;

  @override
  bool operator ==(Object other) =>
      other is _LinkTarget && other.childId == childId;

  @override
  int get hashCode => childId.hashCode;
}

/// Extremo de una conexión ([edge]) o de un enlace de jerarquía ([link]).
/// [source] = el de origen (en un enlace, el del padre).
typedef _EndHit = ({EdgeData? edge, String? link, bool source});

/// Bordes que mueve un redimensionado.
class _ResizeHit {
  const _ResizeHit(this.nodeId, this.left, this.top, this.right, this.bottom);
  final String nodeId;
  final bool left, top, right, bottom;

  MouseCursor get cursor {
    if ((left && top) || (right && bottom)) {
      return SystemMouseCursors.resizeUpLeftDownRight;
    }
    if ((right && top) || (left && bottom)) {
      return SystemMouseCursors.resizeUpRightDownLeft;
    }
    return left || right
        ? SystemMouseCursors.resizeLeftRight
        : SystemMouseCursors.resizeUpDown;
  }
}

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
  late final EditorEffects _fx;
  // Animaciones activas (configuración + "reducir movimiento" del sistema).
  bool _fxOn = false;
  // Último estado conocido del grafo, para detectar qué cambió y animarlo.
  Map<String, NodeData<T>>? _knownNodes;
  Map<String, Offset> _knownPos = {};
  Map<String, EdgeData>? _knownEdges;
  bool _knownPosStale = true;
  // Último widget de cada nodo que está saliendo.
  final Map<String, Widget> _ghostWidgets = {};
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
  String? _hitLink;
  // Arrastre
  Set<String> _dragIds = const {};
  Offset _dragAccum = Offset.zero;
  Offset _dragStartPos = Offset.zero;
  String? _dropTargetId;
  // Grupo de historial abierto por el gesto en curso.
  bool _group = false;
  // Redimensionado
  _ResizeHit? _resize;
  Rect _resizeStart = Rect.zero;
  Offset _resizeAccum = Offset.zero;
  // Reconexión: conexión cuyo extremo se arrastra (el otro queda fijo).
  EdgeData? _reconnect;
  bool _reconnectSource = false;
  // Enlace de jerarquía cuyo extremo se arrastra (id del hijo).
  String? _relink;
  bool _relinkParentEnd = false;
  String? _relinkTarget;
  String? _relinkInvalid;
  // Guías de alineación del gesto en curso.
  AlignmentSnapper? _snapper;
  Rect _dragBoxStart = Rect.zero;
  // Ratón
  final ValueNotifier<MouseCursor> _cursor =
      ValueNotifier(SystemMouseCursors.basic);
  // Conexión
  String? _connectNode;
  NodePort? _connectPort;
  String? _connectTargetNode;
  NodePort? _connectTargetPort;
  String? _connectInvalidReason;
  // Qué se está creando (conexión o enlace de jerarquía) y con qué estilo.
  ConnectorStyle _connectStyle = const ConnectorStyle();
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
    _fx = EditorEffects(this)
      ..onGhostsChanged = () {
        if (!mounted) return;
        _ghostWidgets.removeWhere((id, _) => !_fx.isGhost(id));
        setState(() {});
      };
    _renderer.effects = _fx;
    _attach(_c);
  }

  @override
  void didUpdateWidget(NodeEditor<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      _detach(oldWidget.controller);
      oldWidget.controller.viewport.configureAnimation(null, owner: this);
      _cameraOn = false;
      _fx.clear();
      _ghostWidgets.clear();
      _resetSnapshots();
      _renderer = SceneRenderer<T>(widget.controller)..effects = _fx;
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
    c.structure.addListener(_onGraphStructure);
    c.selection.addListener(_onStructure);
    c.edgesSignal.addListener(_onEdges);
    c.geometry.addListener(_onGeometry);
    c.viewport.addListener(_onViewport);
    c.locked.addListener(_onLocked);
    _syncTicker();
  }

  void _detach(NodeEditorController<T> c) {
    c.structure.removeListener(_onGraphStructure);
    c.selection.removeListener(_onStructure);
    c.edgesSignal.removeListener(_onEdges);
    c.geometry.removeListener(_onGeometry);
    c.viewport.removeListener(_onViewport);
    c.locked.removeListener(_onLocked);
  }

  @override
  void dispose() {
    _detach(_c);
    _c.viewport.configureAnimation(null, owner: this);
    _fx.dispose();
    _ticker.dispose();
    _longPressTimer?.cancel();
    _interaction.dispose();
    _cursor.dispose();
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
    _diffEdges();
    _syncTicker();
    // Doblar una línea no cambia qué puertos están conectados: la capa de
    // escena se repinta sola y no hace falta reconstruir el editor.
    if (_mode == _Mode.bend) return;
    if (mounted) setState(() {});
  }

  void _onGraphStructure() {
    _diffStructure();
    _onStructure();
  }

  void _onGeometry() {
    _diffPositions();
    _scheduleVisibilityCheck();
  }

  // ============================================================ animaciones

  NodeEditorAnimations get _anim => widget.config.animations;
  bool _cameraOn = false;

  /// Recalcula si hay animaciones (depende de la configuración y de la
  /// preferencia del sistema) y conecta las piezas que las usan.
  void _syncAnimations(BuildContext context) {
    final a = _anim;
    final reduce = a.respectReduceMotion &&
        (MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    final on = a.enabled && !reduce;
    _fx.config = a;
    if (on != _fxOn) {
      _fxOn = on;
      _nodeCache.clear();
      if (on) {
        _resetSnapshots();
        _snapshot();
      } else {
        _fx.clear();
        _ghostWidgets.clear();
        _resetSnapshots();
      }
    }
    final camera = on && a.camera;
    if (camera) {
      _c.viewport
          .configureAnimation(this, owner: this, duration: a.cameraDuration);
    } else if (_cameraOn) {
      _c.viewport.configureAnimation(null, owner: this);
    }
    _cameraOn = camera;
  }

  void _resetSnapshots() {
    _knownNodes = null;
    _knownEdges = null;
    _knownPos = {};
    _knownPosStale = true;
  }

  void _snapshot() {
    _knownNodes = {for (final n in _c.nodes) n.id: n};
    _knownEdges = {for (final e in _c.edges) e.id: e};
    _knownPos = {for (final n in _c.nodes) n.id: n.position};
    _knownPosStale = false;
  }

  /// Zona en la que merece la pena animar (lo que se ve y un poco más).
  Rect get _animArea {
    final v = _c.viewport.visibleWorldRect;
    return v.inflate(math.max(v.width, v.height) * 0.1);
  }

  /// Nodos creados, borrados, re-parentados o ramas plegadas.
  void _diffStructure() {
    if (!_fxOn) return;
    final old = _knownNodes;
    final now = {for (final n in _c.nodes) n.id: n};
    _knownNodes = now;
    if (old == null) return;
    final a = _anim;
    final area = _animArea;
    final removed = [
      for (final id in old.keys)
        if (!now.containsKey(id)) id
    ];
    final added = [
      for (final id in now.keys)
        if (!old.containsKey(id)) id
    ];
    // Recarga completa (cargar un documento, cambiar de escenario…).
    if (removed.length + added.length > a.maxAnimatedNodes) return;
    final editingLine = _reconnect != null || _relink != null;

    for (final id in removed) {
      if (a.edgeExit && old[id]!.parentId != null && !editingLine) {
        _ghostLink(id);
      }
      if (!a.nodeExit || !_visibleSet.contains(id)) continue;
      final w = _nodeCache[id]?.widget;
      if (w == null) continue;
      _ghostWidgets[id] = w;
      final n = old[id]!;
      _fx.nodeExit(id, origin: n.position, size: n.size, autoSize: n.autoSize);
    }
    for (final id in added) {
      if (a.nodeEnter && area.overlaps(_c.rectOf(id)) && !_c.isHidden(id)) {
        _fx.nodeEnter(id);
      }
    }

    var budget = a.maxAnimatedNodes;
    for (final n in now.values) {
      final before = old[n.id];
      if (before == null || identical(before, n)) continue;
      if (before.parentId != n.parentId) {
        if (a.edgeExit && before.parentId != null && !editingLine) {
          _ghostLink(n.id);
        }
        if (a.edgeEnter && n.parentId != null && !_c.isHidden(n.id)) {
          _fx.linkEnter(n.id);
        }
      }
      if (a.collapse && before.collapsed != n.collapsed && budget > 0) {
        budget -= _animateCollapse(n.id, n.collapsed, area, budget);
      }
    }
  }

  /// Recoge (o despliega) los descendientes de [id] hacia (desde) él.
  int _animateCollapse(String id, bool collapsed, Rect area, int budget) {
    final anchor = _c.rectOf(id).center;
    var count = 0;
    for (final d in _c.descendantsOf(id)) {
      if (count >= budget) break;
      final r = _c.rectOf(d);
      if (!area.overlaps(r)) continue;
      final toAnchor = anchor - r.center;
      if (collapsed) {
        // Sólo los que se veían y ahora quedan ocultos.
        if (!_visibleSet.contains(d) || !_c.isHidden(d)) continue;
        final w = _nodeCache[d]?.widget;
        if (w == null) continue;
        _ghostWidgets[d] = w;
        _fx.nodeExit(d, to: toAnchor, scaleTo: 0.3);
      } else {
        if (_c.isHidden(d)) continue;
        _fx.nodeEnter(d, from: toAnchor, scaleFrom: 0.3);
      }
      count++;
    }
    return count;
  }

  void _ghostLink(String childId) {
    final snap = _renderer.linkSnapshot(childId);
    if (snap == null) return;
    final (path, color, width) = snap;
    _fx.addGhostLine(path, color, width);
  }

  /// Conexiones creadas o borradas.
  void _diffEdges() {
    if (!_fxOn || _mode == _Mode.bend) return;
    final old = _knownEdges;
    final now = {for (final e in _c.edges) e.id: e};
    _knownEdges = now;
    if (old == null) return;
    final a = _anim;
    final removed = [
      for (final id in old.keys)
        if (!now.containsKey(id)) id
    ];
    final added = [
      for (final id in now.keys)
        if (!old.containsKey(id)) id
    ];
    if (removed.length + added.length > a.maxAnimatedNodes) return;
    if (a.edgeExit && _reconnect == null) {
      final area = _animArea;
      for (final id in removed) {
        final snap = _renderer.edgeSnapshot(old[id]!);
        if (snap == null) continue;
        final (path, color, width) = snap;
        if (path.getBounds().overlaps(area)) {
          _fx.addGhostLine(path, color, width);
        }
      }
    }
    if (a.edgeEnter) {
      final area = _animArea;
      for (final id in added) {
        final e = now[id]!;
        if (area.overlaps(_c.rectOf(e.sourceNodeId)) ||
            area.overlaps(_c.rectOf(e.targetNodeId))) {
          _fx.edgeEnter(id);
        }
      }
    }
  }

  /// Nodos que cambiaron de sitio fuera de un arrastre (deshacer, layout,
  /// teclado, API): se deslizan desde donde estaban.
  void _diffPositions() {
    if (!_fxOn) return;
    // Durante un gesto (o un layout ya animado) sólo anotamos que la foto
    // quedó vieja; al terminar se renueva sin animar.
    if (_mode != _Mode.none || _c.isAnimatingLayout) {
      _knownPosStale = true;
      return;
    }
    if (_knownPosStale) {
      _knownPos = {for (final n in _c.nodes) n.id: n.position};
      _knownPosStale = false;
      return;
    }
    final a = _anim;
    final jumps = <String, Offset>{};
    var tooMany = false;
    for (final n in _c.nodes) {
      final before = _knownPos[n.id];
      _knownPos[n.id] = n.position;
      if (before == null || before == n.position || tooMany) continue;
      jumps[n.id] = before - n.position;
      if (jumps.length > a.maxAnimatedNodes) tooMany = true;
    }
    if (_knownPos.length > _c.nodeCount * 2 + 64) {
      _knownPos.removeWhere((id, _) => !_c.containsNode(id));
    }
    if (!a.moveTransitions || tooMany || jumps.isEmpty) return;
    final area = _animArea;
    jumps.forEach((id, jump) {
      if (_c.isHidden(id)) return;
      final r = _c.rectOf(id);
      if (area.overlaps(r) || area.overlaps(r.shift(jump))) {
        _fx.glide(id, jump);
      }
    });
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

  /// Muestra (o quita con `null`) un rectángulo fantasma en coordenadas del
  /// mundo. Pensado para dar feedback al arrastrar elementos desde una paleta
  /// propia hasta el lienzo.
  void showDropPreview(Rect? worldRect) {
    if (_interaction.dropPreview == worldRect) return;
    _interaction
      ..dropPreview = worldRect
      ..update();
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
        final pos = rect.topLeft + _theme.portLocalPosition(n, rect.size, p.id);
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

  bool get _connectorHandlesOn =>
      !_readOnly && widget.config.connectorHandles && !_lod;

  /// Nodos que muestran tiradores aunque el ratón no esté encima: el único
  /// seleccionado (así también funcionan en pantallas táctiles).
  List<String> get _selectedHandleNodes {
    if (!_connectorHandlesOn) return const [];
    final sel = _c.selectedNodeIds;
    if (sel.length != 1) return const [];
    final id = sel.first;
    return _c.isHidden(id) ? const [] : [id];
  }

  /// Tirador de conector bajo [world].
  ({String nodeId, PortSide side, Offset position})? _hitConnectorHandle(
      Offset world) {
    if (!_connectorHandlesOn || _interaction.handlesHidden) return null;
    final s = _c.viewport.scale;
    final tol = (EditHandles.connectorHandleRadius + 4) / s;
    final ids = <String>{
      ..._selectedHandleNodes,
      if (_interaction.handleNodeId != null) _interaction.handleNodeId!,
    };
    ({String nodeId, PortSide side, Offset position})? best;
    var bestD = tol;
    for (final id in ids) {
      if (!_c.containsNode(id) || _c.isHidden(id)) continue;
      for (final (side, c)
          in EditHandles.connectorHandles(_renderer.rectOf(id), s)) {
        final d = (c - world).distance;
        if (d <= bestD) {
          bestD = d;
          best = (nodeId: id, side: side, position: c);
        }
      }
    }
    return best;
  }

  bool _canResize(NodeData<T> n) =>
      widget.config.enableNodeResize &&
      !n.locked &&
      (widget.canResize?.call(n) ?? true);

  /// Borde de un nodo bajo [world]. Con ratón vale cualquier borde de
  /// cualquier nodo; en táctil sólo las esquinas del nodo seleccionado, para
  /// no confundir redimensionar con arrastrar.
  _ResizeHit? _hitResize(Offset world, PointerDeviceKind kind) {
    if (_readOnly || !widget.config.enableNodeResize) return null;
    final scale = _c.viewport.scale;
    if (scale < widget.config.lodScale) return null;
    final touch =
        kind == PointerDeviceKind.touch || kind == PointerDeviceKind.stylus;
    final tol = (touch ? 16 : 5) / scale;
    final top = _c.nodeAt(world);
    _ResizeHit? best;
    var bestZ = -1;
    for (final id
        in _c.queryNodes(Rect.fromCircle(center: world, radius: tol))) {
      if (_c.isHidden(id)) continue;
      final n = _c.node(id)!;
      if (!_canResize(n)) continue;
      if (touch && !(_c.selectedNodeIds.length == 1 && _c.isNodeSelected(id))) {
        continue;
      }
      final z = _c.zOf(id);
      // Otro nodo por encima tapa este borde.
      if (top != null && top.id != id && _c.zOf(top.id) > z) continue;
      final r = _c.rectOf(id);
      if (!r.inflate(tol).contains(world)) continue;
      final l = (world.dx - r.left).abs() <= tol;
      final rt = (world.dx - r.right).abs() <= tol;
      final t = (world.dy - r.top).abs() <= tol;
      final b = (world.dy - r.bottom).abs() <= tol;
      final corner = (l || rt) && (t || b);
      if (touch ? !corner : !(l || rt || t || b)) continue;
      if (z > bestZ) {
        bestZ = z;
        best = _ResizeHit(id, l, t, rt && !l, b && !t);
      }
    }
    return best;
  }

  bool get _edgeEditing => !_readOnly && widget.config.enableEdgeEditing;

  /// Botón de borrar de la conexión (o enlace) seleccionado bajo [world].
  (EdgeData?, String?)? _hitDeleteButton(Offset world) {
    if (!_edgeEditing) return null;
    final single = EditHandles.singleSelection(_c);
    if (single == null) return null;
    final (edge, link) = single;
    final g = edge != null
        ? _renderer.geometryOf(edge)
        : _renderer.linkGeometryOf(link!);
    if (g == null) return null;
    final s = _c.viewport.scale;
    final c = EditHandles.deleteButtonCenter(
        edge, g, s, s >= widget.config.labelMinScale);
    final r = (EditHandles.deleteButtonRadius + 4) / s;
    return (c - world).distance <= r ? single : null;
  }

  /// Extremo de una conexión o enlace seleccionado (o bajo el ratón) en
  /// [world].
  _EndHit? _hitEdgeEnd(Offset world) {
    if (!_edgeEditing) return null;
    final slop = _theme.portHitRadius / _c.viewport.scale;
    _EndHit? best;
    var bestD = slop;
    void consider(EdgeGeometry? g, EdgeData? e, String? link) {
      if (g == null) return;
      final ds = (g.polyline.first - world).distance;
      final dt = (g.polyline.last - world).distance;
      if (ds <= bestD) {
        bestD = ds;
        best = (edge: e, link: link, source: true);
      }
      if (dt <= bestD) {
        bestD = dt;
        best = (edge: e, link: link, source: false);
      }
    }

    for (final id in <String>[
      ..._c.selectedEdgeIds.take(EditHandles.maxEdgeHandles),
      if (_interaction.hoverEdgeId != null) _interaction.hoverEdgeId!,
    ]) {
      final e = _c.edge(id);
      if (e != null) consider(_renderer.geometryOf(e), e, null);
    }
    for (final id in <String>[
      ..._c.selectedLinkIds.take(EditHandles.maxEdgeHandles),
      if (_interaction.hoverLinkId != null) _interaction.hoverLinkId!,
    ]) {
      consider(_renderer.linkGeometryOf(id), null, id);
    }
    return best;
  }

  double get _lineTolerance => _theme.edgeHitWidth / _c.viewport.scale;

  /// Enlace de jerarquía bajo [world] (id del hijo).
  String? _hitLinkAt(Offset world) => _renderer.hitLink(world, _lineTolerance);

  /// Conexión más reciente que llega a [port] de [nodeId].
  EdgeData? _lastEdgeAt(String nodeId, NodePort port) {
    EdgeData? last;
    for (final e in _c.edgesOf(nodeId)) {
      if ((e.sourceNodeId == nodeId && e.sourcePortId == port.id) ||
          (e.targetNodeId == nodeId && e.targetPortId == port.id)) {
        last = e;
      }
    }
    return last;
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
    _hitLink = null;

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
      final del = _hitDeleteButton(world);
      if (del != null) {
        final (edge, link) = del;
        if (edge != null) {
          _c.removeEdge(edge.id);
        } else {
          _unlink(link!);
        }
        _mode = _Mode.none;
        return;
      }
      final end = _hitEdgeEnd(world);
      if (end != null) {
        if (end.edge != null) {
          _startReconnect(end.edge!, end.source);
        } else {
          _startRelink(end.link!, end.source);
        }
        return;
      }
      final handle = _hitConnectorHandle(world);
      final portHit = _hitPort(world);
      if (handle != null &&
          (portHit == null ||
              (handle.position - world).distance <
                  (portHit.position - world).distance)) {
        // Tirador (+): crea un conector del tipo elegido, con o sin puertos.
        final rect = _c.rectOf(handle.nodeId);
        final anchor = switch (handle.side) {
          PortSide.top => rect.topCenter,
          PortSide.right => rect.centerRight,
          PortSide.bottom => rect.bottomCenter,
          PortSide.left => rect.centerLeft,
        };
        _startConnection(handle.nodeId, null, anchor, side: handle.side);
        return;
      }
      final port = portHit;
      if (port != null) {
        final existing = _lastEdgeAt(port.nodeId, port.port);
        if (existing != null && _alt) {
          // Alt + clic en un puerto: rompe sus conexiones (como en Unreal).
          _c.removeEdges([
            for (final e in _c.edgesOf(port.nodeId))
              if ((e.sourceNodeId == port.nodeId &&
                      e.sourcePortId == port.port.id) ||
                  (e.targetNodeId == port.nodeId &&
                      e.targetPortId == port.port.id))
                e.id
          ]);
          _mode = _Mode.none;
          return;
        }
        if (existing != null &&
            _edgeEditing &&
            (!port.port.canSend ||
                HardwareKeyboard.instance.isControlPressed ||
                HardwareKeyboard.instance.isMetaPressed)) {
          // Arrastrar desde una entrada ya conectada (o Ctrl/⌘ + arrastrar
          // desde cualquier puerto) recoge su última conexión para moverla.
          _startReconnect(
              existing,
              existing.sourceNodeId == port.nodeId &&
                  existing.sourcePortId == port.port.id);
          return;
        }
        _startConnection(port.nodeId, port.port, port.position);
        return;
      }
      final resize = _hitResize(world, e.kind);
      if (resize != null) {
        _hitNode = resize.nodeId;
        if (!_c.isNodeSelected(resize.nodeId)) _c.selectNode(resize.nodeId);
        _c.bringToFront([resize.nodeId]);
        _resize = resize;
        _mode = _Mode.resize;
        _cursor.value = resize.cursor;
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

    final edge = _renderer.hitEdge(world, _lineTolerance);
    if (edge != null) {
      _hitEdge = edge;
      // En táctil sólo se dobla una línea ya seleccionada, para que arrastrar
      // sobre ella siga moviendo la vista.
      final bend = _edgeEditing &&
          !_multiKey &&
          (e.kind == PointerDeviceKind.mouse || _c.isEdgeSelected(edge.id));
      if (_multiKey) {
        _c.toggleEdgeSelection(edge.id);
      } else {
        _c.selectEdges([edge.id]);
      }
      _mode = bend ? _Mode.bend : _Mode.pan;
      if (e.kind == PointerDeviceKind.touch) _startLongPress(e.position);
      return;
    }

    final link = _hitLinkAt(world);
    if (link != null) {
      _hitLink = link;
      final bend = _edgeEditing &&
          !_multiKey &&
          (e.kind == PointerDeviceKind.mouse || _c.isLinkSelected(link));
      if (_multiKey) {
        _c.toggleLinkSelection(link);
      } else {
        _c.selectLinks([link]);
      }
      _mode = bend ? _Mode.bend : _Mode.pan;
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
      _interaction.handlesHidden = true;
      if (_mode == _Mode.dragNodes) _beginDrag();
      if (_mode == _Mode.resize) _beginResize();
      if (_reconnect != null) _liftReconnecting();
      if (_relink != null) _liftRelink();
      if (_mode == _Mode.bend) _openGroup();
      if (_mode == _Mode.pan || _mode == _Mode.bend) {
        _cursor.value = SystemMouseCursors.grabbing;
      }
    }
    final world = _c.viewport.toWorld(e.localPosition);

    switch (_mode) {
      case _Mode.pan:
        _c.viewport.panBy(e.localDelta);
      case _Mode.dragNodes:
        _updateDrag(e.localDelta, world);
      case _Mode.connect:
        _updateConnection(world);
      case _Mode.resize:
        _updateResize(e.localDelta);
      case _Mode.bend:
        _updateBend(world);
      case _Mode.relink:
        _updateRelink(world);
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
      case _Mode.resize:
        _endResize();
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
      case _Mode.bend:
        if (!_moved) {
          _handleTap(
              _hitEdge ??
                  (_hitLink != null ? _LinkTarget(_hitLink!) : null) ??
                  _canvasTapTarget,
              e.localPosition);
        }
      case _Mode.relink:
        _finishRelink();
      case _Mode.none:
      case _Mode.pinch:
        break;
    }
    _resetInteraction();
    _updateHover(e.localPosition, e.kind);
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
    } else if (target is _LinkTarget) {
      final n = _c.node(target.childId);
      if (n != null && !isDouble) widget.onLinkTap?.call(n);
    } else {
      if (!isDouble) _c.clearSelection();
      if (isDouble) {
        if (widget.config.doubleTapToFit) _c.fitView(animate: true);
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
    final edge = _renderer.hitEdge(world, _lineTolerance);
    if (edge != null) {
      _c.selectEdges([edge.id]);
      widget.onEdgeContextMenu?.call(edge, global);
      return;
    }
    final link = _hitLinkAt(world);
    if (link != null) {
      _c.selectLinks([link]);
      widget.onLinkContextMenu?.call(_c.node(link)!, global);
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
    Rect? box;
    for (final id in ids) {
      if (_c.isHidden(id)) continue;
      final r = _c.rectOf(id);
      box = box == null ? r : box.expandToInclude(r);
    }
    _dragBoxStart = box ?? _c.rectOf(primary);
    _snapper = _buildSnapper(ids);
    _openGroup();
    _cursor.value = SystemMouseCursors.grabbing;
    if (_fxOn && _anim.dragLift) {
      // Con muchos nodos sólo se levanta el que se agarró.
      _fx.lift(ids.length <= 40 ? ids : [primary]);
    }
  }

  /// Rectángulos contra los que alinear: nodos visibles (y algo más) que no
  /// forman parte del gesto.
  AlignmentSnapper? _buildSnapper(Set<String> exclude) {
    if (!widget.config.enableAlignmentGuides) return null;
    final visible = _c.viewport.visibleWorldRect;
    final area = visible.inflate(math.max(visible.width, visible.height) / 2);
    final rects = <Rect>[
      for (final id in _c.queryNodes(area))
        if (!exclude.contains(id) && !_c.isHidden(id)) _c.rectOf(id),
    ];
    return rects.isEmpty ? null : AlignmentSnapper(rects);
  }

  /// Ctrl/⌘ desactiva el imán de alineación mientras se mantiene.
  bool get _guidesActive =>
      _snapper != null &&
      !HardwareKeyboard.instance.isControlPressed &&
      !HardwareKeyboard.instance.isMetaPressed;

  double get _snapTolerance =>
      widget.config.alignmentSnapDistance / _c.viewport.scale;

  void _setGuides(List<AlignmentGuide> guides) {
    if (listEquals(_interaction.guides, guides)) return;
    _interaction
      ..guides = guides
      ..update();
  }

  void _openGroup() {
    if (_group) return;
    _group = true;
    _c.beginHistoryGroup();
  }

  void _closeGroup() {
    if (!_group) return;
    _group = false;
    _c.endHistoryGroup();
  }

  void _updateDrag(Offset screenDelta, Offset world) {
    if (_dragIds.isEmpty) return;
    _dragAccum += screenDelta / _c.viewport.scale;
    var target = _dragStartPos + _dragAccum;
    if (widget.config.snapToGrid) {
      final g = _theme.gridSpacing;
      target = Offset((target.dx / g).round() * g, (target.dy / g).round() * g);
    }
    if (_guidesActive) {
      final box = _dragBoxStart.shift(target - _dragStartPos);
      final res = _snapper!.snap(box, _snapTolerance);
      target += res.delta;
      _setGuides(res.guides);
    } else {
      _setGuides(const []);
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
    _closeGroup();
    if (_dragIds.isNotEmpty) widget.onNodesMoved?.call(_dragIds.toList());
  }

  // --------------------------------------------------------- redimensionado

  void _beginResize() {
    final hit = _resize!;
    final n = _c.node(hit.nodeId);
    if (n == null) {
      _mode = _Mode.none;
      return;
    }
    _openGroup();
    _resizeStart = _c.rectOf(hit.nodeId);
    _resizeAccum = Offset.zero;
    _snapper = _buildSnapper({hit.nodeId});
    // Un nodo autoajustable pasa a tamaño fijo: el usuario manda.
    if (n.autoSize) {
      _c.updateNode(hit.nodeId,
          (n) => n.copyWith(autoSize: false, size: _resizeStart.size));
    }
    _interaction
      ..resizingNodeId = hit.nodeId
      ..update();
  }

  void _updateResize(Offset screenDelta) {
    final hit = _resize;
    if (hit == null || _interaction.resizingNodeId == null) return;
    _resizeAccum += screenDelta / _c.viewport.scale;
    final min = widget.config.minNodeSize;
    final g = _theme.gridSpacing;
    double snap(double v) => widget.config.snapToGrid ? (v / g).round() * g : v;
    final r = _resizeStart;
    var l = r.left, t = r.top, rt = r.right, b = r.bottom;
    if (hit.left) l = math.min(snap(l + _resizeAccum.dx), rt - min.width);
    if (hit.right) rt = math.max(snap(rt + _resizeAccum.dx), l + min.width);
    if (hit.top) t = math.min(snap(t + _resizeAccum.dy), b - min.height);
    if (hit.bottom) b = math.max(snap(b + _resizeAccum.dy), t + min.height);
    if (_guidesActive) {
      // Sólo se alinean los bordes que se están moviendo.
      final lines = AlignLines(
        left: hit.left,
        centerX: false,
        right: hit.right,
        top: hit.top,
        centerY: false,
        bottom: hit.bottom,
      );
      final res = _snapper!
          .snap(Rect.fromLTRB(l, t, rt, b), _snapTolerance, lines: lines);
      if (hit.left) l = math.min(l + res.delta.dx, rt - min.width);
      if (hit.right) rt = math.max(rt + res.delta.dx, l + min.width);
      if (hit.top) t = math.min(t + res.delta.dy, b - min.height);
      if (hit.bottom) b = math.max(b + res.delta.dy, t + min.height);
      _setGuides(_snapper!.guidesFor(Rect.fromLTRB(l, t, rt, b), lines: lines));
    } else {
      _setGuides(const []);
    }
    _c.setNodeRect(hit.nodeId, Rect.fromLTRB(l, t, rt, b));
  }

  void _endResize() {
    final id = _interaction.resizingNodeId;
    _closeGroup();
    if (id != null && _c.containsNode(id)) {
      widget.onNodeResized?.call(id, _c.rectOf(id));
    }
  }

  // ------------------------------------------------------------- conexión

  /// Empieza a tirar una línea desde [nodeId]: desde un puerto, o desde un
  /// tirador (+) si [port] es `null`.
  void _startConnection(String nodeId, NodePort? port, Offset position,
      {PortSide? side}) {
    final template = widget.config.newConnector;
    _mode = _Mode.connect;
    _connectNode = nodeId;
    _connectPort = port;
    // Los puertos son de datos: desde ellos siempre sale una conexión.
    _connectStyle = port != null && template.isHierarchy
        ? const ConnectorStyle()
        : template;
    _interaction
      ..connectFrom = position
      ..connectFromSide = port?.side ?? side ?? PortSide.right
      // Arrastrar desde una entrada dibuja la línea "hacia atrás".
      ..connectReversed = port != null && !port.canSend
      ..connectTo = position
      ..connectCurve = _connectStyle.isHierarchy
          ? _theme.hierarchyEdgeCurve
          : _connectStyle.curve ?? _theme.edgeCurve
      ..update();
  }

  /// Empieza a arrastrar un extremo de [edge] ([source] = el de origen).
  void _startReconnect(EdgeData edge, bool source) {
    final fixed = _renderer.endpoint(edge, source: !source);
    final moving = _renderer.endpoint(edge, source: source);
    if (fixed == null || moving == null) return;
    _mode = _Mode.connect;
    _reconnect = edge;
    _reconnectSource = source;
    _connectNode = source ? edge.targetNodeId : edge.sourceNodeId;
    final fixedPortId = source ? edge.targetPortId : edge.sourcePortId;
    _connectPort =
        fixedPortId == null ? null : _c.node(_connectNode!)?.port(fixedPortId);
    _c.selectEdges([edge.id]);
    // La línea original se oculta y se dibuja la vista previa en cuanto el
    // puntero se mueve (un simple clic sólo selecciona).
    _interaction
      ..reconnectingEdgeId = null
      ..connectFrom = fixed.$1
      ..connectFromSide = fixed.$2
      ..connectReversed = source
      ..connectTo = moving.$1
      ..connectToSide = moving.$2
      ..connectValid = true
      ..connectCurve = edge.curve ?? _theme.edgeCurve;
  }

  void _liftReconnecting() {
    final edge = _reconnect!;
    _renderer.hiddenEdgeId = edge.id;
    _sceneVersion = Object();
    _cursor.value = SystemMouseCursors.grabbing;
    setState(() {});
    _interaction
      ..reconnectingEdgeId = edge.id
      ..update();
  }

  ({String sNode, String? sPort, String tNode, String? tPort}) _orient(
      String otherNode, NodePort? otherPort) {
    final r = _reconnect;
    if (r != null) {
      return _reconnectSource
          ? (
              sNode: otherNode,
              sPort: otherPort?.id,
              tNode: r.targetNodeId,
              tPort: r.targetPortId
            )
          : (
              sNode: r.sourceNodeId,
              sPort: r.sourcePortId,
              tNode: otherNode,
              tPort: otherPort?.id
            );
    }
    final from = _connectPort;
    final reversed = from != null &&
        (!from.canSend ||
            (from.direction == PortDirection.both &&
                otherPort != null &&
                !otherPort.canReceive));
    return reversed
        ? (
            sNode: otherNode,
            sPort: otherPort?.id,
            tNode: _connectNode!,
            tPort: from.id
          )
        : (
            sNode: _connectNode!,
            sPort: from?.id,
            tNode: otherNode,
            tPort: otherPort?.id
          );
  }

  void _updateConnection(Offset world) {
    if (_reconnect == null && _connectStyle.isHierarchy) {
      _updateHierarchyConnection(world);
      return;
    }
    _interaction.dropTarget = null;
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
          targetPortId: o.tPort,
          ignoreEdgeId: _reconnect?.id);
      _connectTargetNode = hit.nodeId;
      _connectTargetPort = hit.port;
      _connectInvalidReason = check.reason;
      _interaction
        ..connectTo = hit.position
        ..connectToSide = hit.port.side
        ..connectValid = check.isValid;
    } else {
      // Nodo sin puertos (o línea que sale de un tirador) bajo el puntero →
      // conexión flotante a ese nodo.
      final n = _c.nodeAt(world);
      final floating = n != null &&
          (n.ports.isEmpty || (_connectPort == null && _reconnect == null));
      if (floating && (n.id != _connectNode || _c.allowSelfConnections)) {
        final o = _orient(n.id, null);
        final check = _c.checkConnection(
            sourceNodeId: o.sNode,
            sourcePortId: o.sPort,
            targetNodeId: o.tNode,
            targetPortId: o.tPort,
            ignoreEdgeId: _reconnect?.id);
        _connectTargetNode = n.id;
        _connectInvalidReason = check.reason;
        final rect = _c.rectOf(n.id);
        final (at, side) =
            NodeGeometry.floatingAnchor(rect, _interaction.connectFrom!);
        _interaction
          ..connectValid = check.isValid
          ..connectTo = at
          ..connectToSide = side
          ..dropTarget = _connectPort == null ? rect : null;
      } else {
        _interaction
          ..connectValid = null
          ..connectTo = world
          ..connectToSide = null;
      }
    }
    _interaction.update();
  }

  /// Tirando un enlace de jerarquía: el nodo de destino será hijo del de
  /// origen.
  void _updateHierarchyConnection(Offset world) {
    final parent = _connectNode!;
    final n = _c.nodeAt(world);
    _connectTargetNode = null;
    _connectInvalidReason = null;
    if (n == null || n.id == parent) {
      _interaction
        ..connectValid = null
        ..connectTo = world
        ..connectToSide = null
        ..dropTarget = null
        ..update();
      return;
    }
    String? reason;
    if (n.parentId == parent) {
      reason = 'Ya depende de este nodo';
    } else if (!_c.canSetParent(n.id, parent)) {
      reason = 'Crearía un ciclo en la jerarquía';
    } else if (!(widget.canReparent?.call(n, _c.node(parent)!) ?? true)) {
      reason = 'Esta relación no está permitida';
    }
    _connectTargetNode = n.id;
    _connectInvalidReason = reason;
    final rect = _c.rectOf(n.id);
    final (at, side) =
        NodeGeometry.floatingAnchor(rect, _interaction.connectFrom!);
    _interaction
      ..connectValid = reason == null
      ..connectTo = at
      ..connectToSide = side
      ..dropTarget = reason == null ? rect : null
      ..update();
  }

  void _finishConnection(Offset world, Offset global) {
    if (_reconnect != null) {
      _finishReconnect();
      return;
    }
    final targetNode = _connectTargetNode;
    if (targetNode != null) {
      if (_connectInvalidReason != null) {
        widget.onConnectionRejected?.call(_connectInvalidReason!);
      } else if (_connectStyle.isHierarchy) {
        if (_c.setParent(targetNode, _connectNode!)) {
          widget.onParentChanged?.call(targetNode, _connectNode);
        }
      } else {
        final o = _orient(targetNode, _connectTargetPort);
        final e = _c.connect(
          sourceNodeId: o.sNode,
          sourcePortId: o.sPort,
          targetNodeId: o.tNode,
          targetPortId: o.tPort,
          style: _connectStyle,
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
          style: _connectStyle,
        ));
      }
    }
  }

  void _finishReconnect() {
    final before = _reconnect!;
    final target = _connectTargetNode;
    if (!_moved) return; // Sólo un clic: la conexión queda seleccionada.
    if (target != null) {
      if (_connectInvalidReason != null) {
        widget.onConnectionRejected?.call(_connectInvalidReason!);
        return;
      }
      final after = _c.reconnectEdge(
        before.id,
        moveSource: _reconnectSource,
        nodeId: target,
        portId: _connectTargetPort?.id,
      );
      if (after != null && !identical(after, before)) {
        widget.onEdgeReconnected?.call(before, after);
      }
    } else {
      // Soltada en el vacío: se desconecta.
      _c.removeEdge(before.id);
      widget.onEdgeDisconnected?.call(before);
    }
  }

  // ------------------------------------------------- trazado de conexiones

  /// Dobla la conexión (o enlace) pulsada para que pase por [world]. Si se
  /// suelta cerca de su trazado automático, vuelve a él.
  void _updateBend(Offset world) {
    final snapBack = 10 / _c.viewport.scale;
    final edge = _hitEdge;
    if (edge != null) {
      final e = _c.edge(edge.id);
      if (e == null) return;
      final plain = _renderer.straightGeometryOf(e);
      final straight =
          plain != null && (plain.labelPosition - world).distance <= snapBack;
      _c.setEdgeBend(
          e.id,
          straight
              ? null
              : world -
                  _renderer.referenceBetween(e.sourceNodeId, e.targetNodeId));
      return;
    }
    final link = _hitLink;
    if (link == null) return;
    final parent = _c.node(link)?.parentId;
    if (parent == null) return;
    final plain = _renderer.linkGeometryOf(link, straight: true);
    final straight =
        plain != null && (plain.labelPosition - world).distance <= snapBack;
    _c.setLinkBend(link,
        straight ? null : world - _renderer.referenceBetween(parent, link));
  }

  /// Empieza a arrastrar un extremo del enlace de [childId] ([parentEnd] =
  /// el del padre).
  void _startRelink(String childId, bool parentEnd) {
    final ends = _renderer.linkEnds(childId);
    if (ends == null) return;
    _mode = _Mode.relink;
    _relink = childId;
    _relinkParentEnd = parentEnd;
    _c.selectLinks([childId]);
    final (p, c) = ends;
    final fixed = parentEnd ? c : p;
    final moving = parentEnd ? p : c;
    _interaction
      ..connectFrom = fixed.$1
      ..connectFromSide = fixed.$2
      ..connectReversed = parentEnd
      ..connectTo = moving.$1
      ..connectToSide = moving.$2
      ..connectValid = true
      ..connectCurve = _theme.hierarchyEdgeCurve;
  }

  void _liftRelink() {
    final id = _relink!;
    _renderer.hiddenLinkId = id;
    _sceneVersion = Object();
    _cursor.value = SystemMouseCursors.grabbing;
    setState(() {});
    _interaction
      ..reconnectingLinkId = id
      ..update();
  }

  void _updateRelink(Offset world) {
    final child = _relink!;
    final parent = _c.node(child)?.parentId;
    final candidate = _c.nodeAt(world);
    _relinkTarget = candidate?.id;
    _relinkInvalid = null;
    if (candidate != null && parent != null) {
      if (_relinkParentEnd) {
        // Nuevo padre para el hijo.
        if (candidate.id != parent &&
            (!_c.canSetParent(child, candidate.id) ||
                !(widget.canReparent?.call(_c.node(child)!, candidate) ??
                    true))) {
          _relinkInvalid = 'No se puede colgar de ese nodo';
        }
      } else if (candidate.id != child &&
          (!_c.canSetParent(candidate.id, parent) ||
              !(widget.canReparent?.call(candidate, _c.node(parent)!) ??
                  true))) {
        _relinkInvalid = 'Ese nodo no puede depender de este padre';
      }
    }
    final valid = candidate != null && _relinkInvalid == null;
    _interaction
      ..connectTo = world
      ..connectToSide = null
      ..connectValid = candidate == null ? null : valid
      ..dropTarget = valid ? _c.rectOf(candidate.id) : null
      ..update();
  }

  void _finishRelink() {
    final child = _relink!;
    if (!_moved) return; // Sólo un clic: el enlace queda seleccionado.
    final parent = _c.node(child)?.parentId;
    if (parent == null) return;
    final target = _relinkTarget;
    if (target == null) {
      _unlink(child);
      return;
    }
    if (_relinkInvalid != null) {
      widget.onConnectionRejected?.call(_relinkInvalid!);
      return;
    }
    if (_relinkParentEnd) {
      if (target != parent && _c.setParent(child, target)) {
        widget.onParentChanged?.call(child, target);
      }
    } else if (target != child && _c.moveLinkToChild(child, target)) {
      widget.onParentChanged?.call(child, null);
      widget.onParentChanged?.call(target, parent);
    }
  }

  /// Rompe el enlace de [childId] con su padre.
  void _unlink(String childId) {
    if (_c.node(childId)?.parentId == null) return;
    if (_c.setParent(childId, null)) {
      widget.onParentChanged?.call(childId, null);
    }
  }

  void _endCurrent({bool cancel = false}) {
    if (_mode == _Mode.dragNodes ||
        _mode == _Mode.resize ||
        _mode == _Mode.bend) {
      _closeGroup();
    }
    if (cancel) _resetInteraction();
  }

  void _resetInteraction() {
    if (_dropTargetId != null) {
      _nodeCache.remove(_dropTargetId);
      _dropTargetId = null;
      if (mounted) setState(() {});
    }
    if (_reconnect != null || _relink != null) {
      _reconnect = null;
      _relink = null;
      _renderer
        ..hiddenEdgeId = null
        ..hiddenLinkId = null;
      _sceneVersion = Object();
      if (mounted) setState(() {});
    }
    _relinkTarget = null;
    _relinkInvalid = null;
    _snapper = null;
    _closeGroup();
    _resize = null;
    _mode = _Mode.none;
    _dragIds = const {};
    _fx.dropAll();
    if (_fxOn && _knownPosStale) {
      // Lo que se movió durante el gesto ya está en su sitio.
      _knownPos = {for (final n in _c.nodes) n.id: n.position};
      _knownPosStale = false;
    }
    _connectNode = null;
    _connectPort = null;
    _connectTargetNode = null;
    _connectTargetPort = null;
    _connectInvalidReason = null;
    _connectStyle = const ConnectorStyle();
    _interaction.clear();
  }

  // ------------------------------------------------------------ hover

  void _onPointerHover(PointerHoverEvent e) =>
      _updateHover(e.localPosition, e.kind);

  void _onExit(PointerExitEvent e) {
    if (_mode != _Mode.none) return;
    _cursor.value = SystemMouseCursors.basic;
    _setHover(null, null);
    _setHandleHover(null, null);
  }

  void _setHandleHover(String? nodeId, PortSide? side) {
    if (_interaction.handleNodeId == nodeId &&
        _interaction.hoverHandle == side) {
      return;
    }
    _interaction
      ..handleNodeId = nodeId
      ..hoverHandle = side
      ..update();
  }

  /// Nodo cuyos tiradores se muestran con el ratón en [world]: el que está
  /// debajo, o el que ya los mostraba mientras el ratón siga cerca (para
  /// poder llegar a los tiradores, que están fuera del nodo).
  String? _handleNodeAt(Offset world) {
    if (!_connectorHandlesOn) return null;
    final under = _c.nodeAt(world);
    if (under != null) return under.id;
    final current = _interaction.handleNodeId;
    if (current == null || !_c.containsNode(current)) return null;
    final reach = (EditHandles.connectorHandleGap +
            EditHandles.connectorHandleRadius +
            6) /
        _c.viewport.scale;
    return _c.rectOf(current).inflate(reach).contains(world) ? current : null;
  }

  void _setHover(String? edgeId, String? linkId) {
    if (_interaction.hoverEdgeId == edgeId &&
        _interaction.hoverLinkId == linkId) {
      return;
    }
    _interaction
      ..hoverEdgeId = edgeId
      ..hoverLinkId = linkId
      ..update();
  }

  /// Cursor y resaltado según lo que haya bajo el ratón.
  void _updateHover(Offset local, PointerDeviceKind kind) {
    if (kind == PointerDeviceKind.touch || _mode != _Mode.none) return;
    final world = _c.viewport.toWorld(local);
    var handle = _hitConnectorHandle(world);
    if (handle != null && !_readOnly) {
      final port = _hitPort(world);
      if (port != null &&
          (port.position - world).distance <
              (handle.position - world).distance) {
        handle = null;
      }
    }
    _setHandleHover(handle?.nodeId ?? _handleNodeAt(world), handle?.side);
    if (handle != null) {
      _cursor.value = SystemMouseCursors.precise;
      _setHover(null, null);
      return;
    }
    MouseCursor cursor = SystemMouseCursors.basic;
    var hover = _interaction.hoverEdgeId;
    var hoverLink = _interaction.hoverLinkId;
    // Las líneas se pueden arrastrar para cambiar su trazado.
    final lineCursor =
        _edgeEditing ? SystemMouseCursors.move : SystemMouseCursors.click;
    if (_hitDeleteButton(world) != null) {
      cursor = SystemMouseCursors.click;
    } else if (_hitEdgeEnd(world) != null) {
      cursor = SystemMouseCursors.grab;
    } else if (!_readOnly && _hitPort(world) != null) {
      cursor = SystemMouseCursors.precise;
      hover = hoverLink = null;
    } else {
      final resize = _hitResize(world, kind);
      final node = resize == null ? _c.nodeAt(world) : null;
      if (resize != null) {
        cursor = resize.cursor;
        hover = hoverLink = null;
      } else if (node != null) {
        if (!_readOnly && !node.locked) cursor = SystemMouseCursors.grab;
        hover = hoverLink = null;
      } else {
        final edge = _renderer.hitEdge(world, _lineTolerance);
        hover = edge?.id;
        hoverLink = edge == null ? _hitLinkAt(world) : null;
        if (edge != null || hoverLink != null) cursor = lineCursor;
      }
    }
    _cursor.value = cursor;
    _setHover(hover, hoverLink);
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
      _c.fitView(ids: sel.isEmpty ? null : sel, animate: true);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.equal ||
        key == LogicalKeyboardKey.add ||
        key == LogicalKeyboardKey.numpadAdd) {
      _c.viewport.zoomBy(widget.config.zoomStep, animate: true);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.minus ||
        key == LogicalKeyboardKey.numpadSubtract) {
      _c.viewport.zoomBy(1 / widget.config.zoomStep, animate: true);
      return KeyEventResult.handled;
    }
    if (_readOnly) return KeyEventResult.ignored;

    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      final links = _c.selectedLinkIds.toList();
      _c.deleteSelection();
      for (final id in links) {
        if (_c.containsNode(id)) widget.onParentChanged?.call(id, null);
      }
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
      child: _wrapEffect(
        id,
        RepaintBoundary(
          child: NodeFrame(
            node: n,
            state: state,
            theme: _theme,
            showPorts: widget.config.showPorts,
            child: body,
          ),
        ),
      ),
    );
    _nodeCache[id] = _NodeCacheEntry(version, state, w);
    return w;
  }

  Widget _wrapEffect(String id, Widget child) {
    if (!_fxOn) return child;
    return NodeEffect(
      nodeId: id,
      effects: _fx,
      radius: _theme.nodeRadius,
      shadowColor: _theme.brightness == Brightness.dark
          ? const Color(0x99000000)
          : const Color(0x40000000),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    _syncAnimations(context);
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
                ValueListenableBuilder<MouseCursor>(
                  valueListenable: _cursor,
                  builder: (context, cursor, child) => MouseRegion(
                    cursor: cursor,
                    onExit: _onExit,
                    child: child,
                  ),
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: _onPointerDown,
                    onPointerMove: _onPointerMove,
                    onPointerUp: _onPointerUp,
                    onPointerHover: _onPointerHover,
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
                      effects: _fxOn ? _fx : null,
                      children: [
                        const SceneLayer(),
                        // Nodos que se están yendo (borrados o plegados).
                        for (final e in _ghostWidgets.entries)
                          if (!_visibleSet.contains(e.key) &&
                              _fx.isGhost(e.key))
                            e.value,
                        for (final id in _visible)
                          if (_c.containsNode(id)) _buildNode(context, id),
                      ],
                    ),
                  ),
                ),
                IgnorePointer(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: EditOverlayPainter<T>(
                        controller: _c,
                        renderer: _renderer,
                        state: _interaction,
                        theme: theme,
                        edgeEditing: _edgeEditing,
                        nodeResize: !_readOnly && config.enableNodeResize,
                        labelMinScale: config.labelMinScale,
                        canResize: _canResize,
                        connectorHandleNodes: _selectedHandleNodes,
                        effects: _fxOn ? _fx : null,
                      ),
                    ),
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
