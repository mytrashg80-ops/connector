import 'package:connector/connector.dart';
import 'package:connector/src/widgets/effects.dart';
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

Widget _host(NodeEditorController<void> c,
    {NodeEditorAnimations animations = const NodeEditorAnimations(),
    bool reduceMotion = false}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
          size: const Size(800, 600), disableAnimations: reduceMotion),
      child: Scaffold(
        body: SizedBox(
          width: 800,
          height: 600,
          child: NodeEditor<void>(
            controller: c,
            config: NodeEditorConfig(
              showMinimap: false,
              showControls: false,
              animations: animations,
            ),
          ),
        ),
      ),
    ),
  );
}

/// Efectos del editor (a través del primer nodo animable).
EditorEffects _fx(WidgetTester tester) => tester
    .renderObject<RenderNodeEffect>(find.byType(NodeEffect).first)
    .effects;

void main() {
  testWidgets('un nodo nuevo aparece creciendo y queda normal', (tester) async {
    final c =
        NodeEditorController<void>(nodes: [_n('a', const Offset(40, 40))]);
    await tester.pumpWidget(_host(c));
    c.addNode(_n('b', const Offset(300, 40)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final fx = _fx(tester);
    expect(fx.opacityOf('b'), inExclusiveRange(0, 1));
    expect(fx.scaleOf('b'), lessThan(1));
    await tester.pumpAndSettle();
    expect(fx.touches('b'), isFalse);
    expect(find.text('Nodo b'), findsOneWidget);
  });

  testWidgets('un nodo borrado se desvanece antes de desaparecer',
      (tester) async {
    final c = NodeEditorController<void>(nodes: [
      _n('a', const Offset(40, 40)),
      _n('b', const Offset(300, 40)),
    ]);
    await tester.pumpWidget(_host(c));
    c.removeNode('b');
    expect(c.containsNode('b'), isFalse); // el modelo cambia al instante
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('Nodo b'), findsOneWidget);
    expect(_fx(tester).isGhost('b'), isTrue);
    // Sigue donde estaba.
    expect(tester.getCenter(find.text('Nodo b')).dx, greaterThan(300));
    await tester.pumpAndSettle();
    expect(find.text('Nodo b'), findsNothing);
  });

  testWidgets('deshacer un movimiento desliza el nodo', (tester) async {
    final c =
        NodeEditorController<void>(nodes: [_n('a', const Offset(40, 40))]);
    await tester.pumpWidget(_host(c));
    c.moveNodes(['a'], const Offset(200, 0));
    await tester.pumpAndSettle();
    final moved = tester.getCenter(find.text('Nodo a')).dx;
    c.undo();
    expect(c.node('a')!.position, const Offset(40, 40));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    final mid = tester.getCenter(find.text('Nodo a')).dx;
    expect(mid, lessThan(moved));
    expect(mid, greaterThan(moved - 200));
    await tester.pumpAndSettle();
    expect(
        tester.getCenter(find.text('Nodo a')).dx, closeTo(moved - 200, 0.01));
  });

  testWidgets('al arrastrar el nodo se levanta y al soltar se asienta',
      (tester) async {
    final c =
        NodeEditorController<void>(nodes: [_n('a', const Offset(40, 40))]);
    await tester.pumpWidget(_host(c));
    final g = await tester.startGesture(
        tester.getCenter(find.byType(NodeEffect)),
        kind: PointerDeviceKind.mouse);
    await g.moveBy(const Offset(20, 0));
    await g.moveBy(const Offset(20, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    final fx = _fx(tester);
    expect(fx.liftOf('a'), 1);
    await g.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(fx.liftOf('a'), lessThan(1));
    await tester.pumpAndSettle();
    expect(fx.touches('a'), isFalse);
    expect(c.node('a')!.position, const Offset(80, 40));
  });

  testWidgets('plegar una rama recoge los hijos hacia el padre',
      (tester) async {
    final c = NodeEditorController<void>(nodes: [
      _n('p', const Offset(40, 40)),
      _n('h', const Offset(40, 300), parent: 'p'),
    ]);
    await tester.pumpWidget(_host(c));
    final start = tester.getCenter(find.text('Nodo h')).dy;
    c.setCollapsed('p', true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Nodo h'), findsOneWidget);
    expect(tester.getCenter(find.text('Nodo h')).dy, lessThan(start));
    await tester.pumpAndSettle();
    expect(find.text('Nodo h'), findsNothing);

    c.setCollapsed('p', false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(tester.getCenter(find.text('Nodo h')).dy, lessThan(start));
    await tester.pumpAndSettle();
    expect(tester.getCenter(find.text('Nodo h')).dy, closeTo(start, 0.01));
  });

  testWidgets('las conexiones nuevas se dibujan y las borradas se desvanecen',
      (tester) async {
    final c = NodeEditorController<void>(nodes: [
      _n('a', const Offset(40, 40)),
      _n('b', const Offset(400, 40)),
    ]);
    await tester.pumpWidget(_host(c));
    final e = c.connect(sourceNodeId: 'a', targetNodeId: 'b')!;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final fx = _fx(tester);
    expect(fx.edgeProgress(e.id), inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
    expect(fx.edgeProgress(e.id), isNull);

    c.removeEdge(e.id);
    await tester.pump();
    expect(fx.ghostLines, hasLength(1));
    await tester.pumpAndSettle();
    expect(fx.ghostLines, isEmpty);
  });

  testWidgets('fitView(animate: true) desliza la cámara', (tester) async {
    final c = NodeEditorController<void>(nodes: [
      _n('a', const Offset(1000, 1000)),
    ]);
    await tester.pumpWidget(_host(c));
    c.fitView(animate: true);
    expect(c.viewport.isAnimating, isTrue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final mid = c.viewport.offset;
    await tester.pumpAndSettle();
    final end = c.viewport.offset;
    expect(mid, isNot(end));
    expect(mid, isNot(Offset.zero));
    // El mismo resultado que sin animar.
    c.viewport.setView(offset: Offset.zero, scale: 1);
    c.fitView();
    expect(c.viewport.offset, end);
  });

  testWidgets('NodeEditorAnimations.none: todo es instantáneo', (tester) async {
    final c = NodeEditorController<void>(nodes: [
      _n('a', const Offset(40, 40)),
      _n('b', const Offset(300, 40)),
    ]);
    await tester.pumpWidget(_host(c, animations: NodeEditorAnimations.none));
    expect(find.byType(NodeEffect), findsNothing);
    c.removeNode('b');
    await tester.pump();
    expect(find.text('Nodo b'), findsNothing);
    c.fitView(animate: true);
    expect(c.viewport.isAnimating, isFalse);
  });

  testWidgets('respeta "reducir movimiento" del sistema', (tester) async {
    final c =
        NodeEditorController<void>(nodes: [_n('a', const Offset(40, 40))]);
    await tester.pumpWidget(_host(c, reduceMotion: true));
    expect(find.byType(NodeEffect), findsNothing);
    await tester.pumpWidget(_host(c,
        reduceMotion: true,
        animations: const NodeEditorAnimations(respectReduceMotion: false)));
    expect(find.byType(NodeEffect), findsOneWidget);
  });

  testWidgets('un documento entero no se anima nodo a nodo', (tester) async {
    final c =
        NodeEditorController<void>(nodes: [_n('a', const Offset(40, 40))]);
    await tester.pumpWidget(
        _host(c, animations: const NodeEditorAnimations(maxAnimatedNodes: 5)));
    c.addNodes([
      for (var i = 0; i < 10; i++) _n('n$i', Offset(40.0 + i * 20, 200)),
    ]);
    await tester.pump();
    expect(_fx(tester).isIdle, isTrue);
  });
}
