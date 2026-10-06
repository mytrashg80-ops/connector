import 'dart:ui';

import 'package:connector/connector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AlignmentSnapper', () {
    final others = [
      const Rect.fromLTWH(0, 0, 100, 50),
      const Rect.fromLTWH(300, 200, 120, 60),
    ];

    test('atrae el borde más cercano dentro de la tolerancia', () {
      final s = AlignmentSnapper(others);
      // Izquierda a 3 px de la del primer nodo; arriba a 4 px del segundo.
      final r = s.snap(const Rect.fromLTWH(3, 204, 80, 40), 6);
      expect(r.delta, const Offset(-3, -4));
      expect(r.guides.where((g) => g.vertical).map((g) => g.position),
          contains(0));
      expect(r.guides.where((g) => !g.vertical).map((g) => g.position),
          contains(200));
    });

    test('alinea centros', () {
      final s = AlignmentSnapper(others);
      // Centro x = 52 (el del primer nodo es 50).
      final r = s.snap(const Rect.fromLTWH(12, 500, 80, 40), 6);
      expect(r.delta.dx, -2);
      expect(r.delta.dy, 0);
      final g = r.guides.single;
      expect(g.vertical, isTrue);
      expect(g.position, 50);
      // La guía abarca desde el nodo de referencia hasta el que se mueve.
      expect(g.start, 0);
      expect(g.end, 540);
    });

    test('fuera de la tolerancia no hace nada', () {
      final s = AlignmentSnapper(others);
      final r = s.snap(const Rect.fromLTWH(140, 120, 80, 40), 6);
      expect(r.delta, Offset.zero);
      expect(r.guides, isEmpty);
    });

    test('sólo usa las líneas indicadas', () {
      final s = AlignmentSnapper(others);
      // El borde derecho (103) está a 3 px de 100, pero sólo se mueve el
      // inferior.
      final r = s.snap(const Rect.fromLTWH(23, 300, 80, 38), 6,
          lines: const AlignLines(
              left: false,
              centerX: false,
              right: false,
              top: false,
              centerY: false));
      expect(r.delta.dx, 0);
    });
  });

  group('punto de paso', () {
    const a = Offset(0, 0), b = Offset(400, 0);
    for (final curve in EdgeCurve.values) {
      test('${curve.name} pasa por el punto', () {
        const via = Offset(200, -50);
        final g = buildEdgeGeometry(curve, a, PortSide.right, b, PortSide.left,
            via: via);
        expect(g.distanceTo(via), lessThan(1.5));
        expect(g.polyline.first, a);
        expect(g.polyline.last, b);
        expect(g.labelPosition, via);
      });
    }

    test('ortogonal: un punto por encima de ambos extremos hace un puente', () {
      final g = buildEdgeGeometry(
          EdgeCurve.step, a, PortSide.right, b, PortSide.left,
          via: const Offset(600, -80));
      // El tramo horizontal superior queda a la altura del punto.
      expect(g.polyline.any((p) => p.dy == -80), isTrue);
      expect(g.bounds.top, -80);
    });
  });

  group('modelo', () {
    test('bend y linkBend se serializan', () {
      const e = EdgeData(
          id: 'e', sourceNodeId: 'a', targetNodeId: 'b', bend: Offset(3, -4));
      expect(EdgeData.fromJson(e.toJson()).bend, const Offset(3, -4));
      expect(e.copyWith(clearBend: true).bend, isNull);

      const n = NodeData<void>(
          id: 'n',
          position: Offset.zero,
          parentId: 'p',
          linkBend: Offset(1, 2));
      expect(NodeData.fromJson<void>(n.toJson()).linkBend, const Offset(1, 2));
      // No es contenido: moverlo no reconstruye el widget del nodo.
      expect(n.copyWith(clearLinkBend: true).sameContentAs(n), isTrue);
    });
  });

  group('controlador', () {
    NodeEditorController<void> make() => NodeEditorController<void>(nodes: [
          const NodeData(id: 'p', position: Offset(0, 0)),
          const NodeData(id: 'q', position: Offset(400, 0)),
          const NodeData(id: 'h', position: Offset(0, 300), parentId: 'p'),
          const NodeData(id: 'r', position: Offset(400, 300)),
        ], edges: const [
          EdgeData(id: 'e', sourceNodeId: 'p', targetNodeId: 'q'),
        ]);

    test('selección y borrado de enlaces de jerarquía', () {
      final c = make();
      c.selectLinks(['h', 'r']); // 'r' no tiene padre: se ignora
      expect(c.selectedLinkIds, {'h'});
      c.selectEdges(['e']);
      expect(c.selectedLinkIds, isEmpty);
      c.toggleLinkSelection('h');
      expect(c.selectedLinkIds, {'h'});
      expect(c.selectedEdgeIds, {'e'});
      c.deleteSelection();
      expect(c.node('h')!.parentId, isNull);
      expect(c.edge('e'), isNull);
      expect(c.selectedLinkIds, isEmpty);
      c.undo();
      expect(c.node('h')!.parentId, 'p');
      expect(c.edge('e'), isNotNull);
    });

    test('cambiar de padre quita el punto de paso del enlace', () {
      final c = make();
      c.setLinkBend('h', const Offset(10, 10));
      expect(c.node('h')!.linkBend, const Offset(10, 10));
      c.selectLinks(['h']);
      c.setParent('h', 'q');
      expect(c.node('h')!.linkBend, isNull);
      expect(c.selectedLinkIds, isEmpty);
    });

    test('moveLinkToChild pasa el enlace a otro nodo', () {
      final c = make();
      c.setLinkBend('h', const Offset(5, 5));
      expect(c.moveLinkToChild('h', 'r'), isTrue);
      expect(c.node('h')!.parentId, isNull);
      expect(c.node('r')!.parentId, 'p');
      expect(c.node('r')!.linkBend, const Offset(5, 5));
      // Sin ciclos: el padre no puede depender de sí mismo.
      expect(c.moveLinkToChild('r', 'p'), isFalse);
      c.undo();
      expect(c.node('h')!.parentId, 'p');
      expect(c.node('r')!.parentId, isNull);
    });

    test('setEdgeBend es deshacible', () {
      final c = make();
      c.setEdgeBend('e', const Offset(0, 40));
      expect(c.edge('e')!.bend, const Offset(0, 40));
      c.setEdgeBend('e', null);
      expect(c.edge('e')!.bend, isNull);
      c.undo();
      expect(c.edge('e')!.bend, const Offset(0, 40));
    });
  });
}
