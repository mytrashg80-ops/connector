import 'package:connector/connector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

NodeData<void> _n(String id, Offset pos,
        {NodeStyle? style,
        String type = 'default',
        Size size = const Size(160, 80),
        Color? color}) =>
    NodeData<void>(
      id: id,
      position: pos,
      size: size,
      title: 'Nodo $id',
      type: type,
      style: style,
      color: color,
    );

void main() {
  group('NodeStyle', () {
    test('JSON de ida y vuelta (también dentro de NodeData)', () {
      const style = NodeStyle(
        shape: NodeShape.circle,
        icon: 'flag',
        filled: false,
        fillColor: Color(0xFF112233),
        borderColor: Color(0xFFAABBCC),
        borderWidth: 2.5,
        borderStyle: NodeBorderStyle.dashed,
        textColor: Color(0xFF000000),
      );
      expect(NodeStyle.fromJson(style.toJson()), style);
      final n = _n('a', Offset.zero, style: style);
      final back = NodeData.fromJson<void>(n.toJson());
      expect(back.style, style);
      // Sin estilo no se escribe nada.
      expect(_n('b', Offset.zero).toJson().containsKey('style'), isFalse);
    });

    test('copyWith y clear', () {
      const s = NodeStyle(icon: 'flag', fillColor: Color(0xFF000000));
      expect(s.copyWith(clearIcon: true).icon, isNull);
      expect(s.copyWith(shape: NodeShape.pill).shape, NodeShape.pill);
      expect(const NodeStyle().isEmpty, isTrue);
      final n = _n('a', Offset.zero, style: s, color: const Color(0xFF00FF00));
      expect(n.copyWith(clearStyle: true).style, isNull);
      expect(n.copyWith(clearColor: true).color, isNull);
      // El estilo forma parte del contenido (reconstruye el widget).
      expect(n.sameContentAs(n.copyWith(style: const NodeStyle())), isFalse);
    });
  });

  group('resolveNodeStyle', () {
    final theme = NodeEditorTheme.light(nodeTypes: const {
      'hito': NodeTypeStyle(
          icon: Icons.flag, color: Color(0xFF14B8A6), shape: NodeShape.circle),
      'nota': NodeTypeStyle(
          shape: NodeShape.box,
          filled: false,
          borderStyle: NodeBorderStyle.dashed),
    });

    test('nodo > tipo > tema', () {
      final plain = theme.resolveNodeStyle(_n('a', Offset.zero));
      expect(plain.shape, NodeShape.card);
      expect(plain.filled, isTrue);
      expect(plain.fillColor, theme.nodeColor);
      expect(plain.borderStyle, NodeBorderStyle.solid);

      final hito = theme.resolveNodeStyle(_n('h', Offset.zero, type: 'hito'));
      expect(hito.shape, NodeShape.circle);
      expect(hito.icon, Icons.flag);
      expect(hito.accent, const Color(0xFF14B8A6));

      final own = theme.resolveNodeStyle(_n('h', Offset.zero,
          type: 'hito',
          color: const Color(0xFFFF0000),
          style: const NodeStyle(shape: NodeShape.diamond, icon: 'check')));
      expect(own.shape, NodeShape.diamond);
      expect(own.icon, NodeIcons.all['check']);
      expect(own.accent, const Color(0xFFFF0000));
    });

    test('sólo líneas: sin relleno y borde del color del nodo', () {
      final nota = theme.resolveNodeStyle(
          _n('n', Offset.zero, type: 'nota', color: const Color(0xFF123456)));
      expect(nota.filled, isFalse);
      expect(nota.fillColor.a, 0);
      expect(nota.borderColor, const Color(0xFF123456));
      expect(nota.borderStyle, NodeBorderStyle.dashed);
    });

    test('iconos propios en el tema', () {
      final t = theme.copyWith(icons: {...NodeIcons.all, 'mio': Icons.abc});
      final r = t.resolveNodeStyle(
          _n('a', Offset.zero, style: const NodeStyle(icon: 'mio')));
      expect(r.icon, Icons.abc);
      // Una clave desconocida usa el icono del tipo.
      expect(theme.iconFor('no-existe'), isNull);
    });
  });

  group('geometría', () {
    test('el círculo ocupa la parte de arriba, el título va debajo', () {
      final r = NodeShapes.bodyRect(NodeShape.circle, const Size(88, 112));
      expect(r, const Rect.fromLTWH(0, 0, 88, 88));
      expect(NodeShapes.bodyRect(NodeShape.box, const Size(88, 112)),
          const Rect.fromLTWH(0, 0, 88, 112));
    });

    test('siluetas', () {
      const r = Rect.fromLTWH(0, 0, 100, 60);
      for (final s in NodeShape.values) {
        final p = NodeShapes.path(s, r, 10);
        expect(p.contains(r.center), isTrue, reason: '$s');
      }
      // Las esquinas quedan fuera del rombo y del hexágono.
      expect(
          NodeShapes.path(NodeShape.diamond, r, 10)
              .contains(const Offset(3, 3)),
          isFalse);
      expect(
          NodeShapes.path(NodeShape.hexagon, r, 10)
              .contains(const Offset(2, 2)),
          isFalse);
    });

    test('las líneas se anclan al círculo, no al título', () {
      final theme = NodeEditorTheme.light();
      final n = _n('c', const Offset(100, 100),
          size: const Size(88, 112),
          style: const NodeStyle(shape: NodeShape.circle));
      expect(
          theme.anchorRect(n, n.rect), const Rect.fromLTWH(100, 100, 88, 88));
      // Puertos en el borde del círculo.
      final withPort = n.copyWith(
          ports: const [NodePort.output(id: 'o', side: PortSide.bottom)]);
      expect(
          theme.portLocalPosition(withPort, n.size, 'o'), const Offset(44, 88));
    });
  });

  testWidgets('todas las formas y bordes se pintan sin errores',
      (tester) async {
    var i = 0;
    final nodes = <NodeData<void>>[
      for (final shape in NodeShape.values)
        for (final border in NodeBorderStyle.values)
          for (final filled in [true, false])
            _n('n${i++}', Offset((i % 6) * 190.0, (i ~/ 6) * 130.0),
                size: shape == NodeShape.circle
                    ? const Size(88, 112)
                    : const Size(170, 90),
                style: NodeStyle(
                    shape: shape,
                    borderStyle: border,
                    filled: filled,
                    icon: 'star')),
    ];
    final c = NodeEditorController<void>(nodes: nodes);
    for (final theme in [NodeEditorTheme.light(), NodeEditorTheme.dark()]) {
      await tester.pumpWidget(MaterialApp(
        home: SizedBox(
          width: 1400,
          height: 1000,
          child: NodeEditor<void>(
            controller: c,
            theme: theme,
            config: const NodeEditorConfig(
                showMinimap: false,
                showControls: false,
                animations: NodeEditorAnimations.none),
          ),
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(DefaultNodeBody), findsWidgets);
      expect(find.byIcon(NodeIcons.all['star']!), findsWidgets);
      // Nivel de detalle (sin widgets): también dibuja las formas.
      c.viewport.setView(scale: 0.2);
      await tester.pump();
      expect(tester.takeException(), isNull);
      c.viewport.setView(scale: 1);
      await tester.pump();
    }
  });

  testWidgets('cambiar el estilo actualiza el nodo y se puede deshacer',
      (tester) async {
    final c =
        NodeEditorController<void>(nodes: [_n('a', const Offset(40, 40))]);
    await tester.pumpWidget(MaterialApp(
      home: SizedBox(
        width: 800,
        height: 600,
        child: NodeEditor<void>(
          controller: c,
          config: const NodeEditorConfig(
              showMinimap: false,
              showControls: false,
              animations: NodeEditorAnimations.none),
        ),
      ),
    ));
    expect(find.byIcon(NodeIcons.all['bolt']!), findsNothing);
    c.updateNode(
        'a',
        (n) => n.copyWith(
            style: const NodeStyle(shape: NodeShape.pill, icon: 'bolt')));
    await tester.pump();
    expect(find.byIcon(NodeIcons.all['bolt']!), findsOneWidget);
    c.undo();
    await tester.pump();
    expect(find.byIcon(NodeIcons.all['bolt']!), findsNothing);
  });
}
