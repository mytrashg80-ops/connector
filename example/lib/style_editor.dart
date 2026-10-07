import 'package:connector/connector.dart';
import 'package:flutter/material.dart';

import 'node_cards.dart';
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

/// Diálogo de la aplicación para cambiar forma, color, icono, relleno y
/// borde de [ids].
///
/// Del paquete sólo usamos herramientas: las opciones ([NodeShape.values],
/// [NodeBorderStyle.values], `theme.icons`), la vista previa ([NodePreview])
/// y `controller.setNodeStyle` / `resetNodeStyle`, que aplican el cambio en
/// un solo paso de deshacer.
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

  NodeStyle style() =>
      NodeStyle(shape: shape, icon: icon, filled: filled, borderStyle: border);

  // Al cambiar de forma ajustamos el tamaño (un círculo necesita ser más alto
  // que ancho para el título, un rombo algo de aire…).
  Size resize(NodeData<Item> n, NodeShape to) =>
      NodeShapes.suggestedSize(to, n.size, from: theme.shapeOf(n));

  final apply = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(builder: (context, setState) {
      final preview = first.copyWith(
        style: style(),
        color: color,
        clearColor: color == null,
        size: resize(first, shape),
      );
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
                padding: const EdgeInsets.all(20),
                child: NodePreview<Item>(
                  node: preview,
                  theme: theme,
                  nodeBuilder: buildNodeCard,
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
              controller.resetNodeStyle(ids,
                  resize: (n) => resize(
                      n, theme.styleFor(n.type).shape ?? NodeShape.card));
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
  controller.setNodeStyle(
    ids,
    style(),
    color: color,
    clearColor: color == null,
    resize: (n) => resize(n, shape),
  );
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
