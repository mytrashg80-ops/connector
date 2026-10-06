import 'dart:convert';

import 'package:connector/connector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

import 'node_cards.dart';
import 'scenarios.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // En web evitamos el menú contextual del navegador para usar el nuestro.
  if (kIsWeb) BrowserContextMenu.disableContextMenu();
  runApp(const DemoApp());
}

class DemoApp extends StatefulWidget {
  const DemoApp({super.key});

  @override
  State<DemoApp> createState() => _DemoAppState();
}

class _DemoAppState extends State<DemoApp> {
  ThemeMode _mode = ThemeMode.dark;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Connector · Editor de nodos',
      debugShowCheckedModeBanner: false,
      themeMode: _mode,
      theme: ThemeData(
          colorSchemeSeed: const Color(0xFF6366F1),
          brightness: Brightness.light),
      darkTheme: ThemeData(
          colorSchemeSeed: const Color(0xFF8B7CF6),
          brightness: Brightness.dark),
      home: EditorPage(
        dark: _mode == ThemeMode.dark,
        onToggleTheme: () => setState(() =>
            _mode = _mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark),
      ),
    );
  }
}

class EditorPage extends StatefulWidget {
  const EditorPage(
      {super.key, required this.dark, required this.onToggleTheme});

  final bool dark;
  final VoidCallback onToggleTheme;

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> with TickerProviderStateMixin {
  final _editorKey = GlobalKey<NodeEditorState<Item>>();
  final controller = NodeEditorController<Item>();

  // Temas creados una sola vez: el editor usa su identidad para cachear.
  final _light = NodeEditorTheme.light(nodeTypes: nodeTypeStyles);
  final _dark = NodeEditorTheme.dark(nodeTypes: nodeTypeStyles);

  int _scenario = 0;
  bool _snap = false;
  bool _animate = true;
  int _connector = 0;

  /// Tipos de conector que se crean al arrastrar desde el "+" de un nodo.
  static const _connectors = <(String, IconData, ConnectorStyle)>[
    (
      'Jerarquía (padre e hijo)',
      Icons.account_tree_outlined,
      ConnectorStyle.hierarchy
    ),
    (
      'Flujo con flecha',
      Icons.trending_flat,
      ConnectorStyle(curve: EdgeCurve.bezier, arrow: true)
    ),
    (
      'Ortogonal',
      Icons.turn_right,
      ConnectorStyle(curve: EdgeCurve.smoothStep, arrow: true)
    ),
    (
      'Recta',
      Icons.horizontal_rule,
      ConnectorStyle(curve: EdgeCurve.straight, arrow: true)
    ),
    (
      'Discontinua',
      Icons.more_horiz,
      ConnectorStyle(curve: EdgeCurve.bezier, dashed: true, arrow: true)
    ),
    (
      'Flujo animado',
      Icons.animation,
      ConnectorStyle(curve: EdgeCurve.bezier, animated: true, arrow: true)
    ),
  ];

  Scenario get scenario => scenarios[_scenario];

  @override
  void initState() {
    super.initState();
    _load(0);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _load(int index) async {
    final (nodes, edges) = scenarios[index].build();
    setState(() {
      _scenario = index;
      // Jerarquías → enlaces padre/hijo; cadenas → conexiones de flujo.
      _connector = edges.isEmpty ? 0 : 1;
    });
    controller
      ..clear()
      ..addNodes(nodes)
      ..addEdges(edges)
      ..clearHistory()
      ..clearSelection();
    await controller.applyLayout(scenarios[index].layout);
    controller.clearHistory();
    // Tras el primer frame ya conocemos el viewport y el tamaño real de los
    // nodos con `autoSize`, así que reorganizamos y encuadramos.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _scenario != index) return;
      await controller.applyLayout(scenarios[index].layout);
      controller
        ..clearHistory()
        ..fitView(animate: true);
    });
  }

  void _autoLayout() => controller.applyLayout(
        scenario.layout,
        vsync: this,
        fitAfter: true,
      );

  NodeEditorTheme get _theme => widget.dark ? _dark : _light;

  // ----------------------------------------------------------------- acciones

  String _addNode(String type, Offset world,
      {String? parentId, String? title}) {
    final id = controller.generateId();
    final size = sizeFor(type);
    controller.addNode(makeNode(
      id,
      type,
      title ?? nodeTypeStyles[type]?.label ?? type,
      position: world - size.center(Offset.zero),
      parentId: parentId,
      data: type == 'product' ? {'stock': 0, 'max': 100} : null,
    ));
    controller.selectNode(id);
    return id;
  }

  Future<void> _rename(NodeData<Item> node) async {
    final text = TextEditingController(text: node.title);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Renombrar'),
        content: TextField(
          controller: text,
          autofocus: true,
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, text.text),
              child: const Text('Guardar')),
        ],
      ),
    );
    if (result != null && result.trim().isNotEmpty) {
      controller.updateNode(node.id, (n) => n.copyWith(title: result.trim()));
    }
  }

  Future<void> _nodeMenu(NodeData<Item> node, Offset global) async {
    final hasParent = node.parentId != null;
    final action = await showMenu<String>(
      context: context,
      position:
          RelativeRect.fromLTRB(global.dx, global.dy, global.dx, global.dy),
      items: [
        const PopupMenuItem(
            value: 'rename', child: _MenuRow(Icons.edit, 'Renombrar')),
        const PopupMenuItem(
            value: 'child',
            child: _MenuRow(Icons.subdirectory_arrow_right, 'Añadir hijo')),
        const PopupMenuItem(
            value: 'dup', child: _MenuRow(Icons.copy_all_outlined, 'Duplicar')),
        if (controller.hasChildren(node.id))
          PopupMenuItem(
            value: 'collapse',
            child: _MenuRow(
                node.collapsed ? Icons.unfold_more : Icons.unfold_less,
                node.collapsed ? 'Expandir' : 'Colapsar'),
          ),
        if (hasParent)
          const PopupMenuItem(
              value: 'unparent',
              child: _MenuRow(Icons.link_off, 'Quitar de su padre')),
        PopupMenuItem(
          value: 'lock',
          child: _MenuRow(node.locked ? Icons.lock_open : Icons.lock_outline,
              node.locked ? 'Desbloquear' : 'Bloquear'),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
            value: 'delete', child: _MenuRow(Icons.delete_outline, 'Eliminar')),
        const PopupMenuItem(
            value: 'deleteTree',
            child: _MenuRow(
                Icons.delete_sweep_outlined, 'Eliminar con descendientes')),
      ],
    );
    switch (action) {
      case 'rename':
        await _rename(node);
      case 'child':
        final r = controller.rectOf(node.id);
        final type = _childTypeOf(node.type);
        final pos = scenario.hierarchyAxis == Axis.vertical
            ? r.bottomCenter + Offset(0, 60 + sizeFor(type).height / 2)
            : r.centerRight + Offset(80 + sizeFor(type).width / 2, 0);
        controller.transaction(() {
          if (node.collapsed) controller.setCollapsed(node.id, false);
          _addNode(type, pos, parentId: node.id);
        });
      case 'dup':
        controller.duplicate(controller.selectedNodeIds);
      case 'collapse':
        controller.toggleCollapsed(node.id);
      case 'unparent':
        controller.setParent(node.id, null);
      case 'lock':
        controller.updateNode(node.id, (n) => n.copyWith(locked: !n.locked));
      case 'delete':
        controller.removeNode(node.id);
      case 'deleteTree':
        controller.removeNode(node.id, withDescendants: true);
    }
  }

  Future<void> _linkMenu(NodeData<Item> child, Offset global) async {
    final parent = controller.node(child.parentId!);
    final action = await showMenu<String>(
      context: context,
      position:
          RelativeRect.fromLTRB(global.dx, global.dy, global.dx, global.dy),
      items: [
        if (child.linkBend != null)
          const PopupMenuItem(
              value: 'straighten',
              child: _MenuRow(Icons.straighten, 'Enderezar trazado')),
        PopupMenuItem(
            value: 'unlink',
            child: _MenuRow(
                Icons.link_off, 'Separar de “${parent?.title ?? ''}”')),
      ],
    );
    if (action == 'straighten') {
      controller.setLinkBend(child.id, null);
    } else if (action == 'unlink') {
      controller.setParent(child.id, null);
      _onParentChanged(child.id, null);
    }
  }

  void _onParentChanged(String child, String? parent) {
    final c = controller.node(child)?.title;
    _toast(parent == null
        ? '“$c” ya no depende de nadie'
        : '“$c” ahora depende de “${controller.node(parent)?.title}”');
  }

  Future<void> _edgeMenu(EdgeData edge, Offset global) async {
    final action = await showMenu<String>(
      context: context,
      position:
          RelativeRect.fromLTRB(global.dx, global.dy, global.dx, global.dy),
      items: [
        PopupMenuItem(
          value: 'anim',
          child: _MenuRow(Icons.animation,
              edge.animated ? 'Detener animación' : 'Animar flujo'),
        ),
        for (final c in EdgeCurve.values)
          PopupMenuItem(
              value: 'curve:${c.name}',
              child: _MenuRow(Icons.timeline, 'Curva: ${c.name}')),
        if (edge.bend != null)
          const PopupMenuItem(
              value: 'straighten',
              child: _MenuRow(Icons.straighten, 'Enderezar trazado')),
        const PopupMenuDivider(),
        const PopupMenuItem(
            value: 'delete',
            child: _MenuRow(Icons.delete_outline, 'Eliminar conexión')),
      ],
    );
    if (action == null) return;
    if (action == 'delete') {
      controller.removeEdge(edge.id);
    } else if (action == 'straighten') {
      controller.setEdgeBend(edge.id, null);
    } else if (action == 'anim') {
      controller.updateEdge(edge.id, (e) => e.copyWith(animated: !e.animated));
    } else if (action.startsWith('curve:')) {
      final c = EdgeCurve.values.byName(action.substring(6));
      controller.updateEdge(edge.id, (e) => e.copyWith(curve: c));
    }
  }

  Future<void> _canvasMenu(Offset world, Offset global) async {
    final type = await showMenu<String>(
      context: context,
      position:
          RelativeRect.fromLTRB(global.dx, global.dy, global.dx, global.dy),
      items: [
        for (final e in nodeTypeStyles.entries)
          PopupMenuItem(
              value: e.key,
              child: _MenuRow(e.value.icon!, 'Nuevo: ${e.value.label}')),
      ],
    );
    if (type != null) _addNode(type, world);
  }

  String _childTypeOf(String? type) => switch (type) {
        'company' => 'region',
        'region' => 'branch',
        'branch' => 'warehouse',
        'category' => 'product',
        final t => t ?? 'employee',
      };

  /// Soltar una conexión en el vacío crea un nodo nuevo ya conectado (o un
  /// hijo, si el conector es de jerarquía).
  void _onConnectionDropped(ConnectionDropDetails<Item> d) {
    if (d.style.isHierarchy) {
      _addNode(_childTypeOf(d.node.type), d.worldPosition, parentId: d.node.id);
      return;
    }
    final port = d.port;
    final type = switch (d.node.type) {
      'part' => 'station',
      'station' => 'product',
      'supplier' || 'product' => 'warehouse',
      'warehouse' => 'branch',
      'branch' || 'transport' => 'customer',
      final t => t,
    };
    controller.transaction(() {
      final id = _addNode(type, d.worldPosition);
      final created = controller.node(id)!;
      if (port == null || port.canSend) {
        final target = created.ports.where((p) => p.canReceive).firstOrNull;
        controller.connect(
          sourceNodeId: d.node.id,
          sourcePortId: port?.id,
          targetNodeId: id,
          targetPortId: target?.id,
          style: d.style,
        );
      } else {
        final source = created.ports.where((p) => p.canSend).firstOrNull;
        controller.connect(
          sourceNodeId: id,
          sourcePortId: source?.id,
          targetNodeId: d.node.id,
          targetPortId: port.id,
          style: d.style,
        );
      }
    });
  }

  void _showJson() {
    final json =
        const JsonEncoder.withIndent('  ').convert(controller.toJson());
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('JSON (${json.length} caracteres)'),
        content: SizedBox(
          width: 520,
          height: 420,
          child: SingleChildScrollView(
            child: SelectableText(json,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar')),
        ],
      ),
    );
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          width: 360,
          duration: const Duration(seconds: 2)));
  }

  // -------------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final t = _theme;
    final wide = MediaQuery.sizeOf(context).width > 760;
    // La paleta usa `pointerDragAnchorStrategy`: `details.offset` es la
    // posición del puntero.
    final editor = DragTarget<String>(
      onMove: (details) {
        final state = _editorKey.currentState!;
        state.showDropPreview(Rect.fromCenter(
          center: state.globalToWorld(details.offset),
          width: sizeFor(details.data).width,
          height: sizeFor(details.data).height,
        ));
      },
      onLeave: (_) => _editorKey.currentState?.showDropPreview(null),
      onAcceptWithDetails: (details) {
        final state = _editorKey.currentState!;
        state.showDropPreview(null);
        _addNode(details.data, state.globalToWorld(details.offset));
      },
      builder: (context, _, __) => NodeEditor<Item>(
        key: _editorKey,
        controller: controller,
        theme: t.copyWithCurve(scenario.curve),
        autofocus: true,
        config: NodeEditorConfig(
          snapToGrid: _snap,
          hierarchyAxis: scenario.hierarchyAxis,
          showMinimap: wide,
          animations: _animate
              ? const NodeEditorAnimations()
              : NodeEditorAnimations.none,
          newConnector: _connectors[_connector].$3,
        ),
        nodeBuilder: buildNodeCard,
        onNodeDoubleTap: _rename,
        onNodeContextMenu: _nodeMenu,
        onEdgeContextMenu: _edgeMenu,
        onLinkContextMenu: _linkMenu,
        onCanvasContextMenu: _canvasMenu,
        onConnectionDropped: _onConnectionDropped,
        onConnectionRejected: _toast,
        onParentChanged: _onParentChanged,
      ),
    );

    return Scaffold(
      backgroundColor: t.backgroundColor,
      drawer: wide ? null : Drawer(child: _Sidebar(page: this)),
      body: SafeArea(
        child: Row(
          children: [
            if (wide) SizedBox(width: 260, child: _Sidebar(page: this)),
            Expanded(
              child: Column(
                children: [
                  _TopBar(page: this, showMenuButton: !wide),
                  Expanded(child: editor),
                  _StatusBar(controller: controller, theme: t),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pequeña extensión del ejemplo para cambiar la curva sin perder la
/// identidad del tema entre frames.
final _curveCache = Expando<Map<EdgeCurve, NodeEditorTheme>>();

extension on NodeEditorTheme {
  NodeEditorTheme copyWithCurve(EdgeCurve curve) {
    if (curve == edgeCurve) return this;
    final map = _curveCache[this] ??= {};
    return map[curve] ??= copyWith(edgeCurve: curve);
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 18),
        const SizedBox(width: 12),
        Text(text),
      ]);
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.page, required this.showMenuButton});

  final _EditorPageState page;
  final bool showMenuButton;

  @override
  Widget build(BuildContext context) {
    final t = page._theme;
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: t.controlsBackground,
        border: Border(bottom: BorderSide(color: t.controlsBorderColor)),
      ),
      child: Row(
        children: [
          if (showMenuButton)
            IconButton(
              icon: Icon(Icons.menu, color: t.controlsForeground),
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
          Icon(page.scenario.icon, color: t.accentColor, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              page.scenario.name,
              style: t.nodeTitleStyle.copyWith(fontSize: 15),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          PopupMenuButton<int>(
            tooltip: 'Tipo de conector que se crea con el "+" de cada nodo',
            initialValue: page._connector,
            // ignore: invalid_use_of_protected_member
            onSelected: (i) => page.setState(() => page._connector = i),
            itemBuilder: (context) => [
              for (var i = 0; i < _EditorPageState._connectors.length; i++)
                PopupMenuItem(
                  value: i,
                  child: _MenuRow(_EditorPageState._connectors[i].$2,
                      _EditorPageState._connectors[i].$1),
                ),
            ],
            child: IgnorePointer(
              child: _BarButton(
                icon: _EditorPageState._connectors[page._connector].$2,
                label:
                    'Conector: ${_EditorPageState._connectors[page._connector].$1}',
                theme: t,
                onTap: () {},
              ),
            ),
          ),
          _BarButton(
            icon: Icons.auto_fix_high,
            label: 'Auto-organizar',
            theme: t,
            onTap: page._autoLayout,
          ),
          _BarButton(
            icon: page._snap ? Icons.grid_on : Icons.grid_off,
            label: 'Imán',
            theme: t,
            active: page._snap,
            // ignore: invalid_use_of_protected_member
            onTap: () => page.setState(() => page._snap = !page._snap),
          ),
          _BarButton(
            icon: page._animate
                ? Icons.animation
                : Icons.motion_photos_off_outlined,
            label: 'Animaciones',
            theme: t,
            active: page._animate,
            // ignore: invalid_use_of_protected_member
            onTap: () => page.setState(() => page._animate = !page._animate),
          ),
          _BarButton(
            icon: Icons.data_object,
            label: 'JSON',
            theme: t,
            onTap: page._showJson,
          ),
          _BarButton(
            icon: page.widget.dark
                ? Icons.light_mode_outlined
                : Icons.dark_mode_outlined,
            label: page.widget.dark ? 'Claro' : 'Oscuro',
            theme: t,
            onTap: page.widget.onToggleTheme,
          ),
        ],
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.icon,
    required this.label,
    required this.theme,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final NodeEditorTheme theme;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? theme.accentColor : theme.controlsForeground;
    final compact = MediaQuery.sizeOf(context).width < 1000;
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Tooltip(
        message: label,
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: color,
            side: BorderSide(
                color: active ? theme.accentColor : theme.controlsBorderColor),
            padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14),
            minimumSize: const Size(0, 36),
          ),
          onPressed: onTap,
          icon: Icon(icon, size: 18),
          label: compact ? const SizedBox.shrink() : Text(label),
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.page});

  final _EditorPageState page;

  @override
  Widget build(BuildContext context) {
    final t = page._theme;
    final header = t.nodeTypeLabelStyle.copyWith(fontSize: 11);
    return Container(
      decoration: BoxDecoration(
        color: t.controlsBackground,
        border: Border(right: BorderSide(color: t.controlsBorderColor)),
      ),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Row(children: [
              Icon(Icons.hub_outlined, color: t.accentColor),
              const SizedBox(width: 8),
              Text('Connector', style: t.nodeTitleStyle.copyWith(fontSize: 17)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
            child: Text('ESCENARIOS', style: header),
          ),
          for (var i = 0; i < scenarios.length; i++)
            _SideTile(
              icon: scenarios[i].icon,
              label: scenarios[i].name,
              selected: i == page._scenario,
              theme: t,
              onTap: () {
                page._load(i);
                if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
                  Navigator.pop(context);
                }
              },
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
            child: Text('ARRASTRA AL LIENZO', style: header),
          ),
          for (final e in nodeTypeStyles.entries)
            Draggable<String>(
              data: e.key,
              // Horizontal: en táctil, arrastrar en vertical sigue haciendo
              // scroll de la lista.
              affinity: Axis.horizontal,
              dragAnchorStrategy: pointerDragAnchorStrategy,
              // Etiqueta pequeña junto al cursor; sobre el lienzo, el editor
              // dibuja además la silueta del nodo donde caerá.
              feedback: Transform.translate(
                offset: const Offset(14, 14),
                child: _DragPill(style: e.value, theme: t),
              ),
              childWhenDragging: Opacity(
                opacity: 0.4,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                  child: _PaletteChip(style: e.value, theme: t),
                ),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                child: _PaletteChip(style: e.value, theme: t),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
            child: Text('ATAJOS', style: header),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Rueda: zoom · Arrastrar fondo: mover\n'
              'Shift + arrastrar: selección múltiple\n'
              'Alt + soltar sobre nodo: asignar jefe/padre\n'
              'Arrastrar un borde: redimensionar\n'
              'Al arrastrar se muestran guías de\n'
              '   alineación (Ctrl: sin imán)\n'
              'Arrastrar el "+" de un nodo hasta otro:\n'
              '   crear conector (tipo en la barra)\n'
              'Arrastrar desde un puerto: conectar\n'
              'Arrastrar una línea: cambiar su trazado\n'
              '   (de vuelta a su sitio: recta)\n'
              'Arrastrar el extremo de una línea:\n'
              '   moverla a otro nodo/jefe\n'
              '   (soltar en el vacío: desconectar)\n'
              'Arrastrar una entrada conectada o\n'
              '   Ctrl + arrastrar salida: mover conexión\n'
              'Alt + clic en puerto: romper conexiones\n'
              'Clic derecho / pulsación larga: menú\n'
              'Supr: eliminar · Ctrl+Z / Ctrl+Y\n'
              'Ctrl+D: duplicar · F: ajustar vista',
              style: t.nodeSubtitleStyle.copyWith(height: 1.7),
            ),
          ),
        ],
      ),
    );
  }
}

class _SideTile extends StatelessWidget {
  const _SideTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.theme,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final NodeEditorTheme theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: selected
            ? theme.accentColor.withValues(alpha: 0.14)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(children: [
              Icon(icon,
                  size: 18,
                  color:
                      selected ? theme.accentColor : theme.controlsForeground),
              const SizedBox(width: 10),
              Expanded(
                child: Text(label,
                    style: theme.nodeTitleStyle.copyWith(
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w400,
                        color: selected ? theme.accentColor : null)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _DragPill extends StatelessWidget {
  const _DragPill({required this.style, required this.theme});

  final NodeTypeStyle style;
  final NodeEditorTheme theme;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: theme.nodeColor,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: style.color ?? theme.accentColor),
          boxShadow: const [
            BoxShadow(color: Color(0x40000000), blurRadius: 10)
          ],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.add, size: 14, color: style.color),
          const SizedBox(width: 6),
          Text(style.label ?? '',
              style: theme.nodeTitleStyle.copyWith(fontSize: 12)),
        ]),
      ),
    );
  }
}

class _PaletteChip extends StatelessWidget {
  const _PaletteChip({
    required this.style,
    required this.theme,
  });

  final NodeTypeStyle style;
  final NodeEditorTheme theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: theme.nodeColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.nodeBorderColor),
      ),
      child: Row(children: [
        Icon(style.icon, size: 18, color: style.color),
        const SizedBox(width: 10),
        Text(style.label ?? '',
            style: theme.nodeTitleStyle.copyWith(fontSize: 13)),
        const Spacer(),
        Icon(Icons.drag_indicator, size: 16, color: theme.portColor),
      ]),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.controller, required this.theme});

  final NodeEditorController<Item> controller;
  final NodeEditorTheme theme;

  @override
  Widget build(BuildContext context) {
    // Escucha sólo estructura/selección/conexiones: NO se reconstruye al
    // arrastrar nodos ni al mover la cámara.
    return ListenableBuilder(
      listenable: Listenable.merge(
          [controller.structure, controller.selection, controller.edgesSignal]),
      builder: (context, _) {
        final sel = controller.selectedNodeIds;
        final style = theme.nodeSubtitleStyle;
        return Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: theme.controlsBackground,
            border: Border(top: BorderSide(color: theme.controlsBorderColor)),
          ),
          child: Row(children: [
            Text(
                '${controller.nodeCount} nodos · ${controller.edgeCount} conexiones',
                style: style),
            const SizedBox(width: 24),
            const Spacer(),
            if (sel.length == 1) ...[
              Flexible(
                  child: Text(
                () {
                  final n = controller.node(sel.first)!;
                  final path = [
                    ...controller
                        .ancestorsOf(n.id)
                        .reversed
                        .map((id) => controller.node(id)!.title),
                    n.title,
                  ];
                  return path.join('  ›  ');
                }(),
                style: style,
                overflow: TextOverflow.ellipsis,
              )),
            ] else if (sel.length > 1)
              Text('${sel.length} seleccionados', style: style),
          ]),
        );
      },
    );
  }
}
