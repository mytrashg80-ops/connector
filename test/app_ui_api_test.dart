import 'package:connector/connector.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

NodeData<void> _n(String id, Offset pos, {String? parent}) => NodeData<void>(
      id: id,
      position: pos,
      size: const Size(160, 80),
      title: 'Nodo $id',
      parentId: parent,
    );

List<EditorCommand> _commands(List<EditorAction> actions) =>
    [for (final a in actions) a.command];

void main() {
  group('acciones', () {
    test('un nodo ofrece sólo lo que tiene sentido y lo ejecuta', () {
      final c = NodeEditorController<void>(nodes: [
        _n('p', Offset.zero),
        _n('h', const Offset(0, 200), parent: 'p'),
      ]);
      final leaf = _commands(c.actionsFor(NodeTarget(c.node('h')!)));
      expect(leaf, contains(EditorCommand.detachFromParent));
      expect(leaf, isNot(contains(EditorCommand.collapse)));
      expect(leaf, isNot(contains(EditorCommand.deleteWithDescendants)));

      final parent = c.actionsFor(NodeTarget(c.node('p')!));
      expect(_commands(parent), contains(EditorCommand.collapse));
      expect(
          _commands(parent), isNot(contains(EditorCommand.detachFromParent)));

      c.actionFor(NodeTarget(c.node('p')!), EditorCommand.collapse)!();
      expect(c.node('p')!.collapsed, isTrue);
      expect(_commands(c.actionsFor(NodeTarget(c.node('p')!))),
          contains(EditorCommand.expand));

      final del = c.actionFor(
          NodeTarget(c.node('p')!), EditorCommand.deleteWithDescendants)!;
      expect(del.destructive, isTrue);
      del();
      expect(c.nodeCount, 0);
      c.undo();
      expect(c.nodeCount, 2);
    });

    test('con el editor bloqueado sólo se habilitan las que no editan', () {
      final c = NodeEditorController<void>(nodes: [_n('a', Offset.zero)]);
      c.locked.value = true;
      final actions = c.actionsFor(NodeTarget(c.node('a')!));
      for (final a in actions) {
        final editsNothing = a.command == EditorCommand.focus ||
            a.command == EditorCommand.bringToFront;
        expect(a.enabled, editsNothing, reason: a.command.name);
      }
      c.actionFor(NodeTarget(c.node('a')!), EditorCommand.delete)!();
      expect(c.nodeCount, 1);
    });

    test('la selección múltiple actúa sobre todos en un paso', () {
      final c = NodeEditorController<void>(nodes: [
        _n('a', Offset.zero),
        _n('b', const Offset(300, 0)),
        _n('x', const Offset(600, 0)),
      ]);
      expect(c.targetForNode(c.node('a')!), isA<NodeTarget<void>>());
      c.selectNodes(['a', 'b']);
      final t = c.targetForNode(c.node('a')!);
      expect(t, isA<SelectionTarget<void>>());
      expect((t as SelectionTarget).nodeIds, ['a', 'b']);
      expect(c.targetForNode(c.node('x')!), isA<NodeTarget<void>>());

      c.actionFor(t, EditorCommand.lock)!();
      expect(c.node('a')!.locked && c.node('b')!.locked, isTrue);
      expect(_commands(c.actionsFor(t)), contains(EditorCommand.unlock));
      c.undo();
      expect(c.node('a')!.locked || c.node('b')!.locked, isFalse);
    });

    test('conexiones: curva actual, invertir y animar', () {
      final c = NodeEditorController<void>(
        nodes: [_n('a', Offset.zero), _n('b', const Offset(300, 0))],
        edges: [
          const EdgeData(
              id: 'e',
              sourceNodeId: 'a',
              targetNodeId: 'b',
              curve: EdgeCurve.step),
        ],
      );
      final t = EdgeTarget<void>(c.edge('e')!);
      final curves = c
          .actionsFor(t)
          .where((a) => a.command == EditorCommand.setEdgeCurve)
          .toList();
      expect(curves.map((a) => a.value), EdgeCurve.values);
      expect(curves.singleWhere((a) => a.selected).value, EdgeCurve.step);

      c.actionFor(t, EditorCommand.setEdgeCurve, value: EdgeCurve.straight)!();
      expect(c.edge('e')!.curve, EdgeCurve.straight);
      c.actionFor(t, EditorCommand.reverseEdge)!();
      expect(c.edge('e')!.sourceNodeId, 'b');
      expect(c.edge('e')!.targetNodeId, 'a');
      c.actionFor(t, EditorCommand.toggleEdgeAnimation)!();
      expect(c.edge('e')!.animated, isTrue);
      expect(
          c.actionFor(t, EditorCommand.toggleEdgeAnimation)!.selected, isTrue);
      c.actionFor(t, EditorCommand.deleteEdge)!();
      expect(c.edgeCount, 0);
    });

    test('enlaces y lienzo', () {
      final c = NodeEditorController<void>(nodes: [
        _n('p', Offset.zero),
        _n('h', const Offset(0, 200), parent: 'p'),
      ]);
      final link = LinkTarget<void>(c.node('h')!, c.node('p'));
      expect(_commands(c.actionsFor(link)), [EditorCommand.unlink]);
      c.actionFor(link, EditorCommand.unlink)!();
      expect(c.node('h')!.parentId, isNull);

      final canvas = c.actionsFor(const CanvasTarget<void>(Offset.zero));
      final undo = canvas.singleWhere((a) => a.command == EditorCommand.undo);
      final redo = canvas.singleWhere((a) => a.command == EditorCommand.redo);
      expect(undo.enabled, isTrue);
      expect(redo.enabled, isFalse);
      undo();
      expect(c.node('h')!.parentId, 'p');
    });
  });

  group('estilo', () {
    test('setNodeStyle cambia varios nodos en un paso y conserva el centro',
        () {
      final c = NodeEditorController<void>(nodes: [
        _n('a', Offset.zero),
        _n('b', const Offset(300, 0)),
      ]);
      final center = c.rectOf('a').center;
      c.setNodeStyle(
        ['a', 'b'],
        const NodeStyle(shape: NodeShape.circle, icon: 'flag'),
        color: Colors.red,
        resize: (n) => NodeShapes.suggestedSize(NodeShape.circle, n.size,
            from: NodeShape.card),
      );
      expect(c.node('a')!.style!.shape, NodeShape.circle);
      expect(c.node('b')!.color, Colors.red);
      expect(c.node('a')!.size, const Size(88, 112));
      expect(c.rectOf('a').center, center);

      c.resetNodeStyle(['a']);
      expect(c.node('a')!.style, isNull);
      expect(c.node('a')!.color, isNull);
      c.undo();
      c.undo();
      expect(c.node('a')!.style, isNull);
      expect(c.node('b')!.style, isNull);
      expect(c.node('a')!.size, const Size(160, 80));
    });

    test('suggestedSize', () {
      const s = Size(160, 80);
      expect(
          NodeShapes.suggestedSize(NodeShape.card, s, from: NodeShape.card), s);
      expect(NodeShapes.suggestedSize(NodeShape.pill, s).height, 44);
      final d = NodeShapes.suggestedSize(NodeShape.diamond, s);
      expect(d.width >= 170 && d.height >= 110, isTrue);
      expect(
          NodeShapes.suggestedSize(NodeShape.box, const Size(88, 112),
              from: NodeShape.circle),
          const Size(180, 72));
    });
  });

  group('widget', () {
    late NodeEditorController<void> c;
    final menus = <EditorContextMenuDetails<void>>[];

    Future<void> pump(WidgetTester tester,
        {NodeEditorConfig config = const NodeEditorConfig(),
        SelectionOverlayBuilder<void>? toolbar}) async {
      menus.clear();
      c = NodeEditorController<void>(nodes: [
        _n('a', const Offset(100, 200)),
        _n('b', const Offset(400, 200)),
      ], edges: [
        const EdgeData(id: 'e', sourceNodeId: 'a', targetNodeId: 'b'),
      ]);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: NodeEditor<void>(
              controller: c,
              config: config,
              onContextMenu: menus.add,
              selectionOverlayBuilder: toolbar,
            ),
          ),
        ),
      ));
    }

    Offset screen(WidgetTester tester, Offset world) =>
        tester.getTopLeft(find.byType(NodeEditor<void>)) +
        c.viewport.toScreen(world);

    testWidgets('no añade ninguna interfaz propia', (tester) async {
      await pump(tester);
      expect(find.byType(NodeEditorMinimap<void>), findsNothing);
      expect(find.byType(Tooltip), findsNothing);
    });

    testWidgets('el clic derecho entrega el destino y las acciones',
        (tester) async {
      await pump(tester);
      await tester.tapAt(screen(tester, c.rectOf('a').center),
          buttons: kSecondaryButton, kind: PointerDeviceKind.mouse);
      await tester.pump();
      expect(menus, hasLength(1));
      final t = menus.single.target as NodeTarget<void>;
      expect(t.node.id, 'a');
      expect(c.isNodeSelected('a'), isTrue);
      expect(_commands(menus.single.actions), contains(EditorCommand.delete));

      const empty = Offset(300, 520);
      await tester.tapAt(screen(tester, empty),
          buttons: kSecondaryButton, kind: PointerDeviceKind.mouse);
      await tester.pump();
      final canvas = menus.last.target as CanvasTarget<void>;
      expect((canvas.worldPosition - empty).distance, lessThan(0.01));
      expect((menus.last.worldPosition - empty).distance, lessThan(0.01));
    });

    testWidgets('la barra de la selección la construye la app y sigue al nodo',
        (tester) async {
      EditorSelectionDetails<void>? last;
      await pump(tester, toolbar: (context, d) {
        last = d;
        return const SizedBox(key: Key('barra'), width: 120, height: 32);
      });
      expect(find.byKey(const Key('barra')), findsNothing);

      c.selectNode('a');
      await tester.pump();
      final bar = find.byKey(const Key('barra'));
      expect(bar, findsOneWidget);
      expect(last!.target, isA<NodeTarget<void>>());
      final node = c.viewport.toScreen(c.rectOf('a').topCenter);
      final origin = tester.getTopLeft(find.byType(NodeEditor<void>));
      expect(tester.getBottomLeft(bar).dy - origin.dy, lessThan(node.dy));
      expect(
          (tester.getCenter(bar).dx - origin.dx - node.dx).abs(), lessThan(1));

      // Se oculta durante el arrastre y vuelve al soltar.
      final g = await tester.startGesture(screen(tester, c.rectOf('a').center),
          kind: PointerDeviceKind.mouse);
      await g.moveBy(const Offset(30, 0));
      await g.moveBy(const Offset(30, 0));
      await tester.pump();
      expect(bar, findsNothing);
      await g.up();
      await tester.pump();
      expect(bar, findsOneWidget);

      c.selectEdges(['e']);
      await tester.pump();
      expect(last!.target, isA<EdgeTarget<void>>());
      expect(_commands(last!.actions), contains(EditorCommand.deleteEdge));

      c.clearSelection();
      await tester.pump();
      expect(bar, findsNothing);
    });

    testWidgets('al mover la cámara la barra se recoloca sin reconstruirse',
        (tester) async {
      var builds = 0;
      await pump(tester, toolbar: (context, d) {
        builds++;
        return const SizedBox(key: Key('barra'), width: 120, height: 32);
      });
      c.selectNode('a');
      await tester.pump();
      final bar = find.byKey(const Key('barra'));
      final before = tester.getTopLeft(bar);
      final count = builds;
      c.viewport.panBy(const Offset(40, 30));
      await tester.pump();
      expect(builds, count);
      expect(tester.getTopLeft(bar) - before, const Offset(40, 30));
    });

    testWidgets('NodePreview pinta el nodo fuera del editor', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Center(
          child: SizedBox(
            width: 200,
            height: 120,
            child: NodePreview<void>(
              node: _n('a', Offset.zero)
                  .copyWith(style: const NodeStyle(shape: NodeShape.pill)),
            ),
          ),
        ),
      ));
      expect(find.text('Nodo a'), findsOneWidget);
      expect(find.byType(DefaultNodeBody), findsOneWidget);
    });
  });
}
