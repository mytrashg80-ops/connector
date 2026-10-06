import 'package:connector/connector.dart';
import 'package:flutter/material.dart';

import 'scenarios.dart';

/// `nodeBuilder` del ejemplo: tarjetas propias para algunos tipos y la
/// tarjeta por defecto (devolviendo `null`) para el resto.
Widget? buildNodeCard(
    BuildContext context, NodeData<Item> node, NodeViewState state) {
  switch (node.type) {
    case 'employee':
      return _EmployeeCard(node: node, state: state);
    case 'product':
      final stock = (node.data?['stock'] as int?) ?? 0;
      final max = (node.data?['max'] as int?) ?? 100;
      return DefaultNodeBody(
        node: node,
        state: state,
        content: _StockBar(stock: stock, max: max),
      );
    case 'idea':
      return _IdeaBubble(node: node, state: state);
  }
  return null;
}

class _EmployeeCard extends StatelessWidget {
  const _EmployeeCard({required this.node, required this.state});

  final NodeData<Item> node;
  final NodeViewState state;

  @override
  Widget build(BuildContext context) {
    final t = NodeEditorScope.themeOf(context);
    final accent = t.accentFor(node.type, node.color);
    final initials = node.title
        .split(' ')
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0])
        .join();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.nodeColor,
        borderRadius: BorderRadius.circular(t.nodeRadius),
        border: Border.all(
          color: state.dropTarget
              ? t.dropTargetColor
              : state.selected
                  ? t.nodeSelectedBorderColor
                  : t.nodeBorderColor,
          width: state.selected || state.dropTarget ? 2 : 1,
        ),
        boxShadow: t.nodeShadow,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: accent.withValues(alpha: 0.18),
              child: Text(initials,
                  style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w700,
                      fontSize: 13)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(node.title,
                      style: t.nodeTitleStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(node.subtitle ?? '',
                      style: t.nodeSubtitleStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (state.hasChildren)
              GestureDetector(
                onTap: state.onToggleCollapsed,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: node.collapsed
                        ? accent
                        : accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    node.collapsed
                        ? '+${state.childCount}'
                        : '${state.childCount}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: node.collapsed ? Colors.white : accent,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StockBar extends StatelessWidget {
  const _StockBar({required this.stock, required this.max});

  final int stock;
  final int max;

  @override
  Widget build(BuildContext context) {
    final t = NodeEditorScope.themeOf(context);
    final ratio = max == 0 ? 0.0 : (stock / max).clamp(0.0, 1.0);
    final color = ratio < 0.2
        ? const Color(0xFFEF4444)
        : ratio < 0.5
            ? const Color(0xFFF59E0B)
            : const Color(0xFF22C55E);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 6,
            child: Stack(children: [
              Positioned.fill(child: ColoredBox(color: t.nodeBorderColor)),
              FractionallySizedBox(
                widthFactor: ratio,
                child: ColoredBox(color: color),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 4),
        Text('Stock $stock / $max',
            style: t.nodeSubtitleStyle.copyWith(fontSize: 11)),
      ],
    );
  }
}

class _IdeaBubble extends StatelessWidget {
  const _IdeaBubble({required this.node, required this.state});

  final NodeData<Item> node;
  final NodeViewState state;

  @override
  Widget build(BuildContext context) {
    final t = NodeEditorScope.themeOf(context);
    final isRoot = node.parentId == null;
    final accent = node.color ?? t.accentColor;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: isRoot ? 14 : 10),
      decoration: BoxDecoration(
        color: isRoot ? accent : t.nodeColor,
        borderRadius: BorderRadius.circular(isRoot ? 14 : 22),
        border: Border.all(
          color: state.selected ? t.nodeSelectedBorderColor : accent,
          width: state.selected ? 2.5 : 1.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              node.title,
              style: t.nodeTitleStyle.copyWith(
                color: isRoot ? Colors.white : null,
                fontSize: isRoot ? 16 : 13,
              ),
            ),
          ),
          if (state.hasChildren) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: state.onToggleCollapsed,
              child: Icon(
                node.collapsed ? Icons.add_circle : Icons.remove_circle_outline,
                size: 16,
                color: isRoot ? Colors.white : accent,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
