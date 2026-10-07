// Ejemplo mínimo de `connector`: una red de almacenes, sucursales y
// productos. El editor sólo pinta el lienzo; el menú contextual, la barra de
// la selección, los controles de la cámara y los diálogos los construye la
// aplicación con su propio estilo.

import 'package:connector/connector.dart';
import 'package:flutter/material.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'connector',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.indigo),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
      ),
      home: const EditorPage(),
    );
  }
}

/// Tipos de nodo de la aplicación.
const Map<String, NodeTypeStyle> _types = {
  'almacen': NodeTypeStyle(
      label: 'Almacén', icon: Icons.warehouse_outlined, color: Colors.indigo),
  'sucursal': NodeTypeStyle(
      label: 'Sucursal', icon: Icons.storefront_outlined, color: Colors.teal),
  'producto': NodeTypeStyle(
      label: 'Producto',
      icon: Icons.inventory_2_outlined,
      color: Colors.orange,
      shape: NodeShape.pill),
};

class EditorPage extends StatefulWidget {
  const EditorPage({super.key});

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  final NodeEditorController<void> _controller = NodeEditorController(
    nodes: const [
      NodeData(
          id: 'central',
          type: 'almacen',
          title: 'Almacén central',
          subtitle: 'Madrid',
          position: Offset(320, 40)),
      NodeData(
          id: 'norte',
          type: 'sucursal',
          title: 'Sucursal Norte',
          subtitle: 'Bilbao',
          parentId: 'central',
          position: Offset(80, 260)),
      NodeData(
          id: 'sur',
          type: 'sucursal',
          title: 'Sucursal Sur',
          subtitle: 'Sevilla',
          parentId: 'central',
          position: Offset(560, 260)),
      NodeData(
          id: 'tornillos',
          type: 'producto',
          title: 'Tornillos M6',
          size: Size(170, 44),
          position: Offset(95, 480)),
      NodeData(
          id: 'tuercas',
          type: 'producto',
          title: 'Tuercas M6',
          size: Size(170, 44),
          position: Offset(575, 480)),
    ],
    edges: const [
      EdgeData(
          id: 'e1',
          sourceNodeId: 'norte',
          targetNodeId: 'tornillos',
          label: '120 u.'),
      EdgeData(
          id: 'e2',
          sourceNodeId: 'sur',
          targetNodeId: 'tuercas',
          label: '80 u.',
          animated: true),
    ],
  );

  // El tema del editor se crea sólo cuando cambian los colores de la app: el
  // editor usa su identidad para saber cuándo invalidar sus cachés.
  ColorScheme? _scheme;
  late NodeEditorTheme _theme;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scheme = Theme.of(context).colorScheme;
    if (scheme != _scheme) {
      _scheme = scheme;
      _theme = NodeEditorTheme.fromColorScheme(scheme, nodeTypes: _types);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // ------------------------------------------------------- acciones propias

  void _addNode(String type, Offset at, {String? parentId}) {
    final style = _types[type]!;
    final id = _controller.generateId(type);
    _controller
      ..addNode(NodeData(
        id: id,
        type: type,
        title: 'Nuevo: ${style.label}',
        parentId: parentId,
        size: style.shape == NodeShape.pill
            ? const Size(170, 44)
            : const Size(200, 96),
        position: at,
      ))
      ..selectNode(id);
  }

  Future<void> _rename(NodeData<void> node) async {
    final text = TextEditingController(text: node.title);
    final title = await showDialog<String>(
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
    text.dispose();
    if (title == null || title.trim().isEmpty) return;
    _controller.updateNode(node.id, (n) => n.copyWith(title: title.trim()));
  }

  // ------------------------------------------------------ menú contextual

  Future<void> _contextMenu(EditorContextMenuDetails<void> details) async {
    final appItems = <(IconData, String, VoidCallback)>[
      if (details.target case CanvasTarget(:final worldPosition))
        for (final MapEntry(:key, :value) in _types.entries)
          (
            value.icon!,
            'Nuevo: ${value.label}',
            () => _addNode(key, worldPosition)
          ),
      if (details.target case NodeTarget(:final node)) ...[
        (Icons.edit_outlined, 'Renombrar', () => _rename(node)),
        (
          Icons.add_link,
          'Añadir sucursal dependiente',
          () => _addNode('sucursal', node.position + const Offset(0, 220),
              parentId: node.id),
        ),
      ],
    ];
    final scheme = Theme.of(context).colorScheme;
    final p = details.globalPosition;
    final run = await showMenu<VoidCallback>(
      context: context,
      position: RelativeRect.fromLTRB(p.dx, p.dy, p.dx, p.dy),
      items: [
        for (final (icon, label, run) in appItems) _menuItem(icon, label, run),
        if (appItems.isNotEmpty) const PopupMenuDivider(),
        for (final a in details.actions)
          _menuItem(
            _icon(a),
            _label(a),
            a.call,
            enabled: a.enabled,
            color: a.destructive ? scheme.error : null,
            checked: a.selected,
          ),
      ],
    );
    run?.call();
  }

  PopupMenuItem<VoidCallback> _menuItem(
          IconData icon, String label, VoidCallback run,
          {bool enabled = true, Color? color, bool checked = false}) =>
      PopupMenuItem(
        value: run,
        enabled: enabled,
        height: 40,
        child: Row(children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 12),
          Expanded(
              child: Text(label,
                  style: color == null ? null : TextStyle(color: color))),
          if (checked) const Icon(Icons.check, size: 16),
        ]),
      );

  // ------------------------------------------------- barra de la selección

  /// Acciones del editor que mostramos en la barra flotante.
  static const Set<EditorCommand> _toolbarCommands = {
    EditorCommand.duplicate,
    EditorCommand.collapse,
    EditorCommand.expand,
    EditorCommand.toggleEdgeAnimation,
    EditorCommand.reverseEdge,
    EditorCommand.unlink,
    EditorCommand.delete,
    EditorCommand.deleteEdge,
  };

  Widget _selectionToolbar(
      BuildContext context, EditorSelectionDetails<void> details) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      elevation: 3,
      borderRadius: BorderRadius.circular(12),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (details.target case NodeTarget(:final node))
          IconButton(
            tooltip: 'Renombrar',
            iconSize: 18,
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _rename(node),
          ),
        for (final a in details.actions)
          if (_toolbarCommands.contains(a.command))
            IconButton(
              tooltip: _label(a),
              iconSize: 18,
              isSelected: a.selected,
              color: a.destructive ? scheme.error : null,
              icon: Icon(_icon(a)),
              onPressed: a.enabled ? a.call : null,
            ),
      ]),
    );
  }

  // --------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: NodeEditor<void>(
        controller: _controller,
        theme: _theme,
        autofocus: true,
        onNodeDoubleTap: _rename,
        onContextMenu: _contextMenu,
        selectionOverlayBuilder: _selectionToolbar,
        overlays: [
          Positioned(
            left: 16,
            bottom: 16,
            child: _CameraControls(controller: _controller),
          ),
          Positioned(
            right: 16,
            bottom: 16,
            child: NodeEditorMinimap<void>(controller: _controller),
          ),
        ],
      ),
    );
  }
}

/// Zoom, encuadre e historial hechos con los métodos del controlador.
class _CameraControls extends StatelessWidget {
  const _CameraControls({required this.controller});

  final NodeEditorController<void> controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      elevation: 2,
      borderRadius: BorderRadius.circular(14),
      child: ListenableBuilder(
        listenable: c.history,
        builder: (context, _) =>
            Column(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
              tooltip: 'Acercar',
              icon: const Icon(Icons.add),
              onPressed: () => c.viewport.zoomBy(1.2, animate: true)),
          IconButton(
              tooltip: 'Alejar',
              icon: const Icon(Icons.remove),
              onPressed: () => c.viewport.zoomBy(1 / 1.2, animate: true)),
          IconButton(
              tooltip: 'Ajustar vista',
              icon: const Icon(Icons.fit_screen_outlined),
              onPressed: () => c.fitView(animate: true)),
          IconButton(
              tooltip: 'Deshacer',
              icon: const Icon(Icons.undo),
              onPressed: c.canUndo ? c.undo : null),
          IconButton(
              tooltip: 'Rehacer',
              icon: const Icon(Icons.redo),
              onPressed: c.canRedo ? c.redo : null),
        ]),
      ),
    );
  }
}

// ------------------------------------------------- textos e iconos propios

String _label(EditorAction a) => switch (a.command) {
      EditorCommand.duplicate => 'Duplicar',
      EditorCommand.delete => 'Eliminar',
      EditorCommand.deleteWithDescendants => 'Eliminar con descendientes',
      EditorCommand.collapse => 'Colapsar',
      EditorCommand.expand => 'Expandir',
      EditorCommand.detachFromParent || EditorCommand.unlink => 'Separar',
      EditorCommand.lock => 'Bloquear',
      EditorCommand.unlock => 'Desbloquear',
      EditorCommand.bringToFront => 'Traer al frente',
      EditorCommand.resetStyle => 'Restablecer aspecto',
      EditorCommand.focus => 'Centrar',
      EditorCommand.deleteEdge => 'Eliminar conexión',
      EditorCommand.straightenEdge ||
      EditorCommand.straightenLink =>
        'Enderezar',
      EditorCommand.toggleEdgeAnimation => 'Animar flujo',
      EditorCommand.setEdgeCurve => switch (a.value) {
          EdgeCurve.bezier => 'Trazado curvo',
          EdgeCurve.smoothStep => 'Trazado ortogonal suave',
          EdgeCurve.step => 'Trazado en escalones',
          _ => 'Trazado recto',
        },
      EditorCommand.reverseEdge => 'Invertir sentido',
      EditorCommand.selectAll => 'Seleccionar todo',
      EditorCommand.clearSelection => 'Quitar selección',
      EditorCommand.fitView => 'Ajustar vista',
      EditorCommand.undo => 'Deshacer',
      EditorCommand.redo => 'Rehacer',
    };

IconData _icon(EditorAction a) => switch (a.command) {
      EditorCommand.duplicate => Icons.copy_all_outlined,
      EditorCommand.delete || EditorCommand.deleteEdge => Icons.delete_outline,
      EditorCommand.deleteWithDescendants => Icons.delete_sweep_outlined,
      EditorCommand.collapse => Icons.unfold_less,
      EditorCommand.expand => Icons.unfold_more,
      EditorCommand.detachFromParent || EditorCommand.unlink => Icons.link_off,
      EditorCommand.lock => Icons.lock_outline,
      EditorCommand.unlock => Icons.lock_open,
      EditorCommand.bringToFront => Icons.flip_to_front,
      EditorCommand.resetStyle => Icons.format_color_reset_outlined,
      EditorCommand.focus => Icons.center_focus_strong_outlined,
      EditorCommand.straightenEdge ||
      EditorCommand.straightenLink =>
        Icons.straighten,
      EditorCommand.toggleEdgeAnimation => Icons.animation,
      EditorCommand.setEdgeCurve => Icons.gesture,
      EditorCommand.reverseEdge => Icons.swap_horiz,
      EditorCommand.selectAll => Icons.select_all,
      EditorCommand.clearSelection => Icons.deselect,
      EditorCommand.fitView => Icons.fit_screen_outlined,
      EditorCommand.undo => Icons.undo,
      EditorCommand.redo => Icons.redo,
    };
