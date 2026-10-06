import 'package:connector/connector.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

NodeData<void> _n(String id, Offset pos,
        {String? parent, List<NodePort> ports = const []}) =>
    NodeData<void>(
      id: id,
      position: pos,
      size: const Size(160, 80),
      title: 'Nodo $id',
      parentId: parent,
      ports: ports,
    );

class _Log {
  final parents = <(String, String?)>[];
  final rejected = <String>[];
  final dropped = <ConnectionDropDetails<void>>[];
  final connected = <EdgeData>[];
}

Widget _host(NodeEditorController<void> c, _Log log,
    {ConnectorStyle style = const ConnectorStyle(), bool handles = true}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 800,
        height: 600,
        child: NodeEditor<void>(
          controller: c,
          config: NodeEditorConfig(
            showMinimap: false,
            showControls: false,
            animations: NodeEditorAnimations.none,
            newConnector: style,
            connectorHandles: handles,
          ),
          onParentChanged: (child, parent) => log.parents.add((child, parent)),
          onConnectionRejected: log.rejected.add,
          onConnectionDropped: log.dropped.add,
          onConnect: log.connected.add,
        ),
      ),
    ),
  );
}

/// Pasa el ratón por el nodo (para que muestre sus tiradores) y arrastra
/// desde su tirador inferior hasta [to].
Future<void> _dragFromBottomHandle(
    WidgetTester tester, Offset nodeCenter, double nodeBottom, Offset to,
    {PointerDeviceKind kind = PointerDeviceKind.mouse}) async {
  final origin = tester.getTopLeft(find.byType(NodeEditor<void>));
  final handle = Offset(nodeCenter.dx, nodeBottom + 13);
  final g = await tester.createGesture(kind: kind);
  if (kind == PointerDeviceKind.mouse) {
    await g.addPointer(location: origin + nodeCenter);
    await g.moveTo(origin + nodeCenter);
    await tester.pump();
    await g.moveTo(origin + handle);
    await tester.pump();
  }
  await g.down(origin + handle);
  await g.moveTo(origin + handle + const Offset(0, 30));
  await g.moveTo(origin + to);
  await tester.pump();
  await g.up();
  await tester.pump();
}

void main() {
  testWidgets('el "+" crea un enlace de jerarquía padre → hijo',
      (tester) async {
    final c = NodeEditorController<void>(nodes: [
      _n('a', const Offset(100, 100)),
      _n('b', const Offset(100, 400)),
    ]);
    final log = _Log();
    await tester.pumpWidget(_host(c, log, style: ConnectorStyle.hierarchy));
    await _dragFromBottomHandle(
        tester, const Offset(180, 140), 180, const Offset(180, 440));
    expect(c.node('b')!.parentId, 'a');
    expect(log.parents, [('b', 'a')]);
    expect(c.edgeCount, 0);
    // Un solo paso de deshacer.
    c.undo();
    expect(c.node('b')!.parentId, isNull);
  });

  testWidgets('recrear un enlace borrado', (tester) async {
    final c = NodeEditorController<void>(nodes: [
      _n('a', const Offset(100, 100)),
      _n('b', const Offset(100, 400), parent: 'a'),
    ]);
    final log = _Log();
    await tester.pumpWidget(_host(c, log, style: ConnectorStyle.hierarchy));
    c.setParent('b', null);
    await tester.pump();
    await _dragFromBottomHandle(
        tester, const Offset(180, 140), 180, const Offset(180, 440));
    expect(c.node('b')!.parentId, 'a');
  });

  testWidgets('la jerarquía rechaza ciclos', (tester) async {
    final c = NodeEditorController<void>(nodes: [
      _n('a', const Offset(100, 100)),
      _n('b', const Offset(100, 400), parent: 'a'),
    ]);
    final log = _Log();
    await tester.pumpWidget(_host(c, log, style: ConnectorStyle.hierarchy));
    // Desde b (hijo) hasta a (su padre): a no puede colgar de b.
    await _dragFromBottomHandle(
        tester, const Offset(180, 440), 480, const Offset(180, 140));
    expect(c.node('a')!.parentId, isNull);
    expect(log.rejected, ['Crearía un ciclo en la jerarquía']);
  });

  testWidgets('el "+" crea conexiones con el estilo elegido, sin puertos',
      (tester) async {
    final c = NodeEditorController<void>(nodes: [
      _n('a', const Offset(100, 100)),
      _n('b', const Offset(100, 400)),
    ]);
    final log = _Log();
    await tester.pumpWidget(_host(c, log,
        style: const ConnectorStyle(
            curve: EdgeCurve.straight, dashed: true, arrow: true)));
    await _dragFromBottomHandle(
        tester, const Offset(180, 140), 180, const Offset(180, 440));
    expect(c.edgeCount, 1);
    final e = c.edges.single;
    expect((e.sourceNodeId, e.targetNodeId), ('a', 'b'));
    expect(e.sourcePortId, isNull);
    expect(e.curve, EdgeCurve.straight);
    expect(e.dashed, isTrue);
    expect(e.arrow, isTrue);
    expect(log.connected, [e]);
    expect(c.node('b')!.parentId, isNull);
  });

  testWidgets('desde el "+" también se llega a un puerto', (tester) async {
    final c = NodeEditorController<void>(nodes: [
      _n('a', const Offset(100, 100)),
      _n('b', const Offset(100, 400),
          ports: const [NodePort.input(id: 'in', side: PortSide.top)]),
    ]);
    final log = _Log();
    await tester.pumpWidget(_host(c, log));
    await _dragFromBottomHandle(
        tester, const Offset(180, 140), 180, const Offset(180, 400));
    expect(c.edges.single.targetPortId, 'in');
  });

  testWidgets('soltar en el vacío avisa con el tipo de conector',
      (tester) async {
    final c = NodeEditorController<void>(nodes: [
      _n('a', const Offset(100, 100)),
    ]);
    final log = _Log();
    await tester.pumpWidget(_host(c, log, style: ConnectorStyle.hierarchy));
    await _dragFromBottomHandle(
        tester, const Offset(180, 140), 180, const Offset(500, 450));
    expect(log.dropped, hasLength(1));
    expect(log.dropped.single.node.id, 'a');
    expect(log.dropped.single.style.isHierarchy, isTrue);
    expect(log.dropped.single.worldPosition, const Offset(500, 450));
  });

  testWidgets('en táctil, el nodo seleccionado muestra sus tiradores',
      (tester) async {
    final c = NodeEditorController<void>(nodes: [
      _n('a', const Offset(100, 100)),
      _n('b', const Offset(100, 400)),
    ]);
    final log = _Log();
    await tester.pumpWidget(_host(c, log, style: ConnectorStyle.hierarchy));
    c.selectNode('a');
    await tester.pump();
    await _dragFromBottomHandle(
        tester, const Offset(180, 140), 180, const Offset(180, 440),
        kind: PointerDeviceKind.touch);
    expect(c.node('b')!.parentId, 'a');
  });

  testWidgets('connectorHandles: false no muestra tiradores', (tester) async {
    final c = NodeEditorController<void>(nodes: [
      _n('a', const Offset(100, 100)),
      _n('b', const Offset(100, 400)),
    ]);
    final log = _Log();
    await tester.pumpWidget(
        _host(c, log, style: ConnectorStyle.hierarchy, handles: false));
    await _dragFromBottomHandle(
        tester, const Offset(180, 140), 180, const Offset(180, 440));
    expect(c.node('b')!.parentId, isNull);
    expect(c.edgeCount, 0);
  });

  testWidgets('las conexiones desde puertos usan el estilo elegido',
      (tester) async {
    final c = NodeEditorController<void>(nodes: [
      _n('a', const Offset(100, 100),
          ports: const [NodePort.output(id: 'out')]),
      _n('b', const Offset(400, 100), ports: const [NodePort.input(id: 'in')]),
    ]);
    final log = _Log();
    await tester.pumpWidget(_host(c, log,
        style: const ConnectorStyle(curve: EdgeCurve.step, animated: true)));
    final origin = tester.getTopLeft(find.byType(NodeEditor<void>));
    final theme = NodeEditorTheme.light();
    Offset portPos(String node, String port) {
      final n = c.node(node)!;
      return origin +
          n.position +
          NodeGeometry.portLocalPosition(n, n.size, port,
              topInset: theme.nodeHeaderHeight);
    }

    final g = await tester.startGesture(portPos('a', 'out'));
    await g.moveBy(const Offset(40, 0));
    await g.moveTo(portPos('b', 'in'));
    await g.up();
    await tester.pump();
    final e = c.edges.single;
    expect(e.curve, EdgeCurve.step);
    expect(e.animated, isTrue);
  });

  test('ConnectorStyle.toEdge copia el estilo', () {
    const s = ConnectorStyle(
        curve: EdgeCurve.smoothStep,
        color: Color(0xFF00FF00),
        width: 3,
        label: 'envío');
    final e = s.toEdge(id: 'e', sourceNodeId: 'a', targetNodeId: 'b');
    expect(e.curve, EdgeCurve.smoothStep);
    expect(e.color, const Color(0xFF00FF00));
    expect(e.width, 3);
    expect(e.label, 'envío');
    expect(s.copyWith(kind: ConnectorKind.hierarchy).isHierarchy, isTrue);
  });
}
