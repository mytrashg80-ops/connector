import 'dart:collection';

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../layout/graph_layout.dart';
import '../model/connection.dart';
import '../model/edge.dart';
import '../model/node.dart';
import '../model/port.dart';
import 'spatial_index.dart';
import 'viewport.dart';

/// Genera ids únicos para nodos y conexiones creados desde la UI.
typedef IdGenerator = String Function(String prefix);

/// Señal ligera para notificaciones de grano fino.
class _Signal extends ChangeNotifier {
  int revision = 0;
  void fire() {
    revision++;
    notifyListeners();
  }
}

/// Parche reversible usado por el historial (deshacer/rehacer).
class _Patch<T> {
  _Patch(this.nodesBefore, this.nodesAfter, this.edgesBefore, this.edgesAfter);
  final Map<String, NodeData<T>?> nodesBefore;
  final Map<String, NodeData<T>?> nodesAfter;
  final Map<String, EdgeData?> edgesBefore;
  final Map<String, EdgeData?> edgesAfter;
}

/// Estado y API del editor de nodos.
///
/// Mantiene el grafo, la jerarquía, la selección, el viewport y el historial.
/// Expone notificadores de grano fino ([geometry], [structure], [edgesSignal],
/// [selection]) para que cada capa visual sólo se actualice cuando lo
/// necesita: mover un nodo NO reconstruye widgets, sólo recoloca y repinta.
///
/// También es un [ChangeNotifier] general que avisa ante cualquier cambio,
/// útil para que tu app sincronice su propio estado.
class NodeEditorController<T> extends ChangeNotifier {
  NodeEditorController({
    Iterable<NodeData<T>> nodes = const [],
    Iterable<EdgeData> edges = const [],
    this.connectionValidator,
    this.historyLimit = 200,
    this.allowSelfConnections = false,
    this.allowDuplicateConnections = false,
    IdGenerator? idGenerator,
    NodeViewport? viewport,
    double spatialCellSize = 256,
  })  : viewport = viewport ?? NodeViewport(),
        _index = SpatialIndex(cellSize: spatialCellSize),
        _idGenerator = idGenerator {
    _recording = false;
    for (final n in nodes) {
      _setNode(n.id, n);
    }
    for (final e in edges) {
      _setEdge(e.id, e);
    }
    _recording = true;
    _resetDirty();
  }

  /// Cámara del lienzo.
  final NodeViewport viewport;

  /// Validación adicional para nuevas conexiones.
  ConnectionValidator? connectionValidator;

  /// Número máximo de pasos de deshacer.
  int historyLimit;

  bool allowSelfConnections;
  bool allowDuplicateConnections;

  final IdGenerator? _idGenerator;
  int _idCounter = 0;

  // ---------------------------------------------------------------- estado
  final LinkedHashMap<String, NodeData<T>> _nodes = LinkedHashMap();
  final LinkedHashMap<String, EdgeData> _edges = LinkedHashMap();
  final Map<String, Set<String>> _edgesByNode = {};
  final Map<String, LinkedHashSet<String>> _children = {};
  final Map<String, int> _z = {};
  int _zCounter = 0;
  final Map<String, int> _contentVersion = {};
  final Map<String, Size> _measured = {};
  final SpatialIndex _index;

  final LinkedHashSet<String> _selectedNodes = LinkedHashSet();
  final LinkedHashSet<String> _selectedEdges = LinkedHashSet();

  Set<String>? _hiddenCache;

  // ---------------------------------------------------------------- señales
  final _Signal _geometry = _Signal();
  final _Signal _structure = _Signal();
  final _Signal _edgesSig = _Signal();
  final _Signal _selection = _Signal();
  final ValueNotifier<bool> locked = ValueNotifier(false);

  /// Posiciones o tamaños de nodos cambiaron.
  Listenable get geometry => _geometry;

  /// Nodos añadidos/eliminados, contenido o jerarquía cambiados.
  Listenable get structure => _structure;

  /// Conexiones añadidas/eliminadas/modificadas.
  Listenable get edgesSignal => _edgesSig;

  /// La selección cambió.
  Listenable get selection => _selection;

  int get geometryRevision => _geometry.revision;
  int get structureRevision => _structure.revision;
  int get edgesRevision => _edgesSig.revision;
  int get selectionRevision => _selection.revision;

  bool _geometryDirty = false;
  bool _structureDirty = false;
  bool _edgesDirty = false;
  bool _selectionDirty = false;

  // ---------------------------------------------------------------- historial
  /// Transacciones abiertas: agrupan el historial y retienen notificaciones.
  int _txDepth = 0;

  /// Grupos de historial abiertos (gestos): agrupan el historial pero dejan
  /// pasar las notificaciones para que la UI se actualice en tiempo real.
  int _groupDepth = 0;
  bool _recording = true;
  final Map<String, NodeData<T>?> _txNodes = {};
  final Map<String, EdgeData?> _txEdges = {};
  final List<_Patch<T>> _undo = [];
  final List<_Patch<T>> _redo = [];
  final ValueNotifier<int> _historyVersion = ValueNotifier(0);

  /// Notifica cuando cambia la disponibilidad de deshacer/rehacer.
  ValueListenable<int> get history => _historyVersion;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  // =================================================================== lectura

  Iterable<NodeData<T>> get nodes => _nodes.values;
  Iterable<EdgeData> get edges => _edges.values;
  int get nodeCount => _nodes.length;
  int get edgeCount => _edges.length;

  NodeData<T>? node(String id) => _nodes[id];
  EdgeData? edge(String id) => _edges[id];
  bool containsNode(String id) => _nodes.containsKey(id);

  /// Conexiones que tocan [nodeId].
  Iterable<EdgeData> edgesOf(String nodeId) sync* {
    final ids = _edgesByNode[nodeId];
    if (ids == null) return;
    for (final id in ids) {
      final e = _edges[id];
      if (e != null) yield e;
    }
  }

  Iterable<EdgeData> incomingEdges(String nodeId) =>
      edgesOf(nodeId).where((e) => e.targetNodeId == nodeId);
  Iterable<EdgeData> outgoingEdges(String nodeId) =>
      edgesOf(nodeId).where((e) => e.sourceNodeId == nodeId);

  /// Número de conexiones en un puerto concreto.
  int connectionCount(String nodeId, String portId) {
    var c = 0;
    for (final e in edgesOf(nodeId)) {
      if ((e.sourceNodeId == nodeId && e.sourcePortId == portId) ||
          (e.targetNodeId == nodeId && e.targetPortId == portId)) {
        c++;
      }
    }
    return c;
  }

  /// Puertos de [nodeId] que tienen al menos una conexión.
  Set<String> connectedPorts(String nodeId) {
    final out = <String>{};
    for (final e in edgesOf(nodeId)) {
      if (e.sourceNodeId == nodeId && e.sourcePortId != null) {
        out.add(e.sourcePortId!);
      }
      if (e.targetNodeId == nodeId && e.targetPortId != null) {
        out.add(e.targetPortId!);
      }
    }
    return out;
  }

  /// Tamaño real del nodo (medido si usa `autoSize`).
  Size sizeOf(String id) => _measured[id] ?? _nodes[id]?.size ?? Size.zero;

  /// Rectángulo real del nodo en coordenadas del mundo.
  Rect rectOf(String id) {
    final n = _nodes[id];
    if (n == null) return Rect.zero;
    return n.position & sizeOf(id);
  }

  /// Orden de pintado (mayor = encima).
  int zOf(String id) => _z[id] ?? 0;

  /// Contador que cambia cada vez que el contenido (no la posición) del nodo
  /// cambia. Se usa para cachear widgets.
  int contentVersionOf(String id) => _contentVersion[id] ?? 0;

  /// Ids de nodos (visibles o no) que intersectan [worldRect].
  Set<String> queryNodes(Rect worldRect) => _index.query(worldRect);

  /// Nodo visible más alto bajo [worldPoint].
  NodeData<T>? nodeAt(Offset worldPoint, {Set<String>? exclude}) {
    String? best;
    var bestZ = -1;
    for (final id in _index.queryPoint(worldPoint)) {
      if (exclude != null && exclude.contains(id)) continue;
      if (isHidden(id)) continue;
      if (!rectOf(id).contains(worldPoint)) continue;
      final z = zOf(id);
      if (z > bestZ) {
        bestZ = z;
        best = id;
      }
    }
    return best == null ? null : _nodes[best];
  }

  /// Rectángulo que envuelve todos los nodos visibles.
  Rect? get bounds {
    Rect? b;
    for (final n in _nodes.values) {
      if (isHidden(n.id)) continue;
      final r = rectOf(n.id);
      b = b == null ? r : b.expandToInclude(r);
    }
    return b;
  }

  // ================================================================ jerarquía

  NodeData<T>? parentOf(String id) {
    final p = _nodes[id]?.parentId;
    return p == null ? null : _nodes[p];
  }

  Iterable<NodeData<T>> childrenOf(String id) sync* {
    final c = _children[id];
    if (c == null) return;
    for (final cid in c) {
      final n = _nodes[cid];
      if (n != null) yield n;
    }
  }

  bool hasChildren(String id) => _children[id]?.isNotEmpty ?? false;
  int childCount(String id) => _children[id]?.length ?? 0;

  /// Nodos sin padre (o cuyo padre no existe).
  Iterable<NodeData<T>> get roots => _nodes.values
      .where((n) => n.parentId == null || !_nodes.containsKey(n.parentId));

  /// Descendientes en anchura.
  List<String> descendantsOf(String id) {
    final out = <String>[];
    final queue = Queue<String>()..add(id);
    final seen = <String>{id};
    while (queue.isNotEmpty) {
      final c = _children[queue.removeFirst()];
      if (c == null) continue;
      for (final cid in c) {
        if (seen.add(cid)) {
          out.add(cid);
          queue.add(cid);
        }
      }
    }
    return out;
  }

  /// Ancestros del más cercano al más lejano.
  List<String> ancestorsOf(String id) {
    final out = <String>[];
    final seen = <String>{id};
    var p = _nodes[id]?.parentId;
    while (p != null && _nodes.containsKey(p) && seen.add(p)) {
      out.add(p);
      p = _nodes[p]!.parentId;
    }
    return out;
  }

  int depthOf(String id) => ancestorsOf(id).length;

  /// `true` si algún ancestro está colapsado.
  bool isHidden(String id) {
    final cache = _hiddenCache ??= _computeHidden();
    return cache.contains(id);
  }

  Set<String> _computeHidden() {
    final hidden = <String>{};
    for (final n in _nodes.values) {
      if (n.collapsed && !hidden.contains(n.id)) {
        hidden.addAll(descendantsOf(n.id));
      }
    }
    return hidden;
  }

  // ================================================================ selección

  Set<String> get selectedNodeIds => UnmodifiableSetView(_selectedNodes);
  Set<String> get selectedEdgeIds => UnmodifiableSetView(_selectedEdges);
  bool isNodeSelected(String id) => _selectedNodes.contains(id);
  bool isEdgeSelected(String id) => _selectedEdges.contains(id);

  void selectNodes(Iterable<String> ids, {bool additive = false}) {
    if (!additive) {
      _selectedEdges.clear();
      _selectedNodes.clear();
    }
    _selectedNodes.addAll(ids.where(_nodes.containsKey));
    _selectionDirty = true;
    _flush();
  }

  void selectNode(String id, {bool additive = false}) =>
      selectNodes([id], additive: additive);

  void toggleNodeSelection(String id) {
    if (!_selectedNodes.remove(id)) _selectedNodes.add(id);
    _selectionDirty = true;
    _flush();
  }

  void selectEdges(Iterable<String> ids, {bool additive = false}) {
    if (!additive) {
      _selectedEdges.clear();
      _selectedNodes.clear();
    }
    _selectedEdges.addAll(ids.where(_edges.containsKey));
    _selectionDirty = true;
    _flush();
  }

  void toggleEdgeSelection(String id) {
    if (!_selectedEdges.remove(id)) _selectedEdges.add(id);
    _selectionDirty = true;
    _flush();
  }

  void selectAll() {
    _selectedNodes
      ..clear()
      ..addAll(_nodes.keys.where((id) => !isHidden(id)));
    _selectedEdges.clear();
    _selectionDirty = true;
    _flush();
  }

  void clearSelection() {
    if (_selectedNodes.isEmpty && _selectedEdges.isEmpty) return;
    _selectedNodes.clear();
    _selectedEdges.clear();
    _selectionDirty = true;
    _flush();
  }

  /// Elimina los nodos y conexiones seleccionados (ignora nodos bloqueados).
  void deleteSelection() {
    final nodes =
        _selectedNodes.where((id) => _nodes[id]?.locked != true).toList();
    final edges = _selectedEdges.toList();
    transaction(() {
      removeEdges(edges);
      removeNodes(nodes);
    });
  }

  /// Sube los nodos al frente del orden de pintado.
  void bringToFront(Iterable<String> ids) {
    var changed = false;
    for (final id in ids) {
      if (!_nodes.containsKey(id)) continue;
      if (_z[id] == _zCounter) continue;
      _z[id] = ++_zCounter;
      changed = true;
    }
    if (changed) {
      _structureDirty = true;
      _flush();
    }
  }

  // ================================================================ mutaciones

  /// Genera un id nuevo (usa el `idGenerator` si se proporcionó).
  String generateId([String prefix = 'n']) {
    if (_idGenerator != null) return _idGenerator(prefix);
    String id;
    do {
      id = '$prefix${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
          '${(_idCounter++).toRadixString(36)}';
    } while (_nodes.containsKey(id) || _edges.containsKey(id));
    return id;
  }

  /// Agrupa varias operaciones en un único paso de deshacer y una única
  /// notificación.
  R transaction<R>(R Function() action) {
    beginTransaction();
    try {
      return action();
    } finally {
      commitTransaction();
    }
  }

  void beginTransaction() => _txDepth++;

  void commitTransaction() {
    assert(_txDepth > 0, 'commitTransaction sin beginTransaction');
    if (_txDepth == 0) return;
    _txDepth--;
    if (_txDepth > 0) return;
    _sealHistory();
    _flush();
  }

  /// Abre un grupo de historial para un gesto largo (arrastrar, redimensionar,
  /// reconectar...). Todos los cambios hasta [endHistoryGroup] forman un único
  /// paso de deshacer, pero a diferencia de [beginTransaction] las
  /// notificaciones se emiten al momento.
  void beginHistoryGroup() => _groupDepth++;

  void endHistoryGroup() {
    assert(_groupDepth > 0, 'endHistoryGroup sin beginHistoryGroup');
    if (_groupDepth == 0) return;
    _groupDepth--;
    _sealHistory();
    _flush();
  }

  bool get _grouping => _txDepth > 0 || _groupDepth > 0;

  /// Convierte los cambios acumulados en un paso de deshacer.
  void _sealHistory() {
    if (_grouping) return;
    if (_txNodes.isNotEmpty || _txEdges.isNotEmpty) {
      final nb = <String, NodeData<T>?>{}, na = <String, NodeData<T>?>{};
      _txNodes.forEach((id, before) {
        final after = _nodes[id];
        if (!identical(before, after)) {
          nb[id] = before;
          na[id] = after;
        }
      });
      final eb = <String, EdgeData?>{}, ea = <String, EdgeData?>{};
      _txEdges.forEach((id, before) {
        final after = _edges[id];
        if (!identical(before, after)) {
          eb[id] = before;
          ea[id] = after;
        }
      });
      _txNodes.clear();
      _txEdges.clear();
      if (nb.isNotEmpty || eb.isNotEmpty) {
        _undo.add(_Patch(nb, na, eb, ea));
        if (_undo.length > historyLimit) _undo.removeAt(0);
        _redo.clear();
        _historyVersion.value++;
      }
    }
  }

  void addNode(NodeData<T> node) => addNodes([node]);

  void addNodes(Iterable<NodeData<T>> nodes) {
    transaction(() {
      for (final n in nodes) {
        if (_nodes.containsKey(n.id)) {
          throw ArgumentError('Ya existe un nodo con id "${n.id}"');
        }
        _setNode(n.id, n);
      }
    });
  }

  /// Reemplaza un nodo aplicando [update].
  void updateNode(String id, NodeData<T> Function(NodeData<T> node) update) {
    final n = _nodes[id];
    if (n == null) return;
    final next = update(n);
    assert(next.id == id, 'updateNode no puede cambiar el id');
    transaction(() => _setNode(id, next));
  }

  /// Elimina nodos y sus conexiones. Los hijos pasan a ser raíces, salvo que
  /// [withDescendants] sea `true`.
  void removeNodes(Iterable<String> ids, {bool withDescendants = false}) {
    final targets = <String>{};
    for (final id in ids) {
      if (!_nodes.containsKey(id)) continue;
      targets.add(id);
      if (withDescendants) targets.addAll(descendantsOf(id));
    }
    if (targets.isEmpty) return;
    transaction(() {
      for (final id in targets) {
        for (final e in edgesOf(id).toList()) {
          _setEdge(e.id, null);
        }
        for (final c in childrenOf(id).toList()) {
          if (!targets.contains(c.id)) {
            _setNode(c.id, c.copyWith(clearParent: true));
          }
        }
      }
      for (final id in targets) {
        _setNode(id, null);
      }
    });
  }

  void removeNode(String id, {bool withDescendants = false}) =>
      removeNodes([id], withDescendants: withDescendants);

  /// Desplaza nodos. Con [includeDescendants] mueve también sus subárboles.
  void moveNodes(Iterable<String> ids, Offset delta,
      {bool includeDescendants = false}) {
    if (delta == Offset.zero) return;
    final targets = <String>{};
    for (final id in ids) {
      if (!_nodes.containsKey(id)) continue;
      targets.add(id);
      if (includeDescendants) targets.addAll(descendantsOf(id));
    }
    transaction(() {
      for (final id in targets) {
        final n = _nodes[id]!;
        _setNode(id, n.copyWith(position: n.position + delta));
      }
    });
  }

  /// Cambia posición y tamaño de un nodo a la vez (p. ej. al redimensionarlo
  /// desde un borde).
  void setNodeRect(String id, Rect rect) {
    final n = _nodes[id];
    if (n == null) return;
    if (n.position == rect.topLeft && n.size == rect.size) return;
    transaction(() =>
        _setNode(id, n.copyWith(position: rect.topLeft, size: rect.size)));
  }

  /// Asigna posiciones absolutas.
  void setNodePositions(Map<String, Offset> positions) {
    transaction(() {
      positions.forEach((id, p) {
        final n = _nodes[id];
        if (n != null && n.position != p) _setNode(id, n.copyWith(position: p));
      });
    });
  }

  /// Asigna [parentId] como padre de [childId]. Devuelve `false` si crearía
  /// un ciclo. `null` convierte el nodo en raíz.
  bool setParent(String childId, String? parentId) {
    final child = _nodes[childId];
    if (child == null) return false;
    if (parentId != null) {
      if (parentId == childId || !_nodes.containsKey(parentId)) return false;
      if (ancestorsOf(parentId).contains(childId)) return false;
    }
    if (child.parentId == parentId) return true;
    transaction(() => _setNode(
        childId,
        parentId == null
            ? child.copyWith(clearParent: true)
            : child.copyWith(parentId: parentId)));
    return true;
  }

  /// `true` si [childId] puede colgar de [parentId] sin crear ciclos.
  bool canSetParent(String childId, String parentId) =>
      childId != parentId &&
      _nodes.containsKey(childId) &&
      _nodes.containsKey(parentId) &&
      !ancestorsOf(parentId).contains(childId);

  void setCollapsed(String id, bool collapsed) {
    final n = _nodes[id];
    if (n == null || n.collapsed == collapsed) return;
    transaction(() => _setNode(id, n.copyWith(collapsed: collapsed)));
    if (collapsed) {
      final hidden = descendantsOf(id).toSet();
      if (_selectedNodes.any(hidden.contains)) {
        _selectedNodes.removeAll(hidden);
        _selectionDirty = true;
        _flush();
      }
    }
  }

  void toggleCollapsed(String id) {
    final n = _nodes[id];
    if (n != null) setCollapsed(id, !n.collapsed);
  }

  /// Valida si se puede crear una conexión.
  ///
  /// [ignoreEdgeId] excluye una conexión existente de los límites y de la
  /// detección de duplicados (útil al reconectarla).
  ConnectionCheck checkConnection({
    required String sourceNodeId,
    String? sourcePortId,
    required String targetNodeId,
    String? targetPortId,
    String? ignoreEdgeId,
  }) {
    final s = _nodes[sourceNodeId];
    final t = _nodes[targetNodeId];
    if (s == null || t == null) {
      return const ConnectionCheck.invalid('Nodo inexistente');
    }
    if (!allowSelfConnections && s.id == t.id) {
      return const ConnectionCheck.invalid(
          'No se puede conectar consigo mismo');
    }
    final sp = sourcePortId == null ? null : s.port(sourcePortId);
    final tp = targetPortId == null ? null : t.port(targetPortId);
    if (sourcePortId != null && sp == null) {
      return const ConnectionCheck.invalid('Puerto de origen inexistente');
    }
    if (targetPortId != null && tp == null) {
      return const ConnectionCheck.invalid('Puerto de destino inexistente');
    }
    if (sp != null && !sp.canSend) {
      return const ConnectionCheck.invalid('El puerto de origen es de entrada');
    }
    if (tp != null && !tp.canReceive) {
      return const ConnectionCheck.invalid('El puerto de destino es de salida');
    }
    if (sp?.type != null && tp?.type != null && sp!.type != tp!.type) {
      return ConnectionCheck.invalid(
          'Tipos incompatibles (${sp.type} → ${tp.type})');
    }
    int count(String nodeId, String portId) =>
        connectionCount(nodeId, portId) -
        (_touchesPort(ignoreEdgeId, nodeId, portId) ? 1 : 0);
    if (sp?.maxConnections != null &&
        count(s.id, sp!.id) >= sp.maxConnections!) {
      return const ConnectionCheck.invalid('El puerto de origen está lleno');
    }
    if (tp?.maxConnections != null &&
        count(t.id, tp!.id) >= tp.maxConnections!) {
      return const ConnectionCheck.invalid('El puerto de destino está lleno');
    }
    if (!allowDuplicateConnections) {
      for (final e in edgesOf(s.id)) {
        if (e.id != ignoreEdgeId &&
            e.sourceNodeId == s.id &&
            e.sourcePortId == sourcePortId &&
            e.targetNodeId == t.id &&
            e.targetPortId == targetPortId) {
          return const ConnectionCheck.invalid('La conexión ya existe');
        }
      }
    }
    final custom = connectionValidator?.call(ConnectionRequest(
        source: s, sourcePort: sp, target: t, targetPort: tp));
    return custom == null
        ? const ConnectionCheck.valid()
        : ConnectionCheck.invalid(custom);
  }

  /// Crea una conexión validada. Devuelve `null` si no es válida.
  EdgeData? connect({
    required String sourceNodeId,
    String? sourcePortId,
    required String targetNodeId,
    String? targetPortId,
    String? id,
    String? label,
    EdgeCurve? curve,
    bool animated = false,
  }) {
    final check = checkConnection(
      sourceNodeId: sourceNodeId,
      sourcePortId: sourcePortId,
      targetNodeId: targetNodeId,
      targetPortId: targetPortId,
    );
    if (!check.isValid) return null;
    final e = EdgeData(
      id: id ?? generateId('e'),
      sourceNodeId: sourceNodeId,
      sourcePortId: sourcePortId,
      targetNodeId: targetNodeId,
      targetPortId: targetPortId,
      label: label,
      curve: curve,
      animated: animated,
    );
    addEdge(e);
    return e;
  }

  bool _touchesPort(String? edgeId, String nodeId, String portId) {
    final e = edgeId == null ? null : _edges[edgeId];
    if (e == null) return false;
    return (e.sourceNodeId == nodeId && e.sourcePortId == portId) ||
        (e.targetNodeId == nodeId && e.targetPortId == portId);
  }

  /// Mueve uno de los extremos de una conexión existente a otro nodo/puerto.
  /// Valida igual que [connect]; devuelve la conexión actualizada o `null`
  /// si no es válida.
  EdgeData? reconnectEdge(
    String edgeId, {
    required bool moveSource,
    required String nodeId,
    String? portId,
  }) {
    final e = _edges[edgeId];
    if (e == null) return null;
    final check = checkConnection(
      sourceNodeId: moveSource ? nodeId : e.sourceNodeId,
      sourcePortId: moveSource ? portId : e.sourcePortId,
      targetNodeId: moveSource ? e.targetNodeId : nodeId,
      targetPortId: moveSource ? e.targetPortId : portId,
      ignoreEdgeId: edgeId,
    );
    if (!check.isValid) return null;
    final next = moveSource
        ? e.copyWith(
            sourceNodeId: nodeId,
            sourcePortId: portId,
            clearSourcePort: portId == null)
        : e.copyWith(
            targetNodeId: nodeId,
            targetPortId: portId,
            clearTargetPort: portId == null);
    if (next.sameEnds(e)) return e;
    transaction(() => _setEdge(edgeId, next));
    return next;
  }

  /// Añade una conexión sin validar.
  void addEdge(EdgeData edge) => addEdges([edge]);

  void addEdges(Iterable<EdgeData> edges) {
    transaction(() {
      for (final e in edges) {
        if (_edges.containsKey(e.id)) {
          throw ArgumentError('Ya existe una conexión con id "${e.id}"');
        }
        _setEdge(e.id, e);
      }
    });
  }

  void updateEdge(String id, EdgeData Function(EdgeData edge) update) {
    final e = _edges[id];
    if (e == null) return;
    final next = update(e);
    assert(next.id == id, 'updateEdge no puede cambiar el id');
    transaction(() => _setEdge(id, next));
  }

  void removeEdges(Iterable<String> ids) {
    transaction(() {
      for (final id in ids.toList()) {
        _setEdge(id, null);
      }
    });
  }

  void removeEdge(String id) => removeEdges([id]);

  /// Duplica nodos (y las conexiones entre ellos). Devuelve los ids nuevos.
  List<String> duplicate(Iterable<String> ids,
      {Offset offset = const Offset(32, 32)}) {
    final source = ids.where(_nodes.containsKey).toList();
    final map = <String, String>{for (final id in source) id: generateId()};
    transaction(() {
      for (final id in source) {
        final n = _nodes[id]!;
        final parent = n.parentId;
        _setNode(
          map[id]!,
          NodeData<T>(
            id: map[id]!,
            position: n.position + offset,
            size: n.size,
            type: n.type,
            title: n.title,
            subtitle: n.subtitle,
            data: n.data,
            ports: n.ports,
            parentId: parent == null ? null : (map[parent] ?? parent),
            collapsed: n.collapsed,
            locked: false,
            autoSize: n.autoSize,
            color: n.color,
          ),
        );
      }
      for (final e in _edges.values.toList()) {
        final s = map[e.sourceNodeId], t = map[e.targetNodeId];
        if (s != null && t != null) {
          final nid = generateId('e');
          _setEdge(nid, e.copyWith(id: nid, sourceNodeId: s, targetNodeId: t));
        }
      }
    });
    selectNodes(map.values);
    return map.values.toList();
  }

  /// Elimina todo el grafo.
  void clear() {
    transaction(() {
      for (final id in _edges.keys.toList()) {
        _setEdge(id, null);
      }
      for (final id in _nodes.keys.toList()) {
        _setNode(id, null);
      }
    });
  }

  // ================================================================ historial

  void undo() {
    if (_undo.isEmpty || _grouping) return;
    final p = _undo.removeLast();
    _applyPatch(p.nodesBefore, p.edgesBefore);
    _redo.add(p);
    _historyVersion.value++;
  }

  void redo() {
    if (_redo.isEmpty || _grouping) return;
    final p = _redo.removeLast();
    _applyPatch(p.nodesAfter, p.edgesAfter);
    _undo.add(p);
    _historyVersion.value++;
  }

  void clearHistory() {
    _undo.clear();
    _redo.clear();
    _historyVersion.value++;
  }

  void _applyPatch(
      Map<String, NodeData<T>?> nodes, Map<String, EdgeData?> edges) {
    final wasRecording = _recording;
    _recording = false;
    try {
      nodes.forEach(_setNode);
      edges.forEach(_setEdge);
    } finally {
      _recording = wasRecording;
    }
    _selectedNodes.removeWhere((id) => !_nodes.containsKey(id));
    _selectedEdges.removeWhere((id) => !_edges.containsKey(id));
    _selectionDirty = true;
    _flush();
  }

  // ================================================================== layout

  AnimationController? _layoutAnimation;

  /// Construye la entrada para un algoritmo de layout.
  LayoutInput layoutInput({Iterable<String>? ids, bool includeHidden = false}) {
    final idSet = ids?.toSet();
    final nodes = <LayoutNode>[
      for (final n in _nodes.values)
        if ((idSet == null || idSet.contains(n.id)) &&
            (includeHidden || !isHidden(n.id)))
          LayoutNode(
            id: n.id,
            size: sizeOf(n.id),
            position: n.position,
            parentId: n.parentId,
          ),
    ];
    final present = {for (final n in nodes) n.id};
    final edges = <LayoutEdge>[
      for (final e in _edges.values)
        if (present.contains(e.sourceNodeId) &&
            present.contains(e.targetNodeId))
          LayoutEdge(e.sourceNodeId, e.targetNodeId),
    ];
    return LayoutInput(nodes: nodes, edges: edges);
  }

  /// Aplica un algoritmo de auto-organización.
  ///
  /// Si se pasa [vsync] la transición se anima. Siempre genera un único paso
  /// de deshacer.
  Future<void> applyLayout(
    GraphLayout layout, {
    Iterable<String>? ids,
    TickerProvider? vsync,
    Duration duration = const Duration(milliseconds: 450),
    Curve curve = Curves.easeInOutCubic,
    bool fitAfter = false,
  }) async {
    final target = layout.compute(layoutInput(ids: ids));
    _layoutAnimation?.stop();
    _layoutAnimation?.dispose();
    _layoutAnimation = null;
    if (vsync == null || duration == Duration.zero) {
      setNodePositions(target);
      if (fitAfter) fitView();
      return;
    }
    final from = <String, Offset>{
      for (final id in target.keys)
        if (_nodes.containsKey(id)) id: _nodes[id]!.position,
    };
    final anim = AnimationController(vsync: vsync, duration: duration);
    _layoutAnimation = anim;
    final curved = CurvedAnimation(parent: anim, curve: curve);
    void tick() {
      final t = curved.value;
      _withoutRecording(() {
        from.forEach((id, a) {
          final n = _nodes[id];
          final b = target[id];
          if (n == null || b == null) return;
          _setNode(id, n.copyWith(position: Offset.lerp(a, b, t)));
        });
      });
      _flush();
    }

    anim.addListener(tick);
    try {
      await anim.forward().orCancel;
    } on TickerCanceled {
      // Interrumpida por otra animación o por dispose.
    }
    if (!identical(_layoutAnimation, anim)) return;
    _layoutAnimation = null;
    anim.dispose();
    // Volvemos al origen sin registrar y aplicamos el destino en un paso.
    _withoutRecording(() => from.forEach((id, a) {
          final n = _nodes[id];
          if (n != null) _setNode(id, n.copyWith(position: a));
        }));
    setNodePositions(target);
    if (fitAfter) fitView();
  }

  void _withoutRecording(void Function() fn) {
    final was = _recording;
    _recording = false;
    try {
      fn();
    } finally {
      _recording = was;
    }
  }

  // ================================================================ viewport

  /// Ajusta la cámara para mostrar todos los nodos (o sólo [ids]).
  void fitView({Iterable<String>? ids, double padding = 48, double? maxScale}) {
    Rect? b;
    for (final id in ids ?? _nodes.keys) {
      if (!_nodes.containsKey(id) || isHidden(id)) continue;
      final r = rectOf(id);
      b = b == null ? r : b.expandToInclude(r);
    }
    if (b == null) return;
    viewport.fitRect(b, padding: padding, maxScale: maxScale ?? 1.5);
  }

  void centerOnNode(String id, {double? scale}) {
    if (!_nodes.containsKey(id)) return;
    viewport.centerOn(rectOf(id).center, scale: scale);
  }

  // =========================================================== serialización

  /// Serializa el grafo. [encodeData] convierte tu `T` a algo JSON.
  Map<String, Object?> toJson({Object? Function(T? data)? encodeData}) => {
        'version': 1,
        'nodes': [for (final n in _nodes.values) n.toJson(encodeData)],
        'edges': [for (final e in _edges.values) e.toJson()],
        'viewport': {
          'x': viewport.offset.dx,
          'y': viewport.offset.dy,
          'scale': viewport.scale,
        },
      };

  /// Reemplaza el grafo por el contenido de [json].
  void loadJson(Map<String, Object?> json,
      {T? Function(Object? raw)? decodeData, bool restoreViewport = true}) {
    final nodes = [
      for (final n in (json['nodes'] as List?) ?? const [])
        NodeData.fromJson<T>((n as Map).cast<String, Object?>(), decodeData),
    ];
    final edges = [
      for (final e in (json['edges'] as List?) ?? const [])
        EdgeData.fromJson((e as Map).cast<String, Object?>()),
    ];
    _withoutRecording(() {
      for (final id in _edges.keys.toList()) {
        _setEdge(id, null);
      }
      for (final id in _nodes.keys.toList()) {
        _setNode(id, null);
      }
      for (final n in nodes) {
        _setNode(n.id, n);
      }
      for (final e in edges) {
        _setEdge(e.id, e);
      }
    });
    _selectedNodes.clear();
    _selectedEdges.clear();
    _selectionDirty = true;
    clearHistory();
    final v = json['viewport'];
    if (restoreViewport && v is Map) {
      viewport.setView(
        offset: Offset(
            (v['x'] as num? ?? 0).toDouble(), (v['y'] as num? ?? 0).toDouble()),
        scale: (v['scale'] as num? ?? 1).toDouble(),
      );
    }
    _flush();
  }

  // ========================================================== uso interno

  /// Lo llama el lienzo al medir nodos con `autoSize`. No usar directamente.
  @internal
  bool reportMeasuredSize(String id, Size size) {
    final n = _nodes[id];
    if (n == null) return false;
    final prev = _measured[id] ?? n.size;
    if (prev == size) return false;
    _measured[id] = size;
    _index.insertOrUpdate(id, n.position & size);
    _scheduleGeometryPulse();
    return true;
  }

  bool _pulseScheduled = false;
  void _scheduleGeometryPulse() {
    if (_pulseScheduled) return;
    _pulseScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _pulseScheduled = false;
      _geometry.fire();
    });
  }

  void _setNode(String id, NodeData<T>? next) {
    final prev = _nodes[id];
    if (identical(prev, next)) return;
    if (_recording && _grouping) _txNodes.putIfAbsent(id, () => prev);
    if (next == null) {
      _nodes.remove(id);
      _index.remove(id);
      _z.remove(id);
      _measured.remove(id);
      _contentVersion.remove(id);
      final pid = prev!.parentId;
      if (pid != null) _children[pid]?.remove(id);
      if (_selectedNodes.remove(id)) _selectionDirty = true;
      _hiddenCache = null;
      _structureDirty = true;
      _geometryDirty = true;
      return;
    }
    _nodes[id] = next;
    if (prev == null) {
      _z[id] = ++_zCounter;
      _contentVersion[id] = 0;
      _structureDirty = true;
      _hiddenCache = null;
    } else if (!prev.sameContentAs(next)) {
      _contentVersion[id] = (_contentVersion[id] ?? 0) + 1;
      _structureDirty = true;
      if (prev.size != next.size || prev.autoSize != next.autoSize) {
        _measured.remove(id);
      }
      if (prev.collapsed != next.collapsed) _hiddenCache = null;
    }
    if (prev?.parentId != next.parentId) {
      if (prev?.parentId != null) _children[prev!.parentId]?.remove(id);
      if (next.parentId != null) {
        (_children[next.parentId!] ??= LinkedHashSet()).add(id);
      }
      _hiddenCache = null;
    }
    _index.insertOrUpdate(id, next.position & sizeOf(id));
    _geometryDirty = true;
  }

  void _setEdge(String id, EdgeData? next) {
    final prev = _edges[id];
    if (identical(prev, next)) return;
    if (_recording && _grouping) _txEdges.putIfAbsent(id, () => prev);
    if (prev != null) {
      _edgesByNode[prev.sourceNodeId]?.remove(id);
      _edgesByNode[prev.targetNodeId]?.remove(id);
    }
    if (next == null) {
      _edges.remove(id);
      if (_selectedEdges.remove(id)) _selectionDirty = true;
    } else {
      _edges[id] = next;
      (_edgesByNode[next.sourceNodeId] ??= {}).add(id);
      (_edgesByNode[next.targetNodeId] ??= {}).add(id);
    }
    _edgesDirty = true;
  }

  void _resetDirty() {
    _geometryDirty = _structureDirty = _edgesDirty = _selectionDirty = false;
  }

  void _flush() {
    if (_txDepth > 0) return;
    final g = _geometryDirty, s = _structureDirty;
    final e = _edgesDirty, sel = _selectionDirty;
    if (!(g || s || e || sel)) return;
    _resetDirty();
    if (s) _structure.fire();
    if (g) _geometry.fire();
    if (e) _edgesSig.fire();
    if (sel) _selection.fire();
    notifyListeners();
  }

  @override
  void dispose() {
    _layoutAnimation?.dispose();
    _geometry.dispose();
    _structure.dispose();
    _edgesSig.dispose();
    _selection.dispose();
    _historyVersion.dispose();
    locked.dispose();
    viewport.dispose();
    super.dispose();
  }
}

/// Utilidad para obtener el puerto de una conexión.
extension EdgePorts<T> on NodeEditorController<T> {
  NodePort? sourcePortOf(EdgeData e) => e.sourcePortId == null
      ? null
      : node(e.sourceNodeId)?.port(e.sourcePortId!);
  NodePort? targetPortOf(EdgeData e) => e.targetPortId == null
      ? null
      : node(e.targetNodeId)?.port(e.targetPortId!);
}
