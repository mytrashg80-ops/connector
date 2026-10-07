import 'package:connector/connector.dart';
import 'package:flutter/material.dart';

import 'scenarios.dart';

const _shapeNames = {
  NodeShape.card: ('Tarjeta', Icons.web_asset),
  NodeShape.box: ('Caja', Icons.crop_square),
  NodeShape.pill: ('Píldora', Icons.smart_button_outlined),
  NodeShape.circle: ('Círculo', Icons.circle_outlined),
  NodeShape.diamond: ('Rombo', Icons.diamond_outlined),
  NodeShape.hexagon: ('Hexágono', Icons.hexagon_outlined),
};

const _borderNames = {
  NodeBorderStyle.solid: 'Sólido',
  NodeBorderStyle.dashed: 'Discontinuo',
  NodeBorderStyle.dotted: 'Punteado',
  NodeBorderStyle.none: 'Sin borde',
};

const _palette = <Color>[
  Color(0xFF6366F1),
  Color(0xFF0EA5E9),
  Color(0xFF14B8A6),
  Color(0xFF22C55E),
  Color(0xFFEAB308),
  Color(0xFFF97316),
  Color(0xFFEF4444),
  Color(0xFFEC4899),
  Color(0xFFA855F7),
  Color(0xFF64748B),
];

/// Tamaño razonable al cambiar de forma (un círculo necesita ser más alto
/// que ancho para el título, un rombo algo de aire…).
Size sizeForShape(NodeData<Item> n, NodeShape from, NodeShape to) {
  if (from == to) return n.size;
  switch (to) {
    case NodeShape.circle:
      return const Size(88, 112);
    case NodeShape.diamond:
      return Size(n.size.width < 160 ? 170 : n.size.width,
          n.size.height < 110 ? 110 : n.size.height);
    case NodeShape.pill:
      return Size(n.size.width < 150 ? 170 : n.size.width, 44);
    default:
      if (from == NodeShape.circle ||
          from == NodeShape.pill ||
          from == NodeShape.diamond) {
        final s = sizeFor(n.type);
        return s.width < 120 ? const Size(190, 72) : s;
      }
      return n.size;
  }
}

/// Diálogo para cambiar forma, color, icono, relleno y borde de [ids].
Future<void> showNodeStyleDialog(
    BuildContext context,
    NodeEditorController<Item> controller,
    List<String> ids,
    NodeEditorTheme theme) async {
  final first = controller.node(ids.first);
  if (first == null) return;
  final resolved = theme.resolveNodeStyle(first);
  var shape = resolved.shape;
  var color = first.color;
  var icon = first.style?.icon;
  var filled = resolved.filled;
  var border = resolved.borderStyle;

  NodeData<Item> styled(NodeData<Item> n) {
    final from = theme.shapeOf(n);
    return n.copyWith(
      style: NodeStyle(
          shape: shape, icon: icon, filled: filled, borderStyle: border),
      clearStyle: false,
      color: color,
      clearColor: color == null,
      size: sizeForShape(n, from, shape),
    );
  }

  final apply = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(builder: (context, setState) {
      final preview = styled(first);
      Widget section(String title, Widget child) => Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 6),
                child,
              ],
            ),
          );
      return AlertDialog(
        title: Text(ids.length == 1
            ? 'Estilo de "${first.title}"'
            : 'Estilo de ${ids.length} nodos'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Vista previa con el mismo widget que usa el editor.
              Container(
                height: 150,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: theme.backgroundColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: FittedBox(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: SizedBox.fromSize(
                      size: preview.size,
                      child: NodeEditorScope(
                        theme: theme,
                        child: DefaultNodeBody(
                          node: preview,
                          state: const NodeViewState(),
                          theme: theme,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      section(
                        'Forma',
                        Wrap(spacing: 6, runSpacing: 6, children: [
                          for (final e in _shapeNames.entries)
                            ChoiceChip(
                              avatar: Icon(e.value.$2, size: 16),
                              label: Text(e.value.$1),
                              selected: shape == e.key,
                              onSelected: (_) => setState(() => shape = e.key),
                            ),
                        ]),
                      ),
                      section(
                        'Color',
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          _Swatch(
                            color: null,
                            selected: color == null,
                            onTap: () => setState(() => color = null),
                          ),
                          for (final c in _palette)
                            _Swatch(
                              color: c,
                              selected: color == c,
                              onTap: () => setState(() => color = c),
                            ),
                        ]),
                      ),
                      section(
                        'Icono',
                        Wrap(spacing: 4, runSpacing: 4, children: [
                          _IconTile(
                            selected: icon == null,
                            onTap: () => setState(() => icon = null),
                            child: const Text('Auto',
                                style: TextStyle(fontSize: 11)),
                          ),
                          for (final e in theme.icons.entries)
                            _IconTile(
                              selected: icon == e.key,
                              tooltip: e.key,
                              onTap: () => setState(() => icon = e.key),
                              child: Icon(e.value, size: 18),
                            ),
                        ]),
                      ),
                      section(
                        'Relleno',
                        Wrap(spacing: 6, children: [
                          ChoiceChip(
                            label: const Text('Relleno'),
                            selected: filled,
                            onSelected: (_) => setState(() => filled = true),
                          ),
                          ChoiceChip(
                            label: const Text('Solo líneas'),
                            selected: !filled,
                            onSelected: (_) => setState(() => filled = false),
                          ),
                        ]),
                      ),
                      section(
                        'Borde',
                        Wrap(spacing: 6, runSpacing: 6, children: [
                          for (final e in _borderNames.entries)
                            ChoiceChip(
                              label: Text(e.value),
                              selected: border == e.key,
                              onSelected: (_) => setState(() => border = e.key),
                            ),
                        ]),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              // Vuelve al aspecto de su tipo.
              controller.transaction(() {
                for (final id in ids) {
                  controller.updateNode(
                      id,
                      (n) => n.copyWith(
                            clearStyle: true,
                            clearColor: true,
                            size: sizeForShape(n, theme.shapeOf(n),
                                theme.styleFor(n.type).shape ?? NodeShape.card),
                          ));
                }
              });
              Navigator.pop(context, false);
            },
            child: const Text('Restablecer'),
          ),
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Aplicar')),
        ],
      );
    }),
  );
  if (apply != true) return;
  controller.transaction(() {
    for (final id in ids) {
      controller.updateNode(id, styled);
    }
  });
}

class _Swatch extends StatelessWidget {
  const _Swatch(
      {required this.color, required this.selected, required this.onTap});

  final Color? color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: color == null ? 'Color del tipo' : '',
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
                color: selected ? scheme.onSurface : scheme.outlineVariant,
                width: selected ? 3 : 1),
          ),
          child: color == null
              ? Icon(Icons.auto_awesome, size: 14, color: scheme.onSurface)
              : null,
        ),
      ),
    );
  }
}

class _IconTile extends StatelessWidget {
  const _IconTile({
    required this.selected,
    required this.onTap,
    required this.child,
    this.tooltip,
  });

  final bool selected;
  final VoidCallback onTap;
  final Widget child;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tile = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? scheme.primaryContainer : null,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant),
        ),
        child: child,
      ),
    );
    return tooltip == null ? tile : Tooltip(message: tooltip!, child: tile);
  }
}
