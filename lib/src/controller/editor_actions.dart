import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../model/edge.dart';
import '../model/node.dart';
import 'node_editor_controller.dart';

/// Elemento sobre el que se abre un menú o una barra de herramientas.
///
/// Es una jerarquía cerrada, así que la aplicación puede usar `switch`:
///
/// ```dart
/// switch (details.target) {
///   NodeTarget(:final node) => ...,
///   EdgeTarget(:final edge) => ...,
///   LinkTarget(:final child) => ...,
///   SelectionTarget(:final nodeIds) => ...,
///   CanvasTarget(:final worldPosition) => ...,
/// }
/// ```
@immutable
sealed class EditorTarget<T> {
  const EditorTarget();
}

/// El fondo del lienzo, en [worldPosition].
class CanvasTarget<T> extends EditorTarget<T> {
  const CanvasTarget(this.worldPosition);
  final Offset worldPosition;

  @override
  bool operator ==(Object other) =>
      other is CanvasTarget<T> && other.worldPosition == worldPosition;

  @override
  int get hashCode => worldPosition.hashCode;
}

/// Un nodo concreto.
class NodeTarget<T> extends EditorTarget<T> {
  const NodeTarget(this.node);
  final NodeData<T> node;

  @override
  bool operator ==(Object other) =>
      other is NodeTarget<T> && other.node.id == node.id;

  @override
  int get hashCode => node.id.hashCode;
}

/// Varios nodos seleccionados a la vez (p. ej. clic derecho sobre uno de
/// ellos).
class SelectionTarget<T> extends EditorTarget<T> {
  const SelectionTarget(this.nodeIds);
  final List<String> nodeIds;

  @override
  bool operator ==(Object other) =>
      other is SelectionTarget<T> && listEquals(other.nodeIds, nodeIds);

  @override
  int get hashCode => Object.hashAll(nodeIds);
}

/// Una conexión.
class EdgeTarget<T> extends EditorTarget<T> {
  const EdgeTarget(this.edge);
  final EdgeData edge;

  @override
  bool operator ==(Object other) =>
      other is EdgeTarget<T> && other.edge.id == edge.id;

  @override
  int get hashCode => edge.id.hashCode;
}

/// Un enlace de jerarquía, identificado por su nodo hijo.
class LinkTarget<T> extends EditorTarget<T> {
  const LinkTarget(this.child, this.parent);
  final NodeData<T> child;
  final NodeData<T>? parent;

  @override
  bool operator ==(Object other) =>
      other is LinkTarget<T> && other.child.id == child.id;

  @override
  int get hashCode => child.id.hashCode;
}

/// Operaciones que el editor sabe hacer por sí mismo. La aplicación decide
/// cuáles muestra, con qué texto, icono y en qué orden.
enum EditorCommand {
  // ------------------------------------------------------------- nodos
  /// Duplica el nodo (o la selección).
  duplicate,

  /// Elimina el nodo (o la selección); sus hijos pasan a ser raíces.
  delete,

  /// Elimina el nodo (o la selección) con todos sus descendientes.
  deleteWithDescendants,

  /// Pliega la rama del nodo.
  collapse,

  /// Despliega la rama del nodo.
  expand,

  /// Quita el nodo (o la selección) de su padre.
  detachFromParent,

  /// Impide mover o redimensionar el nodo (o la selección).
  lock,

  /// Vuelve a permitir moverlo.
  unlock,

  /// Lo pinta por encima del resto.
  bringToFront,

  /// Quita el estilo y el color propios: vuelve al aspecto de su tipo.
  resetStyle,

  /// Centra la cámara en el nodo (o encuadra la selección).
  focus,

  // --------------------------------------------------------- conexiones
  /// Elimina la conexión.
  deleteEdge,

  /// Quita el trazado manual de la conexión.
  straightenEdge,

  /// Activa o detiene la animación de flujo ([EditorAction.selected] indica
  /// si está animada).
  toggleEdgeAnimation,

  /// Cambia el tipo de curva. Hay una acción por curva, con la curva en
  /// [EditorAction.value].
  setEdgeCurve,

  /// Intercambia origen y destino (sólo conexiones sin puertos).
  reverseEdge,

  // ---------------------------------------------------- enlaces padre/hijo
  /// Quita el trazado manual del enlace.
  straightenLink,

  /// Separa al hijo de su padre.
  unlink,

  // -------------------------------------------------------------- lienzo
  selectAll,
  clearSelection,
  fitView,
  undo,
  redo,
}

/// Una operación disponible para un [EditorTarget], lista para ejecutar.
///
/// No tiene texto ni icono: la aplicación los elige según [command] (y
/// [value]) para que encajen con su estilo e idioma.
@immutable
class EditorAction {
  const EditorAction({
    required this.command,
    required VoidCallback run,
    this.value,
    this.enabled = true,
    this.selected = false,
    this.destructive = false,
  }) : _run = run;

  final EditorCommand command;

  /// Dato extra de la acción (p. ej. la [EdgeCurve] de
  /// [EditorCommand.setEdgeCurve]).
  final Object? value;

  /// `false` si ahora mismo no se puede ejecutar (editor bloqueado, nada que
  /// deshacer…). Puedes mostrarla deshabilitada u ocultarla.
  final bool enabled;

  /// Estado actual en acciones de tipo interruptor u opción (la curva actual,
  /// la animación activa…).
  final bool selected;

  /// Borra datos: útil para pintarla en rojo o pedir confirmación.
  final bool destructive;

  final VoidCallback _run;

  /// Ejecuta la acción (no hace nada si no está [enabled]).
  void call() {
    if (enabled) _run();
  }

  @override
  String toString() =>
      'EditorAction(${command.name}${value == null ? '' : ': $value'})';
}

/// Acciones disponibles para cada elemento del editor.
extension EditorActions<T> on NodeEditorController<T> {
  /// Lo que hay que mostrar al pulsar con el botón derecho sobre [node]: el
  /// propio nodo o, si forma parte de una selección múltiple, la selección.
  EditorTarget<T> targetForNode(NodeData<T> node) {
    final sel = selectedNodeIds;
    if (sel.length > 1 && sel.contains(node.id)) {
      return SelectionTarget<T>(sel.toList());
    }
    return NodeTarget<T>(node);
  }

  /// Acciones que el editor puede ejecutar sobre [target], en un orden
  /// razonable para un menú. Sólo incluye las que tienen sentido (no ofrece
  /// "Expandir" en un nodo sin hijos, por ejemplo).
  List<EditorAction> actionsFor(EditorTarget<T> target) {
    final editable = !locked.value;
    EditorAction a(EditorCommand c, VoidCallback run,
            {Object? value,
            bool enabled = true,
            bool selected = false,
            bool destructive = false,
            bool edits = true}) =>
        EditorAction(
          command: c,
          run: run,
          value: value,
          enabled: enabled && (editable || !edits),
          selected: selected,
          destructive: destructive,
        );

    switch (target) {
      case CanvasTarget():
        return [
          a(EditorCommand.selectAll, selectAll,
              enabled: nodeCount > 0, edits: false),
          if (selectedNodeIds.isNotEmpty ||
              selectedEdgeIds.isNotEmpty ||
              selectedLinkIds.isNotEmpty)
            a(EditorCommand.clearSelection, clearSelection, edits: false),
          a(EditorCommand.fitView, () => fitView(animate: true),
              enabled: nodeCount > 0, edits: false),
          a(EditorCommand.undo, undo, enabled: canUndo),
          a(EditorCommand.redo, redo, enabled: canRedo),
        ];

      case NodeTarget(:final node):
        final n = this.node(node.id) ?? node;
        final id = n.id;
        return [
          a(EditorCommand.focus, () => centerOnNode(id, animate: true),
              edits: false),
          a(EditorCommand.duplicate, () => duplicate([id])),
          if (hasChildren(id))
            n.collapsed
                ? a(EditorCommand.expand, () => setCollapsed(id, false))
                : a(EditorCommand.collapse, () => setCollapsed(id, true)),
          if (n.parentId != null)
            a(EditorCommand.detachFromParent, () => setParent(id, null)),
          n.locked
              ? a(EditorCommand.unlock, () => _setLocked([id], false))
              : a(EditorCommand.lock, () => _setLocked([id], true)),
          a(EditorCommand.bringToFront, () => bringToFront([id]), edits: false),
          if (n.style != null || n.color != null)
            a(EditorCommand.resetStyle, () => resetNodeStyle([id])),
          a(EditorCommand.delete, () => removeNode(id), destructive: true),
          if (hasChildren(id))
            a(EditorCommand.deleteWithDescendants,
                () => removeNode(id, withDescendants: true),
                destructive: true),
        ];

      case SelectionTarget(:final nodeIds):
        final ids = [
          for (final id in nodeIds)
            if (containsNode(id)) id
        ];
        final nodes = [for (final id in ids) node(id)!];
        final allLocked = nodes.isNotEmpty && nodes.every((n) => n.locked);
        final withChildren = ids.any(hasChildren);
        return [
          a(EditorCommand.focus, () => _focusNodes(ids), edits: false),
          a(EditorCommand.duplicate, () => duplicate(ids)),
          if (withChildren &&
              nodes.any((n) => !n.collapsed && hasChildren(n.id)))
            a(EditorCommand.collapse, () => _setCollapsedAll(ids, true)),
          if (nodes.any((n) => n.collapsed))
            a(EditorCommand.expand, () => _setCollapsedAll(ids, false)),
          if (nodes.any((n) => n.parentId != null))
            a(EditorCommand.detachFromParent, () => _detachAll(ids)),
          allLocked
              ? a(EditorCommand.unlock, () => _setLocked(ids, false))
              : a(EditorCommand.lock, () => _setLocked(ids, true)),
          a(EditorCommand.bringToFront, () => bringToFront(ids), edits: false),
          if (nodes.any((n) => n.style != null || n.color != null))
            a(EditorCommand.resetStyle, () => resetNodeStyle(ids)),
          a(EditorCommand.delete, () => removeNodes(ids), destructive: true),
          if (withChildren)
            a(EditorCommand.deleteWithDescendants,
                () => removeNodes(ids, withDescendants: true),
                destructive: true),
        ];

      case EdgeTarget(:final edge):
        final e = this.edge(edge.id) ?? edge;
        final id = e.id;
        return [
          a(EditorCommand.toggleEdgeAnimation,
              () => updateEdge(id, (x) => x.copyWith(animated: !x.animated)),
              selected: e.animated),
          for (final c in EdgeCurve.values)
            a(EditorCommand.setEdgeCurve,
                () => updateEdge(id, (x) => x.copyWith(curve: c)),
                value: c, selected: e.curve == c),
          if (e.bend != null)
            a(EditorCommand.straightenEdge, () => setEdgeBend(id, null)),
          if (e.sourcePortId == null && e.targetPortId == null)
            a(EditorCommand.reverseEdge, () => _reverseEdge(id)),
          a(EditorCommand.deleteEdge, () => removeEdge(id), destructive: true),
        ];

      case LinkTarget(:final child):
        final n = node(child.id) ?? child;
        return [
          if (n.linkBend != null)
            a(EditorCommand.straightenLink, () => setLinkBend(n.id, null)),
          if (n.parentId != null)
            a(EditorCommand.unlink, () => setParent(n.id, null),
                destructive: true),
        ];
    }
  }

  /// Acción concreta para [target], o `null` si no está disponible.
  EditorAction? actionFor(EditorTarget<T> target, EditorCommand command,
      {Object? value}) {
    for (final action in actionsFor(target)) {
      if (action.command == command &&
          (value == null || action.value == value)) {
        return action;
      }
    }
    return null;
  }

  void _setLocked(List<String> ids, bool locked) => transaction(() {
        for (final id in ids) {
          updateNode(id, (n) => n.copyWith(locked: locked));
        }
      });

  void _setCollapsedAll(List<String> ids, bool collapsed) => transaction(() {
        for (final id in ids) {
          if (hasChildren(id)) setCollapsed(id, collapsed);
        }
      });

  void _detachAll(List<String> ids) => transaction(() {
        for (final id in ids) {
          setParent(id, null);
        }
      });

  void _focusNodes(List<String> ids) =>
      fitView(ids: ids, padding: 80, maxScale: 1.2, animate: true);

  void _reverseEdge(String id) => updateEdge(
      id,
      (e) => e.copyWith(
            sourceNodeId: e.targetNodeId,
            targetNodeId: e.sourceNodeId,
          ));
}
