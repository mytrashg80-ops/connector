import 'dart:ui';

import 'package:connector/connector.dart';
import 'package:flutter_test/flutter_test.dart';

NodeData<String> _n(String id,
        {Offset pos = Offset.zero,
        String? parent,
        List<NodePort> ports = const [
          NodePort.input(id: 'in', type: 'item'),
          NodePort.output(id: 'out', type: 'item'),
        ]}) =>
    NodeData<String>(
      id: id,
      position: pos,
      size: const Size(100, 60),
      title: id,
      parentId: parent,
      ports: ports,
    );

void main() {
  group('grafo', () {
    test('añadir, mover y eliminar nodos', () {
      final c = NodeEditorController<String>();
      c.addNodes([_n('a'), _n('b', pos: const Offset(300, 0))]);
      expect(c.nodeCount, 2);
      c.moveNodes(['a'], const Offset(10, 20));
      expect(c.node('a')!.position, const Offset(10, 20));
      c.removeNode('a');
      expect(c.node('a'), isNull);
      expect(c.nodeCount, 1);
    });

    test('ids duplicados lanzan error', () {
      final c = NodeEditorController<String>(nodes: [_n('a')]);
      expect(() => c.addNode(_n('a')), throwsArgumentError);
    });

    test('eliminar un nodo elimina sus conexiones', () {
      final c = NodeEditorController<String>(nodes: [_n('a'), _n('b')]);
      c.connect(
          sourceNodeId: 'a',
          sourcePortId: 'out',
          targetNodeId: 'b',
          targetPortId: 'in');
      expect(c.edgeCount, 1);
      c.removeNode('b');
      expect(c.edgeCount, 0);
      expect(c.edgesOf('a'), isEmpty);
    });
  });

  group('conexiones', () {
    late NodeEditorController<String> c;
    setUp(() => c = NodeEditorController<String>(nodes: [_n('a'), _n('b')]));

    test('salida → entrada es válida', () {
      final e = c.connect(
          sourceNodeId: 'a',
          sourcePortId: 'out',
          targetNodeId: 'b',
          targetPortId: 'in');
      expect(e, isNotNull);
      expect(c.connectedPorts('a'), {'out'});
    });

    test('rechaza entrada como origen, auto-conexión y duplicados', () {
      expect(
          c
              .checkConnection(
                  sourceNodeId: 'a',
                  sourcePortId: 'in',
                  targetNodeId: 'b',
                  targetPortId: 'in')
              .isValid,
          isFalse);
      expect(
          c
              .checkConnection(
                  sourceNodeId: 'a',
                  sourcePortId: 'out',
                  targetNodeId: 'a',
                  targetPortId: 'in')
              .isValid,
          isFalse);
      c.connect(
          sourceNodeId: 'a',
          sourcePortId: 'out',
          targetNodeId: 'b',
          targetPortId: 'in');
      expect(
          c.connect(
              sourceNodeId: 'a',
              sourcePortId: 'out',
              targetNodeId: 'b',
              targetPortId: 'in'),
          isNull);
    });

    test('tipos incompatibles y máximo de conexiones', () {
      c.addNode(_n('x', ports: const [
        NodePort.input(id: 'in', type: 'money', maxConnections: 1),
      ]));
      expect(
          c
              .checkConnection(
                  sourceNodeId: 'a',
                  sourcePortId: 'out',
                  targetNodeId: 'x',
                  targetPortId: 'in')
              .isValid,
          isFalse);
      c.addNode(_n('y', ports: const [
        NodePort.input(id: 'in', maxConnections: 1),
      ]));
      expect(
          c.connect(
              sourceNodeId: 'a',
              sourcePortId: 'out',
              targetNodeId: 'y',
              targetPortId: 'in'),
          isNotNull);
      expect(
          c
              .checkConnection(
                  sourceNodeId: 'b',
                  sourcePortId: 'out',
                  targetNodeId: 'y',
                  targetPortId: 'in')
              .reason,
          contains('lleno'));
    });

    test('validador personalizado', () {
      c.connectionValidator = (r) => r.target.id == 'b' ? 'prohibido' : null;
      final check = c.checkConnection(
          sourceNodeId: 'a',
          sourcePortId: 'out',
          targetNodeId: 'b',
          targetPortId: 'in');
      expect(check.reason, 'prohibido');
    });
  });

  group('jerarquía', () {
    test('padres, hijos, descendientes y ciclos', () {
      final c = NodeEditorController<String>(nodes: [
        _n('ceo'),
        _n('cto', parent: 'ceo'),
        _n('dev', parent: 'cto'),
        _n('cfo', parent: 'ceo'),
      ]);
      expect(c.childrenOf('ceo').map((n) => n.id), ['cto', 'cfo']);
      expect(c.descendantsOf('ceo').toSet(), {'cto', 'dev', 'cfo'});
      expect(c.ancestorsOf('dev'), ['cto', 'ceo']);
      expect(c.roots.map((n) => n.id), ['ceo']);
      expect(c.setParent('ceo', 'dev'), isFalse, reason: 'crearía un ciclo');
      expect(c.setParent('dev', 'cfo'), isTrue);
      expect(c.parentOf('dev')!.id, 'cfo');
    });

    test('colapsar oculta descendientes', () {
      final c = NodeEditorController<String>(nodes: [
        _n('a'),
        _n('b', parent: 'a'),
        _n('c', parent: 'b'),
      ]);
      c.setCollapsed('a', true);
      expect(c.isHidden('b'), isTrue);
      expect(c.isHidden('c'), isTrue);
      expect(c.isHidden('a'), isFalse);
      c.toggleCollapsed('a');
      expect(c.isHidden('c'), isFalse);
    });

    test('eliminar padre convierte a los hijos en raíces', () {
      final c =
          NodeEditorController<String>(nodes: [_n('a'), _n('b', parent: 'a')]);
      c.removeNode('a');
      expect(c.node('b')!.parentId, isNull);
    });

    test('mover con descendientes', () {
      final c = NodeEditorController<String>(nodes: [
        _n('a'),
        _n('b', parent: 'a', pos: const Offset(0, 100)),
      ]);
      c.moveNodes(['a'], const Offset(5, 5), includeDescendants: true);
      expect(c.node('b')!.position, const Offset(5, 105));
    });
  });

  group('historial', () {
    test('deshacer y rehacer', () {
      final c = NodeEditorController<String>();
      c.addNode(_n('a'));
      c.moveNodes(['a'], const Offset(10, 0));
      expect(c.canUndo, isTrue);
      c.undo();
      expect(c.node('a')!.position, Offset.zero);
      c.undo();
      expect(c.node('a'), isNull);
      c.redo();
      c.redo();
      expect(c.node('a')!.position, const Offset(10, 0));
    });

    test('una transacción es un solo paso', () {
      final c = NodeEditorController<String>(nodes: [_n('a'), _n('b')]);
      c.transaction(() {
        c.moveNodes(['a'], const Offset(1, 0));
        c.moveNodes(['a'], const Offset(1, 0));
        c.removeNode('b');
      });
      c.undo();
      expect(c.node('a')!.position, Offset.zero);
      expect(c.node('b'), isNotNull);
      expect(c.canUndo, isFalse);
    });

    test('deshacer borrado restaura conexiones', () {
      final c = NodeEditorController<String>(nodes: [_n('a'), _n('b')]);
      c.connect(
          sourceNodeId: 'a',
          sourcePortId: 'out',
          targetNodeId: 'b',
          targetPortId: 'in');
      c.removeNode('a');
      expect(c.edgeCount, 0);
      c.undo();
      expect(c.edgeCount, 1);
      expect(c.edgesOf('b').length, 1);
    });
  });

  group('selección y duplicado', () {
    test('duplicar copia conexiones internas', () {
      final c = NodeEditorController<String>(nodes: [_n('a'), _n('b')]);
      c.connect(
          sourceNodeId: 'a',
          sourcePortId: 'out',
          targetNodeId: 'b',
          targetPortId: 'in');
      final ids = c.duplicate(['a', 'b']);
      expect(ids.length, 2);
      expect(c.nodeCount, 4);
      expect(c.edgeCount, 2);
      expect(c.selectedNodeIds, ids.toSet());
    });

    test('deleteSelection respeta nodos bloqueados', () {
      final c = NodeEditorController<String>(nodes: [
        _n('a'),
        _n('b').copyWith(locked: true),
      ]);
      c.selectAll();
      c.deleteSelection();
      expect(c.node('a'), isNull);
      expect(c.node('b'), isNotNull);
    });
  });

  group('notificaciones de grano fino', () {
    test('mover sólo dispara geometry', () {
      final c = NodeEditorController<String>(nodes: [_n('a')]);
      var geometry = 0, structure = 0;
      c.geometry.addListener(() => geometry++);
      c.structure.addListener(() => structure++);
      c.moveNodes(['a'], const Offset(1, 1));
      expect(geometry, 1);
      expect(structure, 0);
      expect(c.contentVersionOf('a'), 0);
      c.updateNode('a', (n) => n.copyWith(title: 'nuevo'));
      expect(structure, 1);
      expect(c.contentVersionOf('a'), 1);
    });
  });

  group('serialización', () {
    test('ida y vuelta JSON', () {
      final c = NodeEditorController<String>(nodes: [
        _n('a').copyWith(data: 'payload'),
        _n('b', parent: 'a'),
      ]);
      c.connect(
          sourceNodeId: 'a',
          sourcePortId: 'out',
          targetNodeId: 'b',
          targetPortId: 'in',
          label: 'flujo');
      final json = c.toJson();
      final d = NodeEditorController<String>()..loadJson(json);
      expect(d.nodeCount, 2);
      expect(d.edgeCount, 1);
      expect(d.node('a')!.data, 'payload');
      expect(d.node('b')!.parentId, 'a');
      expect(d.edges.first.label, 'flujo');
      expect(d.node('a')!.ports.length, 2);
    });
  });

  group('índice espacial', () {
    test('consulta por área y punto', () {
      final idx = SpatialIndex(cellSize: 100);
      idx.insertOrUpdate('a', const Rect.fromLTWH(0, 0, 50, 50));
      idx.insertOrUpdate('b', const Rect.fromLTWH(1000, 1000, 50, 50));
      idx.insertOrUpdate('c', const Rect.fromLTWH(-500, -500, 50, 50));
      expect(idx.query(const Rect.fromLTWH(-10, -10, 100, 100)), {'a'});
      expect(idx.queryPoint(const Offset(1010, 1010)), {'b'});
      expect(idx.queryPoint(const Offset(-480, -480)), {'c'});
      idx.insertOrUpdate('a', const Rect.fromLTWH(990, 990, 50, 50));
      expect(idx.query(const Rect.fromLTWH(980, 980, 20, 20)), {'a'});
      idx.remove('b');
      expect(idx.query(const Rect.fromLTWH(980, 980, 200, 200)), {'a'});
    });

    test('nodeAt devuelve el nodo superior', () {
      final c = NodeEditorController<String>(nodes: [
        _n('a'),
        _n('b', pos: const Offset(20, 20)),
      ]);
      expect(c.nodeAt(const Offset(30, 30))!.id, 'b');
      c.bringToFront(['a']);
      expect(c.nodeAt(const Offset(30, 30))!.id, 'a');
    });
  });

  test('un grupo de historial notifica al momento y deshace de una vez', () {
    final c = NodeEditorController<void>(nodes: [
      const NodeData<void>(id: 'a', position: Offset.zero),
    ]);
    var fired = 0;
    c.geometry.addListener(() => fired++);
    c.beginHistoryGroup();
    c.moveNodes(['a'], const Offset(10, 0));
    expect(fired, 1);
    c.moveNodes(['a'], const Offset(10, 0));
    expect(fired, 2);
    c.undo(); // Bloqueado mientras el grupo está abierto.
    expect(c.node('a')!.position, const Offset(20, 0));
    c.endHistoryGroup();
    c.undo();
    expect(c.node('a')!.position, Offset.zero);
    expect(c.canUndo, isFalse);
  });

  test('reconnectEdge valida y mueve un extremo', () {
    final c = NodeEditorController<void>(nodes: [
      for (final id in ['a', 'b', 'c'])
        NodeData<void>(id: id, position: Offset.zero, ports: const [
          NodePort.input(id: 'in', maxConnections: 1),
          NodePort.output(id: 'out'),
        ]),
    ]);
    c.connect(
        sourceNodeId: 'a',
        sourcePortId: 'out',
        targetNodeId: 'b',
        targetPortId: 'in',
        id: 'e1');
    c.connect(
        sourceNodeId: 'b',
        sourcePortId: 'out',
        targetNodeId: 'c',
        targetPortId: 'in',
        id: 'e2');
    // c.in está lleno (maxConnections: 1).
    expect(c.reconnectEdge('e1', moveSource: false, nodeId: 'c', portId: 'in'),
        isNull);
    // Volver a su propio puerto no cuenta como duplicado ni como lleno.
    expect(c.reconnectEdge('e1', moveSource: false, nodeId: 'b', portId: 'in'),
        isNotNull);
    final moved =
        c.reconnectEdge('e2', moveSource: true, nodeId: 'a', portId: 'out');
    expect(moved!.sourceNodeId, 'a');
    expect(c.edgesOf('b').length, 1);
    final floating =
        c.reconnectEdge('e2', moveSource: true, nodeId: 'b', portId: null);
    expect(floating!.sourcePortId, isNull);
  });
}
