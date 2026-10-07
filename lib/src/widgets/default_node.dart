import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../geometry/edge_path.dart';
import '../geometry/node_shapes.dart';
import '../model/node.dart';
import '../model/node_style.dart';
import '../model/port.dart';
import '../theme/node_editor_theme.dart';
import 'editor_config.dart';

/// Nodo por defecto. Según su forma ([NodeStyle.shape] o la de su tipo):
/// tarjeta con cabecera, caja, píldora, círculo con icono, rombo o
/// hexágono; rellenos o sólo líneas, con borde sólido, discontinuo o
/// punteado. Muestra el botón de colapso cuando tiene hijos.
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
    final st = t.resolveNodeStyle(node);
    final accent = st.accent;
    final highlighted = state.selected || state.dropTarget;
    final borderColor = state.dropTarget
        ? t.dropTargetColor
        : state.selected
            ? t.nodeSelectedBorderColor
            : st.borderColor;
    final borderWidth = highlighted
        ? math.max(t.nodeSelectedBorderWidth, st.borderWidth)
        : st.borderWidth;
    final painter = NodeShapePainter(
      shape: st.shape,
      fillColor: st.fillColor,
      borderColor: borderColor,
      borderWidth: borderWidth,
      // Seleccionado se ve aunque no tenga borde.
      borderStyle: highlighted && st.borderStyle == NodeBorderStyle.none
          ? NodeBorderStyle.solid
          : st.borderStyle,
      radius: st.radius,
      shadows: st.filled ? t.nodeShadow : const [],
    );
    final compact = node.size.height < t.nodeHeaderHeight + 32;
    // Si hay etiquetas de puertos a los lados, el área inferior queda para
    // ellas y el título/subtítulo se muestran en la cabecera.
    final sideLabels = t.showPortLabels &&
        node.ports.any((p) =>
            p.label != null &&
            (p.side == PortSide.left || p.side == PortSide.right));
    final titleStyle = t.nodeTitleStyle.copyWith(color: st.textColor);

    final collapse = state.hasChildren
        ? _CollapseBadge(
            count: state.childCount,
            collapsed: node.collapsed,
            theme: t,
            onTap: state.onToggleCollapsed,
          )
        : null;

    if (st.shape != NodeShape.card) {
      return _ShapeBody(
        node: node,
        style: st,
        painter: painter,
        theme: t,
        titleStyle: titleStyle,
        collapse: collapse,
      );
    }

    Widget body;
    if (compact) {
      body = Padding(
        padding: EdgeInsets.symmetric(horizontal: t.nodePadding.left),
        child: Row(
          children: [
            if (st.icon != null) ...[
              Icon(st.icon, size: 16, color: accent),
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
              color: st.filled
                  ? (typeStyle.headerColor ?? t.nodeHeaderColor)
                  : null,
              border: Border(
                  bottom: BorderSide(
                      color: (st.filled ? t.nodeBorderColor : st.borderColor)
                          .withValues(alpha: 0.6))),
            ),
            child: Row(
              children: [
                if (st.icon != null)
                  Icon(st.icon, size: 15, color: accent)
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

    // El borde va por encima del contenido (la cabecera no lo tapa).
    return CustomPaint(
      painter: painter.only(fill: true),
      foregroundPainter: painter.only(border: true),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(
            (st.radius - borderWidth / 2).clamp(0, double.infinity)),
        child: body,
      ),
    );
  }
}

/// Nodos que no son tarjeta: caja, píldora, círculo, rombo y hexágono.
class _ShapeBody extends StatelessWidget {
  const _ShapeBody({
    required this.node,
    required this.style,
    required this.painter,
    required this.theme,
    required this.titleStyle,
    required this.collapse,
  });

  final NodeData<Object?> node;
  final ResolvedNodeStyle style;
  final NodeShapePainter painter;
  final NodeEditorTheme theme;
  final TextStyle titleStyle;
  final Widget? collapse;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.hasBoundedWidth ? c.maxWidth : node.size.width;
      final h = c.hasBoundedHeight ? c.maxHeight : node.size.height;
      return style.shape == NodeShape.circle
          ? _circle(Size(w, h))
          : _other(Size(w, h));
    });
  }

  Widget _circle(Size size) {
    final body = NodeShapes.bodyRect(NodeShape.circle, size);
    final d = body.width;
    final caption = size.height - d;
    final icon = style.icon;
    final initial = node.title.isEmpty ? '?' : node.title.characters.first;
    return SizedBox.fromSize(
      size: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fromRect(
            rect: body,
            child: CustomPaint(
              painter: painter,
              child: Center(
                child: icon != null
                    ? Icon(icon,
                        size: (d * 0.44).clamp(12.0, 72.0), color: style.accent)
                    : Text(initial.toUpperCase(),
                        style: titleStyle.copyWith(
                            color: style.accent,
                            fontSize: (d * 0.38).clamp(10.0, 48.0))),
              ),
            ),
          ),
          if (caption >= 14)
            Positioned(
              left: -12,
              right: -12,
              top: d + 3,
              bottom: 0,
              child: Text(
                node.title,
                textAlign: TextAlign.center,
                maxLines: caption >= 34 ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                style: titleStyle.copyWith(
                    fontSize: math.min(titleStyle.fontSize ?? 13, 12)),
              ),
            ),
          if (collapse != null)
            Positioned(left: body.right - 14, top: -6, child: collapse!),
        ],
      ),
    );
  }

  Widget _other(Size size) {
    final t = theme;
    final shape = style.shape;
    final diamond = shape == NodeShape.diamond;
    final padding = switch (shape) {
      NodeShape.pill => EdgeInsets.symmetric(
          horizontal: math.max(t.nodePadding.left, size.height * 0.4),
          vertical: 4),
      NodeShape.diamond => EdgeInsets.symmetric(
          horizontal: size.width * 0.2, vertical: size.height * 0.16),
      NodeShape.hexagon => EdgeInsets.symmetric(
          horizontal: math.min(size.width * 0.25, size.height * 0.29) + 4,
          vertical: 4),
      _ => t.nodePadding,
    };
    final showSubtitle = !diamond && node.subtitle != null && size.height >= 52;
    final texts = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
          diamond ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Text(node.title,
            style: titleStyle,
            textAlign: diamond ? TextAlign.center : TextAlign.start,
            maxLines: node.autoSize ? null : 2,
            overflow: node.autoSize ? null : TextOverflow.ellipsis),
        if (showSubtitle)
          Text(node.subtitle!,
              style: t.nodeSubtitleStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
      ],
    );
    final icon = style.icon == null
        ? null
        : Icon(style.icon, size: diamond ? 16 : 18, color: style.accent);
    final content = diamond
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[icon, const SizedBox(height: 2)],
              Flexible(child: texts),
            ],
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[icon, const SizedBox(width: 8)],
              Flexible(child: texts),
            ],
          );
    return CustomPaint(
      painter: painter,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Padding(
              padding: padding,
              child: Center(child: content),
            ),
          ),
          if (collapse != null)
            Positioned(
              right: diamond ? size.width * 0.12 : 6,
              top: diamond ? size.height * 0.12 : 6,
              child: collapse!,
            ),
        ],
      ),
    );
  }
}

/// Pinta la silueta de un nodo: relleno, sombra y borde (sólido,
/// discontinuo o punteado). Útil también en tus propios `nodeBuilder`.
class NodeShapePainter extends CustomPainter {
  NodeShapePainter({
    required this.shape,
    required this.fillColor,
    required this.borderColor,
    required this.borderWidth,
    this.borderStyle = NodeBorderStyle.solid,
    this.radius = 10,
    this.shadows = const [],
    this.paintFill = true,
    this.paintBorder = true,
  });

  final NodeShape shape;
  final Color fillColor;
  final Color borderColor;
  final double borderWidth;
  final NodeBorderStyle borderStyle;
  final double radius;
  final List<BoxShadow> shadows;

  /// Para pintar el relleno debajo del contenido y el borde encima.
  final bool paintFill;
  final bool paintBorder;

  /// Copia que sólo pinta el relleno (y la sombra) o sólo el borde.
  NodeShapePainter only({bool fill = false, bool border = false}) =>
      NodeShapePainter(
        shape: shape,
        fillColor: fillColor,
        borderColor: borderColor,
        borderWidth: borderWidth,
        borderStyle: borderStyle,
        radius: radius,
        shadows: shadows,
        paintFill: fill,
        paintBorder: border,
      );

  @override
  void paint(Canvas canvas, Size size) {
    final rect = NodeShapes.bodyRect(shape, size).deflate(borderWidth / 2);
    final path = NodeShapes.path(shape, rect, radius);
    if (paintFill) _paintFill(canvas, path);
    if (paintBorder) _paintBorder(canvas, path);
  }

  void _paintFill(Canvas canvas, Path path) {
    for (final s in shadows) {
      canvas.drawPath(
        path.shift(s.offset),
        Paint()
          ..color = s.color
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, s.blurSigma),
      );
    }
    if (fillColor.a > 0) {
      canvas.drawPath(path, Paint()..color = fillColor);
    }
  }

  void _paintBorder(Canvas canvas, Path path) {
    if (borderStyle == NodeBorderStyle.none || borderWidth <= 0) return;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth
      ..color = borderColor
      ..strokeCap = borderStyle == NodeBorderStyle.dotted
          ? StrokeCap.round
          : StrokeCap.butt
      ..strokeJoin = StrokeJoin.round;
    final w = borderWidth;
    final outline = switch (borderStyle) {
      NodeBorderStyle.dashed => dashPath(path, [w * 4 + 2, w * 2 + 2]),
      NodeBorderStyle.dotted => dashPath(path, [0.01, w * 2.5 + 1]),
      _ => path,
    };
    canvas.drawPath(outline, stroke);
  }

  @override
  bool shouldRepaint(NodeShapePainter old) =>
      old.shape != shape ||
      old.fillColor != fillColor ||
      old.borderColor != borderColor ||
      old.borderWidth != borderWidth ||
      old.borderStyle != borderStyle ||
      old.radius != radius ||
      old.paintFill != paintFill ||
      old.paintBorder != paintBorder ||
      !listEquals(old.shadows, shadows);
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
      final p = theme.portLocalPosition(node, size, port.id);
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
