import 'package:connector/connector.dart';
import 'package:connector/src/widgets/scene_renderer.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

NodeData<void> _n(String id, Offset pos) => NodeData<void>(
      id: id,
      position: pos,
      size: const Size(160, 80),
      title: 'Nodo $id',
      ports: const [
        NodePort.input(id: 'in'),
        NodePort.output(id: 'out'),
      ],
    );

Widget _host(NodeEditorController<void> c,
    {NodeEditorTheme? theme, NodeEditorConfig? config}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 800,
        height: 600,
        child: NodeEditor<void>(
          controller: c,
          theme: theme,
          config: config ??
              const NodeEditorConfig(showMinimap: false, showControls: false),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('sólo construye nodos cercanos al viewport', (tester) async {
    final c = NodeEditorController<void>(nodes: [
      _n('cerca', const Offset(100, 100)),
      _n('lejos', const Offset(50000, 50000)),
    ]);
    await tester.pumpWidget(_host(c));
    expect(find.text('Nodo cerca'), findsOneWidget);
    expect(find.text('Nodo lejos'), findsNothing);

    c.centerOnNode('lejos');
    await tester.pump();
    expect(find.text('Nodo lejos'), findsOneWidget);
    expect(find.text('Nodo cerca'), findsNothing);
  });

  testWidgets('arrastrar un nodo lo mueve y es deshacible', (tester) async {
    final c =
        NodeEditorController<void>(nodes: [_n('a', const Offset(100, 100))]);
    await tester.pumpWidget(_host(c));
    final start = tester.getCenter(find.text('Nodo a'));
    final g = await tester.startGesture(start);
    await g.moveBy(const Offset(20, 0));
    await g.moveBy(const Offset(30, 40));
    await g.up();
    await tester.pump();
    expect(c.node('a')!.position, const Offset(150, 140));
    expect(c.isNodeSelected('a'), isTrue);
    c.undo();
    expect(c.node('a')!.position, const Offset(100, 100));
  });

  testWidgets('arrastrar el fondo desplaza la cámara', (tester) async {
    final c =
        NodeEditorController<void>(nodes: [_n('a', const Offset(100, 100))]);
    await tester.pumpWidget(_host(c));
    await tester.dragFrom(const Offset(600, 500), const Offset(-100, -50));
    await tester.pump();
    expect(c.viewport.offset.dx, lessThan(0));
    expect(c.viewport.offset.dy, lessThan(0));
    expect(c.node('a')!.position, const Offset(100, 100));
  });

  testWidgets('arrastrar de un puerto a otro crea una conexión',
      (tester) async {
    final c = NodeEditorController<void>(nodes: [
      _n('a', const Offset(50, 100)),
      _n('b', const Offset(400, 100)),
    ]);
    EdgeData? created;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 600,
          child: NodeEditor<void>(
            controller: c,
            config:
                const NodeEditorConfig(showMinimap: false, showControls: false),
            onConnect: (e) => created = e,
          ),
        ),
      ),
    ));
    final editorOrigin = tester.getTopLeft(find.byType(NodeEditor<void>));
    final theme = NodeEditorTheme.light();
    Offset portPos(String node, String port) {
      final n = c.node(node)!;
      return editorOrigin +
          c.viewport.toScreen(n.position +
              NodeGeometry.portLocalPosition(n, n.size, port,
                  topInset: theme.nodeHeaderHeight));
    }

    final g = await tester.startGesture(portPos('a', 'out'));
    await g.moveBy(const Offset(40, 0));
    await g.moveTo(portPos('b', 'in'));
    await g.up();
    await tester.pump();
    expect(c.edgeCount, 1);
    expect(created, isNotNull);
    expect(created!.sourceNodeId, 'a');
    expect(created!.targetPortId, 'in');
  });

  testWidgets('modo LOD no construye widgets de nodos', (tester) async {
    final c =
        NodeEditorController<void>(nodes: [_n('a', const Offset(100, 100))]);
    await tester.pumpWidget(_host(c));
    expect(find.text('Nodo a'), findsOneWidget);
    c.viewport.setView(scale: 0.2);
    await tester.pump();
    expect(find.text('Nodo a'), findsNothing);
    c.viewport.setView(scale: 1);
    await tester.pump();
    expect(find.text('Nodo a'), findsOneWidget);
  });

  testWidgets('cambia entre tema claro y oscuro', (tester) async {
    final c =
        NodeEditorController<void>(nodes: [_n('a', const Offset(100, 100))]);
    await tester.pumpWidget(_host(c, theme: NodeEditorTheme.light()));
    await tester.pumpWidget(_host(c, theme: NodeEditorTheme.dark()));
    await tester.pump();
    expect(tester.takeException(), isNull);
    final box = tester.widget<ColoredBox>(find
        .descendant(
            of: find.byType(NodeEditor<void>),
            matching: find.byType(ColoredBox))
        .first);
    expect(box.color, NodeEditorTheme.dark().backgroundColor);
  });

  testWidgets('minimapa y controles se renderizan', (tester) async {
    final c = NodeEditorController<void>(nodes: [
      for (var i = 0; i < 50; i++)
        _n('n$i', Offset(i * 200.0, (i % 5) * 150.0)),
    ]);
    await tester.pumpWidget(_host(c, config: const NodeEditorConfig()));
    expect(find.byType(NodeEditorMinimap<void>), findsOneWidget);
    await tester.tap(find.byTooltip('Ajustar vista'));
    await tester.pump();
    expect(c.viewport.scale, lessThan(1));
  });

  testWidgets('5000 nodos: sólo se construyen los visibles', (tester) async {
    final c = NodeEditorController<void>(nodes: [
      for (var i = 0; i < 5000; i++)
        _n('n$i', Offset((i % 100) * 220.0, (i ~/ 100) * 120.0)),
    ]);
    for (var i = 1; i < 5000; i++) {
      c.addEdge(
          EdgeData(id: 'e$i', sourceNodeId: 'n${i - 1}', targetNodeId: 'n$i'));
    }
    await tester.pumpWidget(_host(c));
    final built = find.byType(NodeFrame).evaluate().length;
    expect(built, greaterThan(0));
    expect(built, lessThan(150));

    // Desplazarse no reconstruye nodos mientras no se salga de la región.
    for (var i = 0; i < 60; i++) {
      c.viewport.panBy(const Offset(-15, -5));
      await tester.pump();
    }
    expect(find.byType(NodeFrame).evaluate().length, lessThan(150));

    // Vista general: nivel de detalle sin widgets de nodos.
    c.fitView();
    await tester.pump();
    expect(find.byType(NodeFrame), findsNothing);
  });

  testWidgets('el nodo se mueve en tiempo real mientras se arrastra',
      (tester) async {
    final c =
        NodeEditorController<void>(nodes: [_n('a', const Offset(100, 100))]);
    await tester.pumpWidget(_host(c));
    final start = tester.getCenter(find.text('Nodo a'));
    final g = await tester.startGesture(start);
    await g.moveBy(const Offset(20, 0));
    await g.moveBy(const Offset(60, 30));
    await tester.pump();
    // Aún sin soltar: el modelo y el widget ya están en la nueva posición.
    expect(c.node('a')!.position, const Offset(180, 130));
    expect(tester.getCenter(find.text('Nodo a')), start + const Offset(80, 30));
    await g.up();
    await tester.pump();
    c.undo();
    expect(c.node('a')!.position, const Offset(100, 100));
  });

  testWidgets('arrastrar el borde de un nodo lo redimensiona', (tester) async {
    final c =
        NodeEditorController<void>(nodes: [_n('a', const Offset(100, 100))]);
    Rect? resized;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 600,
          child: NodeEditor<void>(
            controller: c,
            config:
                const NodeEditorConfig(showMinimap: false, showControls: false),
            onNodeResized: (id, r) => resized = r,
          ),
        ),
      ),
    ));
    final origin = tester.getTopLeft(find.byType(NodeEditor<void>));
    // Esquina inferior derecha (260, 180), un poco hacia dentro.
    final g = await tester.startGesture(origin + const Offset(258, 178),
        kind: PointerDeviceKind.mouse);
    await g.moveBy(const Offset(20, 0));
    await g.moveBy(const Offset(20, 30));
    await tester.pump();
    expect(c.node('a')!.size, const Size(200, 110));
    expect(c.node('a')!.position, const Offset(100, 100));
    await g.up();
    await tester.pump();
    expect(resized, const Rect.fromLTWH(100, 100, 200, 110));

    // Borde izquierdo: mueve la posición y respeta el tamaño mínimo.
    final g2 = await tester.startGesture(origin + const Offset(101, 150),
        kind: PointerDeviceKind.mouse);
    await g2.moveBy(const Offset(20, 0));
    await g2.moveBy(const Offset(500, 0));
    await g2.up();
    await tester.pump();
    const min = NodeEditorConfig();
    expect(c.node('a')!.size.width, min.minNodeSize.width);
    expect(c.rectOf('a').right, 300);

    c.undo();
    c.undo();
    expect(c.node('a')!.size, const Size(160, 80));
  });

  group('editar conexiones', () {
    late NodeEditorController<void> c;
    late Offset origin;
    EdgeData? reconnected;
    EdgeData? disconnected;
    final theme = NodeEditorTheme.light();

    Offset portPos(String node, String port) {
      final n = c.node(node)!;
      return origin +
          c.viewport.toScreen(n.position +
              NodeGeometry.portLocalPosition(n, n.size, port,
                  topInset: theme.nodeHeaderHeight));
    }

    Future<void> setUpEditor(WidgetTester tester) async {
      reconnected = null;
      disconnected = null;
      c = NodeEditorController<void>(nodes: [
        _n('a', const Offset(20, 100)),
        _n('b', const Offset(320, 40)),
        _n('c', const Offset(320, 300)),
      ]);
      c.connect(
          sourceNodeId: 'a',
          sourcePortId: 'out',
          targetNodeId: 'b',
          targetPortId: 'in',
          id: 'e1');
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: NodeEditor<void>(
              controller: c,
              theme: theme,
              config: const NodeEditorConfig(
                  showMinimap: false, showControls: false),
              onEdgeReconnected: (_, after) => reconnected = after,
              onEdgeDisconnected: (e) => disconnected = e,
            ),
          ),
        ),
      ));
      origin = tester.getTopLeft(find.byType(NodeEditor<void>));
    }

    testWidgets('arrastrar el extremo de una conexión la reconecta',
        (tester) async {
      await setUpEditor(tester);
      c.selectEdges(['e1']);
      await tester.pump();
      final g = await tester.startGesture(portPos('b', 'in'));
      await g.moveBy(const Offset(-30, 20));
      await g.moveTo(portPos('c', 'in'));
      await g.up();
      await tester.pump();
      expect(c.edgeCount, 1);
      expect(c.edge('e1')!.sourceNodeId, 'a');
      expect(c.edge('e1')!.targetNodeId, 'c');
      expect(reconnected?.targetNodeId, 'c');
      c.undo();
      expect(c.edge('e1')!.targetNodeId, 'b');
    });

    testWidgets('arrastrar desde una entrada conectada mueve su conexión',
        (tester) async {
      await setUpEditor(tester);
      final g = await tester.startGesture(portPos('b', 'in'));
      await g.moveBy(const Offset(-30, 20));
      await g.moveTo(origin + const Offset(500, 560));
      await g.up();
      await tester.pump();
      expect(c.edgeCount, 0);
      expect(disconnected?.id, 'e1');
    });

    testWidgets('soltar el extremo en el vacío desconecta', (tester) async {
      await setUpEditor(tester);
      c.selectEdges(['e1']);
      await tester.pump();
      final g = await tester.startGesture(portPos('a', 'out'));
      await g.moveBy(const Offset(30, 30));
      await g.moveTo(origin + const Offset(150, 520));
      await g.up();
      await tester.pump();
      expect(c.edgeCount, 0);
      expect(disconnected?.id, 'e1');
      c.undo();
      expect(c.edge('e1'), isNotNull);
    });

    testWidgets('Ctrl + arrastrar desde un puerto recoge su conexión',
        (tester) async {
      await setUpEditor(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      final g = await tester.startGesture(portPos('b', 'in'));
      await g.moveBy(const Offset(-30, 20));
      await g.moveTo(portPos('c', 'in'));
      await g.up();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(c.edge('e1')!.targetNodeId, 'c');
    });

    testWidgets('el botón de borrar elimina la conexión seleccionada',
        (tester) async {
      await setUpEditor(tester);
      c.selectEdges(['e1']);
      await tester.pump();
      final renderer = SceneRenderer<void>(c)..theme = theme;
      final geo = renderer.geometryOf(c.edge('e1')!)!;
      await tester.tapAt(origin + c.viewport.toScreen(geo.labelPosition));
      await tester.pump();
      expect(c.edgeCount, 0);
    });
  });
}
