import 'package:flutter/material.dart';

import '../geometry/node_geometry.dart';
import '../model/node.dart';
import '../model/port.dart';
import '../theme/node_editor_theme.dart';
import 'editor_config.dart';

/// Tarjeta de nodo por defecto: cabecera con tipo/icono, título, subtítulo y
/// botón de colapso cuando tiene hijos.
///
/// Puedes reutilizarla en tu `nodeBuilder` y añadir contenido propio con
/// [content].
class DefaultNodeBody extends StatelessWidget {
  const DefaultNodeBody({
    super.key,
    required this.node,
    required this.state,
    this.theme,
    this.content,
    this.trailing,
  });

  final NodeData<Object?> node;
  final NodeViewState state;
  final NodeEditorTheme? theme;

  /// Contenido adicional bajo el título.
  final Widget? content;

  /// Widget extra en la esquina superior derecha.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = theme ?? NodeEditorScope.themeOf(context);
    final typeStyle = t.styleFor(node.type);
    final accent = t.accentFor(node.type, node.color);
    final borderColor = state.dropTarget
        ? t.dropTargetColor
        : state.selected
            ? t.nodeSelectedBorderColor
            : (typeStyle.borderColor ?? t.nodeBorderColor);
    final borderWidth = state.selected || state.dropTarget
        ? t.nodeSelectedBorderWidth
        : t.nodeBorderWidth;
    final compact = node.size.height < t.nodeHeaderHeight + 32;
    // Si hay etiquetas de puertos a los lados, el área inferior queda para
    // ellas y el título/subtítulo se muestran en la cabecera.
    final sideLabels = t.showPortLabels &&
        node.ports.any((p) =>
            p.label != null &&
            (p.side == PortSide.left || p.side == PortSide.right));
    final titleStyle = typeStyle.titleColor == null
        ? t.nodeTitleStyle
        : t.nodeTitleStyle.copyWith(color: typeStyle.titleColor);

    final collapse = state.hasChildren
        ? _CollapseBadge(
            count: state.childCount,
            collapsed: node.collapsed,
            theme: t,
            onTap: state.onToggleCollapsed,
          )
        : null;

    Widget body;
    if (compact) {
      body = Padding(
        padding: EdgeInsets.symmetric(horizontal: t.nodePadding.left),
        child: Row(
          children: [
            if (typeStyle.icon != null) ...[
              Icon(typeStyle.icon, size: 16, color: accent),
              const SizedBox(width: 8),
            ] else ...[
              _Dot(color: accent),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(node.title,
                      style: titleStyle,
                      maxLines: node.autoSize ? null : 1,
                      overflow: node.autoSize ? null : TextOverflow.ellipsis),
                  if (node.subtitle != null)
                    Text(node.subtitle!,
                        style: t.nodeSubtitleStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (trailing != null) trailing!,
            if (collapse != null) ...[const SizedBox(width: 6), collapse],
          ],
        ),
      );
    } else {
      final details = Padding(
        padding: t.nodePadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!sideLabels)
              Text(
                node.subtitle == null ? node.title : node.subtitle!,
                style: node.subtitle == null ? titleStyle : t.nodeSubtitleStyle,
                maxLines: node.autoSize ? null : 2,
                overflow: node.autoSize ? null : TextOverflow.ellipsis,
              ),
            if (content != null) ...[
              if (!sideLabels) const SizedBox(height: 6),
              content!,
            ],
          ],
        ),
      );
      final Widget headerText;
      if (sideLabels) {
        headerText = Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(node.title,
                style: titleStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            if (node.subtitle != null)
              Text(node.subtitle!,
                  style: t.nodeSubtitleStyle.copyWith(
                      fontSize: (t.nodeSubtitleStyle.fontSize ?? 11.5) - 1),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
          ],
        );
      } else {
        headerText = Text(
          node.subtitle == null
              ? (typeStyle.label ?? node.type).toUpperCase()
              : node.title,
          style: node.subtitle == null ? t.nodeTypeLabelStyle : titleStyle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      }
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: t.nodeHeaderHeight,
            padding: EdgeInsets.symmetric(horizontal: t.nodePadding.left),
            decoration: BoxDecoration(
              color: typeStyle.headerColor ?? t.nodeHeaderColor,
              border: Border(
                  bottom: BorderSide(
                      color: t.nodeBorderColor.withValues(alpha: 0.6))),
            ),
            child: Row(
              children: [
                if (typeStyle.icon != null)
                  Icon(typeStyle.icon, size: 15, color: accent)
                else
                  _Dot(color: accent),
                const SizedBox(width: 8),
                Expanded(child: headerText),
                if (trailing != null) trailing!,
                if (collapse != null) collapse,
              ],
            ),
          ),
          if (node.autoSize)
            details
          else
            // Con tamaño fijo el contenido nunca desborda: se recorta.
            Expanded(
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.topLeft,
                  minHeight: 0,
                  maxHeight: double.infinity,
                  child: details,
                ),
              ),
            ),
        ],
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: typeStyle.backgroundColor ?? t.nodeColor,
        borderRadius: BorderRadius.circular(t.nodeRadius),
        border: Border.all(color: borderColor, width: borderWidth),
        boxShadow: t.nodeShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(
            (t.nodeRadius - borderWidth).clamp(0, double.infinity)),
        child: body,
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

class _CollapseBadge extends StatelessWidget {
  const _CollapseBadge({
    required this.count,
    required this.collapsed,
    required this.theme,
    this.onTap,
  });

  final int count;
  final bool collapsed;
  final NodeEditorTheme theme;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: collapsed
              ? theme.badgeColor
              : theme.badgeColor.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              collapsed ? Icons.chevron_right : Icons.expand_more,
              size: 12,
              color: collapsed ? theme.badgeTextStyle.color : theme.badgeColor,
            ),
            Text(
              '$count',
              style: collapsed
                  ? theme.badgeTextStyle
                  : theme.badgeTextStyle.copyWith(color: theme.badgeColor),
            ),
          ],
        ),
      ),
    );
  }
}

/// Envuelve el cuerpo de un nodo y dibuja sus puertos encima.
class NodeFrame extends StatelessWidget {
  const NodeFrame({
    super.key,
    required this.node,
    required this.state,
    required this.theme,
    required this.child,
    this.showPorts = true,
  });

  final NodeData<Object?> node;
  final NodeViewState state;
  final NodeEditorTheme theme;
  final Widget child;
  final bool showPorts;

  @override
  Widget build(BuildContext context) {
    if (!showPorts || node.ports.isEmpty) return child;
    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.passthrough,
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _PortsPainter(
                node: node,
                connected: state.connectedPorts,
                theme: theme,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PortsPainter extends CustomPainter {
  _PortsPainter({
    required this.node,
    required this.connected,
    required this.theme,
  });

  final NodeData<Object?> node;
  final Set<String> connected;
  final NodeEditorTheme theme;

  static final Paint _fill = Paint();
  static final Paint _stroke = Paint()..style = PaintingStyle.stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final r = theme.portRadius;
    _stroke.strokeWidth = 1.5;
    for (final port in node.ports) {
      final p = NodeGeometry.portLocalPosition(node, size, port.id,
          topInset: theme.nodeHeaderHeight);
      final color = port.color ?? theme.portColor;
      final isConnected = connected.contains(port.id);
      _fill.color = isConnected ? color : theme.portFillColor;
      canvas.drawCircle(p, r, _fill);
      _stroke.color = color;
      canvas.drawCircle(p, r, _stroke);
      if (theme.showPortLabels && port.label != null) {
        _paintLabel(canvas, size, p, port);
      }
    }
  }

  void _paintLabel(Canvas canvas, Size size, Offset p, NodePort port) {
    final tp = TextPainter(
      text: TextSpan(text: port.label, style: theme.portLabelStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: size.width / 2 - 14);
    final gap = theme.portRadius + 6;
    final Offset at;
    switch (port.side) {
      case PortSide.left:
        at = Offset(p.dx + gap, p.dy - tp.height / 2);
      case PortSide.right:
        at = Offset(p.dx - gap - tp.width, p.dy - tp.height / 2);
      case PortSide.top:
        at = Offset(p.dx - tp.width / 2, p.dy + gap - 2);
      case PortSide.bottom:
        at = Offset(p.dx - tp.width / 2, p.dy - gap - tp.height + 2);
    }
    tp.paint(canvas, at);
    tp.dispose();
  }

  @override
  bool shouldRepaint(_PortsPainter old) =>
      !identical(old.node.ports, node.ports) ||
      old.node.size != node.size ||
      !identical(old.theme, theme) ||
      old.connected.length != connected.length ||
      !old.connected.containsAll(connected);
}

/// Da acceso al tema efectivo dentro de los nodos.
class NodeEditorScope extends InheritedWidget {
  const NodeEditorScope({super.key, required this.theme, required super.child});

  final NodeEditorTheme theme;

  static NodeEditorTheme themeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NodeEditorScope>()?.theme ??
      NodeEditorTheme.of(context);

  @override
  bool updateShouldNotify(NodeEditorScope oldWidget) =>
      !identical(oldWidget.theme, theme);
}
