import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'graph_layout.dart';

/// Construye el bosque (padre → hijos) a partir de `parentId` o de las
/// conexiones (el primer origen entrante de cada nodo es su padre).
Map<String?, List<String>> _forest(LayoutInput input,
    {required bool fromEdges}) {
  final parent = <String, String?>{};
  if (fromEdges) {
    for (final n in input.nodes) {
      parent[n.id] = null;
    }
    for (final e in input.edges) {
      if (parent[e.target] == null && e.source != e.target) {
        // Evita ciclos: no aceptar un padre que desciende del hijo.
        var p = e.source;
        var cyclic = false;
        final seen = <String>{};
        while (seen.add(p)) {
          if (p == e.target) {
            cyclic = true;
            break;
          }
          final next = parent[p];
          if (next == null) break;
          p = next;
        }
        if (!cyclic) parent[e.target] = e.source;
      }
    }
  } else {
    for (final n in input.nodes) {
      final p = n.parentId;
      parent[n.id] = p != null && input.byId.containsKey(p) ? p : null;
    }
  }
  final children = <String?, List<String>>{};
  for (final n in input.nodes) {
    children.putIfAbsent(parent[n.id], () => []).add(n.id);
  }
  return children;
}

Offset _origin(LayoutInput input) {
  if (input.nodes.isEmpty) return Offset.zero;
  var x = double.infinity, y = double.infinity;
  for (final n in input.nodes) {
    x = math.min(x, n.position.dx);
    y = math.min(y, n.position.dy);
  }
  return Offset(x, y);
}

double _cross(Size s, bool vertical) => vertical ? s.width : s.height;
double _depth(Size s, bool vertical) => vertical ? s.height : s.width;

/// Convierte coordenadas abstractas (cross, depth) a la esquina superior
/// izquierda en el mundo.
Offset _toWorld(LayoutDirection dir, double cross, double depth, Size size) {
  final v = dir.isVertical;
  final d = dir.isReversed ? -depth - _depth(size, v) : depth;
  return v ? Offset(cross, d) : Offset(d, cross);
}

/// Árbol ordenado (organigramas, estructura de empresa, inventario).
///
/// Usa la jerarquía `parentId` (o las conexiones con [useEdges]). Cada padre
/// queda centrado sobre sus hijos y los niveles se alinean.
class TreeLayout extends GraphLayout {
  const TreeLayout({
    this.direction = LayoutDirection.topToBottom,
    this.siblingGap = 32,
    this.levelGap = 72,
    this.rootGap = 96,
    this.useEdges = false,
  });

  final LayoutDirection direction;
  final double siblingGap;
  final double levelGap;
  final double rootGap;
  final bool useEdges;

  @override
  Map<String, Offset> compute(LayoutInput input) {
    final v = direction.isVertical;
    final children = _forest(input, fromEdges: useEdges);
    final roots = children[null] ?? const [];
    final depthOf = <String, int>{};
    final levelSize = <int, double>{};

    // Profundidad y tamaño máximo por nivel.
    void walk(String id, int d) {
      depthOf[id] = d;
      final s = _depth(input.byId[id]!.size, v);
      levelSize[d] = math.max(levelSize[d] ?? 0, s);
      for (final c in children[id] ?? const <String>[]) {
        walk(c, d + 1);
      }
    }

    for (final r in roots) {
      walk(r, 0);
    }
    final levelPos = <int, double>{};
    var acc = 0.0;
    for (var d = 0; levelSize.containsKey(d); d++) {
      levelPos[d] = acc;
      acc += levelSize[d]! + levelGap;
    }

    // Anchura (eje cruzado) de cada subárbol.
    final extent = <String, double>{};
    double measure(String id) {
      final own = _cross(input.byId[id]!.size, v);
      final kids = children[id] ?? const <String>[];
      if (kids.isEmpty) return extent[id] = own;
      var sum = 0.0;
      for (final c in kids) {
        sum += measure(c);
      }
      sum += siblingGap * (kids.length - 1);
      return extent[id] = math.max(own, sum);
    }

    final out = <String, Offset>{};
    void place(String id, double start) {
      final size = input.byId[id]!.size;
      final own = _cross(size, v);
      final ext = extent[id]!;
      final kids = children[id] ?? const <String>[];
      var kidsWidth = 0.0;
      for (final c in kids) {
        kidsWidth += extent[c]!;
      }
      kidsWidth += kids.isEmpty ? 0 : siblingGap * (kids.length - 1);
      var cursor = start + (ext - kidsWidth) / 2;
      double? firstCenter, lastCenter;
      for (final c in kids) {
        place(c, cursor);
        final cs = _cross(input.byId[c]!.size, v);
        final p = v ? out[c]!.dx : out[c]!.dy;
        firstCenter ??= p + cs / 2;
        lastCenter = p + cs / 2;
        cursor += extent[c]! + siblingGap;
      }
      // Centrado sobre el primer y el último hijo (árbol "ordenado").
      final cross = firstCenter == null
          ? start + (ext - own) / 2
          : ((firstCenter + lastCenter!) / 2 - own / 2)
              .clamp(start, start + ext - own);
      // Alineamos al centro de su nivel en el eje de profundidad.
      final d = depthOf[id]!;
      final depth = levelPos[d]! + (levelSize[d]! - _depth(size, v)) / 2;
      out[id] = _toWorld(direction, cross, depth, size);
    }

    var cursor = 0.0;
    for (final r in roots) {
      measure(r);
      place(r, cursor);
      cursor += extent[r]! + rootGap;
    }
    return _translateTo(out, input, _origin(input));
  }
}

/// Desplaza el resultado para que su esquina superior izquierda coincida con
/// [origin] (así el layout no "salta" lejos de donde estaba el grafo).
Map<String, Offset> _translateTo(
    Map<String, Offset> pos, LayoutInput input, Offset origin) {
  if (pos.isEmpty) return pos;
  var x = double.infinity, y = double.infinity;
  pos.forEach((id, p) {
    x = math.min(x, p.dx);
    y = math.min(y, p.dy);
  });
  final d = origin - Offset(x, y);
  return pos.map((id, p) => MapEntry(id, p + d));
}

/// Grafo dirigido por capas (cadenas de ensamblado, distribución, flujos).
///
/// Versión ligera de Sugiyama: elimina ciclos, asigna capas por camino más
/// largo y reduce cruces con barycenter.
class LayeredLayout extends GraphLayout {
  const LayeredLayout({
    this.direction = LayoutDirection.leftToRight,
    this.nodeGap = 32,
    this.layerGap = 96,
    this.iterations = 4,
    this.includeHierarchy = true,
  });

  final LayoutDirection direction;
  final double nodeGap;
  final double layerGap;
  final int iterations;

  /// También trata los enlaces padre → hijo como aristas.
  final bool includeHierarchy;

  @override
  Map<String, Offset> compute(LayoutInput input) {
    final v = direction.isVertical;
    final ids = [for (final n in input.nodes) n.id];
    final succ = <String, List<String>>{for (final id in ids) id: []};
    final pred = <String, List<String>>{for (final id in ids) id: []};
    final edges = <(String, String)>[
      for (final e in input.edges)
        if (e.source != e.target) (e.source, e.target),
      if (includeHierarchy)
        for (final n in input.nodes)
          if (n.parentId != null && input.byId.containsKey(n.parentId))
            (n.parentId!, n.id),
    ];

    // 1. Quitar ciclos con DFS (iterativo para no desbordar la pila).
    final adj = <String, List<String>>{for (final id in ids) id: []};
    for (final (s, t) in edges) {
      adj[s]!.add(t);
    }
    final state = <String, int>{}; // 0 = nuevo, 1 = en pila, 2 = hecho
    final back = <(String, String)>{};
    for (final start in ids) {
      if ((state[start] ?? 0) != 0) continue;
      final stack = <(String, int)>[(start, 0)];
      state[start] = 1;
      while (stack.isNotEmpty) {
        final (node, i) = stack.removeLast();
        final out = adj[node]!;
        if (i < out.length) {
          stack.add((node, i + 1));
          final next = out[i];
          final st = state[next] ?? 0;
          if (st == 1) {
            back.add((node, next));
          } else if (st == 0) {
            state[next] = 1;
            stack.add((next, 0));
          }
        } else {
          state[node] = 2;
        }
      }
    }
    final seenEdge = <(String, String)>{};
    for (final e in edges) {
      if (back.contains(e) || !seenEdge.add(e)) continue;
      succ[e.$1]!.add(e.$2);
      pred[e.$2]!.add(e.$1);
    }

    // 2. Capas por camino más largo (orden topológico de Kahn).
    final indeg = {for (final id in ids) id: pred[id]!.length};
    final layer = <String, int>{for (final id in ids) id: 0};
    final queue = [
      for (final id in ids)
        if (indeg[id] == 0) id
    ];
    var qi = 0;
    while (qi < queue.length) {
      final u = queue[qi++];
      for (final w in succ[u]!) {
        layer[w] = math.max(layer[w]!, layer[u]! + 1);
        final d = indeg[w]! - 1;
        indeg[w] = d;
        if (d == 0) queue.add(w);
      }
    }
    final layerCount = layer.values.fold<int>(0, math.max) + 1;
    final layers = List.generate(layerCount, (_) => <String>[]);
    for (final id in ids) {
      layers[layer[id]!].add(id);
    }

    // 3. Reducción de cruces (barycenter alternando direcciones).
    final order = <String, double>{};
    void reindex(List<String> l) {
      for (var i = 0; i < l.length; i++) {
        order[l[i]] = i.toDouble();
      }
    }

    layers.forEach(reindex);
    for (var it = 0; it < iterations; it++) {
      final down = it.isEven;
      final range = down
          ? List.generate(layerCount - 1, (i) => i + 1)
          : List.generate(layerCount - 1, (i) => layerCount - 2 - i);
      for (final li in range) {
        final l = layers[li];
        final bary = <String, double>{};
        for (final id in l) {
          final ref = down ? pred[id]! : succ[id]!;
          bary[id] = ref.isEmpty
              ? order[id]!
              : ref.map((r) => order[r]!).reduce((a, b) => a + b) / ref.length;
        }
        l.sort((a, b) {
          final c = bary[a]!.compareTo(bary[b]!);
          return c != 0 ? c : order[a]!.compareTo(order[b]!);
        });
        reindex(l);
      }
    }

    // 4. Coordenadas: cada capa centrada en el eje cruzado.
    final out = <String, Offset>{};
    var depth = 0.0;
    for (final l in layers) {
      var total = 0.0;
      var maxDepth = 0.0;
      for (final id in l) {
        final s = input.byId[id]!.size;
        total += _cross(s, v);
        maxDepth = math.max(maxDepth, _depth(s, v));
      }
      total += nodeGap * math.max(0, l.length - 1);
      var cursor = -total / 2;
      for (final id in l) {
        final s = input.byId[id]!.size;
        out[id] = _toWorld(
            direction, cursor, depth + (maxDepth - _depth(s, v)) / 2, s);
        cursor += _cross(s, v) + nodeGap;
      }
      depth += maxDepth + layerGap;
    }
    return _translateTo(out, input, _origin(input));
  }
}

/// Árbol radial: la raíz en el centro y cada nivel en un anillo.
class RadialLayout extends GraphLayout {
  const RadialLayout({
    this.ringGap = 80,
    this.minRadius = 220,
    this.useEdges = false,
  });

  final double ringGap;
  final double minRadius;
  final bool useEdges;

  @override
  Map<String, Offset> compute(LayoutInput input) {
    final children = _forest(input, fromEdges: useEdges);
    final roots = children[null] ?? const <String>[];
    if (roots.isEmpty) return const {};
    final leaves = <String, int>{};
    int countLeaves(String id) {
      final kids = children[id] ?? const <String>[];
      if (kids.isEmpty) return leaves[id] = 1;
      var s = 0;
      for (final c in kids) {
        s += countLeaves(c);
      }
      return leaves[id] = s;
    }

    var maxNode = 0.0;
    for (final n in input.nodes) {
      maxNode = math.max(maxNode, math.max(n.size.width, n.size.height));
    }
    final step = math.max(minRadius, maxNode + ringGap);
    final centers = <String, Offset>{};

    void place(String id, int depth, double a0, double a1) {
      final mid = (a0 + a1) / 2;
      final r = depth * step;
      centers[id] = Offset(math.cos(mid) * r, math.sin(mid) * r);
      final kids = children[id] ?? const <String>[];
      final total = leaves[id]!;
      var a = a0;
      for (final c in kids) {
        final span = (a1 - a0) * leaves[c]! / total;
        place(c, depth + 1, a, a + span);
        a += span;
      }
    }

    if (roots.length == 1) {
      countLeaves(roots.first);
      place(roots.first, 0, 0, math.pi * 2);
    } else {
      var total = 0;
      for (final r in roots) {
        total += countLeaves(r);
      }
      var a = 0.0;
      for (final r in roots) {
        final span = math.pi * 2 * leaves[r]! / total;
        place(r, 1, a, a + span);
        a += span;
      }
    }
    final first = input.byId[roots.first]!;
    final anchor =
        first.position + first.size.center(Offset.zero) - centers[roots.first]!;
    return {
      for (final e in centers.entries)
        e.key: anchor + e.value - input.byId[e.key]!.size.center(Offset.zero),
    };
  }
}

/// Mapa mental equilibrado: la raíz en el centro y las ramas repartidas a
/// izquierda y derecha (estilo XMind / MindNode).
class MindMapLayout extends GraphLayout {
  const MindMapLayout({
    this.siblingGap = 16,
    this.levelGap = 64,
    this.useEdges = false,
  });

  final double siblingGap;
  final double levelGap;
  final bool useEdges;

  @override
  Map<String, Offset> compute(LayoutInput input) {
    final children = _forest(input, fromEdges: useEdges);
    final roots = children[null] ?? const <String>[];
    final out = <String, Offset>{};
    final extent = <String, double>{};

    double measure(String id) {
      final own = input.byId[id]!.size.height;
      final kids = children[id] ?? const <String>[];
      if (kids.isEmpty) return extent[id] = own;
      var sum = siblingGap * (kids.length - 1);
      for (final c in kids) {
        sum += measure(c);
      }
      return extent[id] = math.max(own, sum);
    }

    // Coloca el subárbol de `id` con su borde interior en x = edgeX.
    void place(String id, double edgeX, double top, bool right) {
      final size = input.byId[id]!.size;
      final ext = extent[id]!;
      final x = right ? edgeX : edgeX - size.width;
      out[id] = Offset(x, top + (ext - size.height) / 2);
      final kids = children[id] ?? const <String>[];
      var kidsH = siblingGap * math.max(0, kids.length - 1);
      for (final c in kids) {
        kidsH += extent[c]!;
      }
      var cursor = top + (ext - kidsH) / 2;
      final childEdge = right ? x + size.width + levelGap : x - levelGap;
      for (final c in kids) {
        place(c, childEdge, cursor, right);
        cursor += extent[c]! + siblingGap;
      }
    }

    var offsetY = 0.0;
    for (final root in roots) {
      final rs = input.byId[root]!.size;
      final kids = children[root] ?? const <String>[];
      for (final c in kids) {
        measure(c);
      }
      // Reparto equilibrado por altura acumulada.
      final left = <String>[], right = <String>[];
      var lh = 0.0, rh = 0.0;
      for (final c in kids) {
        if (rh <= lh) {
          right.add(c);
          rh += extent[c]! + siblingGap;
        } else {
          left.add(c);
          lh += extent[c]! + siblingGap;
        }
      }
      final height = math.max(rs.height, math.max(lh, rh));
      final rootPos = Offset(0, offsetY + (height - rs.height) / 2);
      out[root] = rootPos;
      for (final (side, list, h) in [(true, right, rh), (false, left, lh)]) {
        var cursor = offsetY + (height - (h - siblingGap)) / 2;
        for (final c in list) {
          place(
            c,
            side ? rootPos.dx + rs.width + levelGap : rootPos.dx - levelGap,
            cursor,
            side,
          );
          cursor += extent[c]! + siblingGap;
        }
      }
      offsetY += height + levelGap * 2;
    }
    if (roots.isEmpty) return out;
    // Mantiene la raíz principal donde estaba.
    final first = input.byId[roots.first]!;
    final d = first.position - out[roots.first]!;
    return out.map((k, p) => MapEntry(k, p + d));
  }
}

/// Rejilla simple (útil para catálogos o elementos sin relaciones).
class GridLayout extends GraphLayout {
  const GridLayout({this.columns, this.gap = const Size(32, 32)});

  /// `null` = raíz cuadrada del número de nodos.
  final int? columns;
  final Size gap;

  @override
  Map<String, Offset> compute(LayoutInput input) {
    final n = input.nodes.length;
    if (n == 0) return const {};
    final cols = columns ?? math.max(1, math.sqrt(n).ceil());
    var cellW = 0.0, cellH = 0.0;
    for (final node in input.nodes) {
      cellW = math.max(cellW, node.size.width);
      cellH = math.max(cellH, node.size.height);
    }
    final origin = _origin(input);
    return {
      for (var i = 0; i < n; i++)
        input.nodes[i].id: origin +
            Offset((i % cols) * (cellW + gap.width),
                (i ~/ cols) * (cellH + gap.height)),
    };
  }
}
