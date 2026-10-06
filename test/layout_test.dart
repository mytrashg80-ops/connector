import 'dart:ui';

import 'package:connector/connector.dart';
import 'package:flutter_test/flutter_test.dart';

NodeData<void> _n(String id, {String? parent}) => NodeData<void>(
      id: id,
      position: Offset.zero,
      size: const Size(100, 50),
      parentId: parent,
    );

bool _overlaps(NodeEditorController<void> c) {
  final rects = [for (final n in c.nodes) c.rectOf(n.id)];
  for (var i = 0; i < rects.length; i++) {
    for (var j = i + 1; j < rects.length; j++) {
      if (rects[i].deflate(0.5).overlaps(rects[j].deflate(0.5))) return true;
    }
  }
  return false;
}

void main() {
  NodeEditorController<void> org() => NodeEditorController<void>(nodes: [
        _n('ceo'),
        _n('cto', parent: 'ceo'),
        _n('cfo', parent: 'ceo'),
        _n('dev1', parent: 'cto'),
        _n('dev2', parent: 'cto'),
        _n('acc', parent: 'cfo'),
      ]);

  test('TreeLayout: padre encima y centrado sobre sus hijos', () async {
    final c = org();
    await c.applyLayout(const TreeLayout());
    expect(_overlaps(c), isFalse);
    final ceo = c.rectOf('ceo'), cto = c.rectOf('cto'), cfo = c.rectOf('cfo');
    expect(cto.top, greaterThan(ceo.bottom));
    expect(ceo.center.dx, closeTo((cto.center.dx + cfo.center.dx) / 2, 0.01));
    expect(c.rectOf('dev1').top, greaterThan(cto.bottom));
  });

  test('TreeLayout horizontal', () async {
    final c = org();
    await c
        .applyLayout(const TreeLayout(direction: LayoutDirection.leftToRight));
    expect(_overlaps(c), isFalse);
    expect(c.rectOf('cto').left, greaterThan(c.rectOf('ceo').right));
  });

  test('LayeredLayout ordena cadenas y tolera ciclos', () async {
    final c =
        NodeEditorController<void>(nodes: [_n('a'), _n('b'), _n('c'), _n('d')]);
    c.addEdges(const [
      EdgeData(id: '1', sourceNodeId: 'a', targetNodeId: 'b'),
      EdgeData(id: '2', sourceNodeId: 'b', targetNodeId: 'c'),
      EdgeData(id: '3', sourceNodeId: 'c', targetNodeId: 'a'),
      EdgeData(id: '4', sourceNodeId: 'a', targetNodeId: 'd'),
    ]);
    await c.applyLayout(const LayeredLayout());
    expect(_overlaps(c), isFalse);
    expect(c.rectOf('b').left, greaterThan(c.rectOf('a').right));
    expect(c.rectOf('c').left, greaterThan(c.rectOf('b').right));
  });

  test('RadialLayout y MindMapLayout no solapan', () async {
    for (final layout in const <GraphLayout>[RadialLayout(), MindMapLayout()]) {
      final c = org();
      await c.applyLayout(layout);
      expect(_overlaps(c), isFalse, reason: layout.runtimeType.toString());
    }
  });

  test('applyLayout es un único paso de deshacer', () async {
    final c = org();
    await c.applyLayout(const GridLayout());
    expect(_overlaps(c), isFalse);
    c.undo();
    expect(c.nodes.every((n) => n.position == Offset.zero), isTrue);
  });
}
