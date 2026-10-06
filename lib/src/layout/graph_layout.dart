import 'dart:ui' show Offset, Size;

/// Orientación de los algoritmos de auto-organización.
enum LayoutDirection {
  topToBottom,
  bottomToTop,
  leftToRight,
  rightToLeft;

  bool get isVertical =>
      this == LayoutDirection.topToBottom ||
      this == LayoutDirection.bottomToTop;
  bool get isReversed =>
      this == LayoutDirection.bottomToTop ||
      this == LayoutDirection.rightToLeft;
}

/// Nodo tal como lo ve un algoritmo de layout.
class LayoutNode {
  const LayoutNode({
    required this.id,
    required this.size,
    required this.position,
    this.parentId,
  });

  final String id;
  final Size size;
  final Offset position;
  final String? parentId;
}

/// Arista tal como la ve un algoritmo de layout.
class LayoutEdge {
  const LayoutEdge(this.source, this.target);
  final String source;
  final String target;
}

/// Grafo de entrada para los layouts (sólo contiene los nodos a organizar).
class LayoutInput {
  LayoutInput({required this.nodes, required this.edges})
      : byId = {for (final n in nodes) n.id: n};

  final List<LayoutNode> nodes;
  final List<LayoutEdge> edges;
  final Map<String, LayoutNode> byId;
}

/// Algoritmo de auto-organización. Devuelve la nueva posición
/// (esquina superior izquierda) de cada nodo.
abstract class GraphLayout {
  const GraphLayout();

  Map<String, Offset> compute(LayoutInput input);
}
