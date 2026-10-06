import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../model/edge.dart';

/// Estilo de la rejilla de fondo.
enum GridStyle { dots, lines, none }

/// Estilo visual por tipo de nodo (`NodeData.type`).
@immutable
class NodeTypeStyle {
  const NodeTypeStyle({
    this.label,
    this.icon,
    this.color,
    this.backgroundColor,
    this.headerColor,
    this.borderColor,
    this.titleColor,
  });

  /// Texto pequeño de la cabecera (p. ej. "Empleado"). `null` = tipo.
  final String? label;
  final IconData? icon;

  /// Color de acento (indicador, icono, conexiones jerárquicas...).
  final Color? color;
  final Color? backgroundColor;
  final Color? headerColor;
  final Color? borderColor;
  final Color? titleColor;
}

/// Tema completo del editor. Todos los colores y medidas son configurables.
///
/// Se puede pasar directamente al `NodeEditor`, registrar como
/// `ThemeExtension` en tu `ThemeData`, o dejar que el editor elija
/// [NodeEditorTheme.light] / [NodeEditorTheme.dark] según el brillo actual.
@immutable
class NodeEditorTheme extends ThemeExtension<NodeEditorTheme> {
  const NodeEditorTheme({
    required this.brightness,
    required this.backgroundColor,
    this.gridStyle = GridStyle.dots,
    required this.gridColor,
    required this.gridMajorColor,
    this.gridSpacing = 24,
    this.gridMajorEvery = 5,
    required this.nodeColor,
    required this.nodeHeaderColor,
    required this.nodeBorderColor,
    this.nodeBorderWidth = 1,
    required this.nodeSelectedBorderColor,
    this.nodeSelectedBorderWidth = 2,
    this.nodeRadius = 10,
    this.nodeShadow = const [],
    this.nodeHeaderHeight = 40,
    this.nodePadding = const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    required this.nodeTitleStyle,
    required this.nodeSubtitleStyle,
    required this.nodeTypeLabelStyle,
    required this.accentColor,
    required this.portColor,
    required this.portFillColor,
    this.portRadius = 5,
    this.portHitRadius = 14,
    required this.portLabelStyle,
    this.showPortLabels = true,
    required this.edgeColor,
    this.edgeWidth = 2,
    required this.edgeSelectedColor,
    this.edgeCurve = EdgeCurve.bezier,
    this.edgeDashed = false,
    this.edgeDashPattern = const [6, 5],
    this.edgeArrow = false,
    this.edgeArrowSize = 9,
    this.edgeCornerRadius = 12,
    this.edgeHitWidth = 10,
    required this.edgeLabelBackground,
    required this.edgeLabelBorderColor,
    required this.edgeLabelStyle,
    required this.hierarchyEdgeColor,
    this.hierarchyEdgeWidth = 1.6,
    this.hierarchyEdgeCurve = EdgeCurve.smoothStep,
    this.hierarchyEdgeDashed = false,
    required this.connectionPreviewColor,
    required this.invalidConnectionColor,
    required this.selectionFillColor,
    required this.selectionBorderColor,
    required this.dropTargetColor,
    required this.minimapBackground,
    required this.minimapNodeColor,
    required this.minimapSelectedNodeColor,
    required this.minimapViewportColor,
    required this.minimapBorderColor,
    required this.controlsBackground,
    required this.controlsForeground,
    required this.controlsBorderColor,
    required this.badgeColor,
    required this.badgeTextStyle,
    this.nodeTypes = const {},
  });

  final Brightness brightness;

  // Fondo y rejilla
  final Color backgroundColor;
  final GridStyle gridStyle;
  final Color gridColor;
  final Color gridMajorColor;
  final double gridSpacing;
  final int gridMajorEvery;

  // Nodos
  final Color nodeColor;
  final Color nodeHeaderColor;
  final Color nodeBorderColor;
  final double nodeBorderWidth;
  final Color nodeSelectedBorderColor;
  final double nodeSelectedBorderWidth;
  final double nodeRadius;
  final List<BoxShadow> nodeShadow;

  /// Altura de la cabecera. Los puertos de los lados izquierdo/derecho se
  /// reparten por debajo de ella.
  final double nodeHeaderHeight;
  final EdgeInsets nodePadding;
  final TextStyle nodeTitleStyle;
  final TextStyle nodeSubtitleStyle;
  final TextStyle nodeTypeLabelStyle;
  final Color accentColor;

  // Puertos
  final Color portColor;
  final Color portFillColor;
  final double portRadius;
  final double portHitRadius;
  final TextStyle portLabelStyle;
  final bool showPortLabels;

  // Conexiones
  final Color edgeColor;
  final double edgeWidth;
  final Color edgeSelectedColor;
  final EdgeCurve edgeCurve;
  final bool edgeDashed;
  final List<double> edgeDashPattern;
  final bool edgeArrow;
  final double edgeArrowSize;
  final double edgeCornerRadius;
  final double edgeHitWidth;
  final Color edgeLabelBackground;
  final Color edgeLabelBorderColor;
  final TextStyle edgeLabelStyle;

  // Enlaces de jerarquía (padre → hijo)
  final Color hierarchyEdgeColor;
  final double hierarchyEdgeWidth;
  final EdgeCurve hierarchyEdgeCurve;
  final bool hierarchyEdgeDashed;

  // Interacción
  final Color connectionPreviewColor;
  final Color invalidConnectionColor;
  final Color selectionFillColor;
  final Color selectionBorderColor;
  final Color dropTargetColor;

  // Minimapa
  final Color minimapBackground;
  final Color minimapNodeColor;
  final Color minimapSelectedNodeColor;
  final Color minimapViewportColor;
  final Color minimapBorderColor;

  // Controles
  final Color controlsBackground;
  final Color controlsForeground;
  final Color controlsBorderColor;

  // Insignias (contador de hijos ocultos)
  final Color badgeColor;
  final TextStyle badgeTextStyle;

  /// Estilos por tipo de nodo.
  final Map<String, NodeTypeStyle> nodeTypes;

  NodeTypeStyle styleFor(String type) =>
      nodeTypes[type] ?? const NodeTypeStyle();

  /// Color de acento efectivo de un nodo.
  Color accentFor(String type, [Color? override]) =>
      override ?? nodeTypes[type]?.color ?? accentColor;

  /// Tema claro por defecto (inspirado en editores tipo "workflow").
  factory NodeEditorTheme.light({
    Color accent = const Color(0xFF6366F1),
    Map<String, NodeTypeStyle> nodeTypes = const {},
  }) {
    const text = Color(0xFF111827);
    const muted = Color(0xFF6B7280);
    return NodeEditorTheme(
      brightness: Brightness.light,
      backgroundColor: const Color(0xFFF7F8FA),
      gridColor: const Color(0xFFD5D9E0),
      gridMajorColor: const Color(0xFFBFC5CF),
      nodeColor: Colors.white,
      nodeHeaderColor: const Color(0xFFF9FAFB),
      nodeBorderColor: const Color(0xFFE5E7EB),
      nodeSelectedBorderColor: accent,
      nodeShadow: const [
        BoxShadow(
            color: Color(0x14000000), blurRadius: 8, offset: Offset(0, 2)),
      ],
      nodeTitleStyle: const TextStyle(
          color: text,
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
          height: 1.2),
      nodeSubtitleStyle:
          const TextStyle(color: muted, fontSize: 11.5, height: 1.25),
      nodeTypeLabelStyle: const TextStyle(
          color: muted,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4),
      accentColor: accent,
      portColor: const Color(0xFF9CA3AF),
      portFillColor: Colors.white,
      portLabelStyle: const TextStyle(color: muted, fontSize: 10.5),
      edgeColor: const Color(0xFF94A3B8),
      edgeSelectedColor: accent,
      edgeLabelBackground: Colors.white,
      edgeLabelBorderColor: const Color(0xFFCBD5E1),
      edgeLabelStyle: const TextStyle(
          color: Color(0xFF334155), fontSize: 11, fontWeight: FontWeight.w500),
      hierarchyEdgeColor: const Color(0xFFA5B4C8),
      connectionPreviewColor: accent,
      invalidConnectionColor: const Color(0xFFEF4444),
      selectionFillColor: accent.withValues(alpha: 0.08),
      selectionBorderColor: accent.withValues(alpha: 0.7),
      dropTargetColor: const Color(0xFF10B981),
      minimapBackground: const Color(0xF2FFFFFF),
      minimapNodeColor: const Color(0xFFCBD5E1),
      minimapSelectedNodeColor: accent,
      minimapViewportColor: accent.withValues(alpha: 0.12),
      minimapBorderColor: const Color(0xFFE5E7EB),
      controlsBackground: Colors.white,
      controlsForeground: const Color(0xFF374151),
      controlsBorderColor: const Color(0xFFE5E7EB),
      badgeColor: accent,
      badgeTextStyle: const TextStyle(
          color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
      nodeTypes: nodeTypes,
    );
  }

  /// Tema oscuro por defecto (inspirado en Unreal / Conveyor).
  factory NodeEditorTheme.dark({
    Color accent = const Color(0xFF8B7CF6),
    Map<String, NodeTypeStyle> nodeTypes = const {},
  }) {
    const text = Color(0xFFF3F4F6);
    const muted = Color(0xFF9CA3AF);
    return NodeEditorTheme(
      brightness: Brightness.dark,
      backgroundColor: const Color(0xFF16171B),
      gridColor: const Color(0xFF2B2D33),
      gridMajorColor: const Color(0xFF3A3D45),
      nodeColor: const Color(0xFF26282E),
      nodeHeaderColor: const Color(0xFF2E3037),
      nodeBorderColor: const Color(0xFF3A3D45),
      nodeSelectedBorderColor: accent,
      nodeShadow: const [],
      nodeTitleStyle: const TextStyle(
          color: text,
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
          height: 1.2),
      nodeSubtitleStyle:
          const TextStyle(color: muted, fontSize: 11.5, height: 1.25),
      nodeTypeLabelStyle: const TextStyle(
          color: muted,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4),
      accentColor: accent,
      portColor: const Color(0xFFA5A8B3),
      portFillColor: const Color(0xFF26282E),
      portLabelStyle: const TextStyle(color: muted, fontSize: 10.5),
      edgeColor: const Color(0xFF8A8F9C),
      edgeSelectedColor: accent,
      edgeLabelBackground: const Color(0xFF26282E),
      edgeLabelBorderColor: const Color(0xFF4B4F59),
      edgeLabelStyle: const TextStyle(
          color: Color(0xFFE5E7EB), fontSize: 11, fontWeight: FontWeight.w500),
      hierarchyEdgeColor: const Color(0xFF5B6070),
      connectionPreviewColor: accent,
      invalidConnectionColor: const Color(0xFFF87171),
      selectionFillColor: accent.withValues(alpha: 0.12),
      selectionBorderColor: accent.withValues(alpha: 0.8),
      dropTargetColor: const Color(0xFF34D399),
      minimapBackground: const Color(0xF21E1F24),
      minimapNodeColor: const Color(0xFF4B4F59),
      minimapSelectedNodeColor: accent,
      minimapViewportColor: accent.withValues(alpha: 0.18),
      minimapBorderColor: const Color(0xFF3A3D45),
      controlsBackground: const Color(0xFF26282E),
      controlsForeground: const Color(0xFFD1D5DB),
      controlsBorderColor: const Color(0xFF3A3D45),
      badgeColor: accent,
      badgeTextStyle: const TextStyle(
          color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
      nodeTypes: nodeTypes,
    );
  }

  /// Deriva un tema a partir del `ColorScheme` de tu app.
  factory NodeEditorTheme.fromColorScheme(
    ColorScheme scheme, {
    Map<String, NodeTypeStyle> nodeTypes = const {},
  }) {
    final base = scheme.brightness == Brightness.dark
        ? NodeEditorTheme.dark(accent: scheme.primary, nodeTypes: nodeTypes)
        : NodeEditorTheme.light(accent: scheme.primary, nodeTypes: nodeTypes);
    return base.copyWith(
      backgroundColor: scheme.surface,
      nodeColor: scheme.surfaceContainerLow,
      nodeHeaderColor: scheme.surfaceContainer,
      nodeBorderColor: scheme.outlineVariant,
      gridColor: scheme.outlineVariant.withValues(alpha: 0.6),
      gridMajorColor: scheme.outlineVariant,
      nodeTitleStyle: base.nodeTitleStyle.copyWith(color: scheme.onSurface),
      nodeSubtitleStyle:
          base.nodeSubtitleStyle.copyWith(color: scheme.onSurfaceVariant),
      portFillColor: scheme.surfaceContainerLow,
      controlsBackground: scheme.surfaceContainerHigh,
      controlsForeground: scheme.onSurface,
      controlsBorderColor: scheme.outlineVariant,
      edgeLabelBackground: scheme.surfaceContainerHigh,
      minimapBackground: scheme.surfaceContainer.withValues(alpha: 0.95),
    );
  }

  /// Tema efectivo: extensión del `Theme` o claro/oscuro según el brillo.
  static NodeEditorTheme of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<NodeEditorTheme>() ??
        (theme.brightness == Brightness.dark ? _defaultDark : _defaultLight);
  }

  // Instancias estables: el editor usa la identidad del tema para decidir si
  // debe invalidar sus cachés.
  static final NodeEditorTheme _defaultLight = NodeEditorTheme.light();
  static final NodeEditorTheme _defaultDark = NodeEditorTheme.dark();

  @override
  NodeEditorTheme copyWith({
    Brightness? brightness,
    Color? backgroundColor,
    GridStyle? gridStyle,
    Color? gridColor,
    Color? gridMajorColor,
    double? gridSpacing,
    int? gridMajorEvery,
    Color? nodeColor,
    Color? nodeHeaderColor,
    Color? nodeBorderColor,
    double? nodeBorderWidth,
    Color? nodeSelectedBorderColor,
    double? nodeSelectedBorderWidth,
    double? nodeRadius,
    List<BoxShadow>? nodeShadow,
    double? nodeHeaderHeight,
    EdgeInsets? nodePadding,
    TextStyle? nodeTitleStyle,
    TextStyle? nodeSubtitleStyle,
    TextStyle? nodeTypeLabelStyle,
    Color? accentColor,
    Color? portColor,
    Color? portFillColor,
    double? portRadius,
    double? portHitRadius,
    TextStyle? portLabelStyle,
    bool? showPortLabels,
    Color? edgeColor,
    double? edgeWidth,
    Color? edgeSelectedColor,
    EdgeCurve? edgeCurve,
    bool? edgeDashed,
    List<double>? edgeDashPattern,
    bool? edgeArrow,
    double? edgeArrowSize,
    double? edgeCornerRadius,
    double? edgeHitWidth,
    Color? edgeLabelBackground,
    Color? edgeLabelBorderColor,
    TextStyle? edgeLabelStyle,
    Color? hierarchyEdgeColor,
    double? hierarchyEdgeWidth,
    EdgeCurve? hierarchyEdgeCurve,
    bool? hierarchyEdgeDashed,
    Color? connectionPreviewColor,
    Color? invalidConnectionColor,
    Color? selectionFillColor,
    Color? selectionBorderColor,
    Color? dropTargetColor,
    Color? minimapBackground,
    Color? minimapNodeColor,
    Color? minimapSelectedNodeColor,
    Color? minimapViewportColor,
    Color? minimapBorderColor,
    Color? controlsBackground,
    Color? controlsForeground,
    Color? controlsBorderColor,
    Color? badgeColor,
    TextStyle? badgeTextStyle,
    Map<String, NodeTypeStyle>? nodeTypes,
  }) {
    return NodeEditorTheme(
      brightness: brightness ?? this.brightness,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      gridStyle: gridStyle ?? this.gridStyle,
      gridColor: gridColor ?? this.gridColor,
      gridMajorColor: gridMajorColor ?? this.gridMajorColor,
      gridSpacing: gridSpacing ?? this.gridSpacing,
      gridMajorEvery: gridMajorEvery ?? this.gridMajorEvery,
      nodeColor: nodeColor ?? this.nodeColor,
      nodeHeaderColor: nodeHeaderColor ?? this.nodeHeaderColor,
      nodeBorderColor: nodeBorderColor ?? this.nodeBorderColor,
      nodeBorderWidth: nodeBorderWidth ?? this.nodeBorderWidth,
      nodeSelectedBorderColor:
          nodeSelectedBorderColor ?? this.nodeSelectedBorderColor,
      nodeSelectedBorderWidth:
          nodeSelectedBorderWidth ?? this.nodeSelectedBorderWidth,
      nodeRadius: nodeRadius ?? this.nodeRadius,
      nodeShadow: nodeShadow ?? this.nodeShadow,
      nodeHeaderHeight: nodeHeaderHeight ?? this.nodeHeaderHeight,
      nodePadding: nodePadding ?? this.nodePadding,
      nodeTitleStyle: nodeTitleStyle ?? this.nodeTitleStyle,
      nodeSubtitleStyle: nodeSubtitleStyle ?? this.nodeSubtitleStyle,
      nodeTypeLabelStyle: nodeTypeLabelStyle ?? this.nodeTypeLabelStyle,
      accentColor: accentColor ?? this.accentColor,
      portColor: portColor ?? this.portColor,
      portFillColor: portFillColor ?? this.portFillColor,
      portRadius: portRadius ?? this.portRadius,
      portHitRadius: portHitRadius ?? this.portHitRadius,
      portLabelStyle: portLabelStyle ?? this.portLabelStyle,
      showPortLabels: showPortLabels ?? this.showPortLabels,
      edgeColor: edgeColor ?? this.edgeColor,
      edgeWidth: edgeWidth ?? this.edgeWidth,
      edgeSelectedColor: edgeSelectedColor ?? this.edgeSelectedColor,
      edgeCurve: edgeCurve ?? this.edgeCurve,
      edgeDashed: edgeDashed ?? this.edgeDashed,
      edgeDashPattern: edgeDashPattern ?? this.edgeDashPattern,
      edgeArrow: edgeArrow ?? this.edgeArrow,
      edgeArrowSize: edgeArrowSize ?? this.edgeArrowSize,
      edgeCornerRadius: edgeCornerRadius ?? this.edgeCornerRadius,
      edgeHitWidth: edgeHitWidth ?? this.edgeHitWidth,
      edgeLabelBackground: edgeLabelBackground ?? this.edgeLabelBackground,
      edgeLabelBorderColor: edgeLabelBorderColor ?? this.edgeLabelBorderColor,
      edgeLabelStyle: edgeLabelStyle ?? this.edgeLabelStyle,
      hierarchyEdgeColor: hierarchyEdgeColor ?? this.hierarchyEdgeColor,
      hierarchyEdgeWidth: hierarchyEdgeWidth ?? this.hierarchyEdgeWidth,
      hierarchyEdgeCurve: hierarchyEdgeCurve ?? this.hierarchyEdgeCurve,
      hierarchyEdgeDashed: hierarchyEdgeDashed ?? this.hierarchyEdgeDashed,
      connectionPreviewColor:
          connectionPreviewColor ?? this.connectionPreviewColor,
      invalidConnectionColor:
          invalidConnectionColor ?? this.invalidConnectionColor,
      selectionFillColor: selectionFillColor ?? this.selectionFillColor,
      selectionBorderColor: selectionBorderColor ?? this.selectionBorderColor,
      dropTargetColor: dropTargetColor ?? this.dropTargetColor,
      minimapBackground: minimapBackground ?? this.minimapBackground,
      minimapNodeColor: minimapNodeColor ?? this.minimapNodeColor,
      minimapSelectedNodeColor:
          minimapSelectedNodeColor ?? this.minimapSelectedNodeColor,
      minimapViewportColor: minimapViewportColor ?? this.minimapViewportColor,
      minimapBorderColor: minimapBorderColor ?? this.minimapBorderColor,
      controlsBackground: controlsBackground ?? this.controlsBackground,
      controlsForeground: controlsForeground ?? this.controlsForeground,
      controlsBorderColor: controlsBorderColor ?? this.controlsBorderColor,
      badgeColor: badgeColor ?? this.badgeColor,
      badgeTextStyle: badgeTextStyle ?? this.badgeTextStyle,
      nodeTypes: nodeTypes ?? this.nodeTypes,
    );
  }

  @override
  NodeEditorTheme lerp(covariant NodeEditorTheme? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    double d(double a, double b) => lerpDouble(a, b, t)!;
    TextStyle s(TextStyle a, TextStyle b) => TextStyle.lerp(a, b, t)!;
    final pick = t < 0.5;
    return NodeEditorTheme(
      brightness: pick ? brightness : other.brightness,
      backgroundColor: c(backgroundColor, other.backgroundColor),
      gridStyle: pick ? gridStyle : other.gridStyle,
      gridColor: c(gridColor, other.gridColor),
      gridMajorColor: c(gridMajorColor, other.gridMajorColor),
      gridSpacing: d(gridSpacing, other.gridSpacing),
      gridMajorEvery: pick ? gridMajorEvery : other.gridMajorEvery,
      nodeColor: c(nodeColor, other.nodeColor),
      nodeHeaderColor: c(nodeHeaderColor, other.nodeHeaderColor),
      nodeBorderColor: c(nodeBorderColor, other.nodeBorderColor),
      nodeBorderWidth: d(nodeBorderWidth, other.nodeBorderWidth),
      nodeSelectedBorderColor:
          c(nodeSelectedBorderColor, other.nodeSelectedBorderColor),
      nodeSelectedBorderWidth:
          d(nodeSelectedBorderWidth, other.nodeSelectedBorderWidth),
      nodeRadius: d(nodeRadius, other.nodeRadius),
      nodeShadow:
          BoxShadow.lerpList(nodeShadow, other.nodeShadow, t) ?? const [],
      nodeHeaderHeight: d(nodeHeaderHeight, other.nodeHeaderHeight),
      nodePadding: EdgeInsets.lerp(nodePadding, other.nodePadding, t)!,
      nodeTitleStyle: s(nodeTitleStyle, other.nodeTitleStyle),
      nodeSubtitleStyle: s(nodeSubtitleStyle, other.nodeSubtitleStyle),
      nodeTypeLabelStyle: s(nodeTypeLabelStyle, other.nodeTypeLabelStyle),
      accentColor: c(accentColor, other.accentColor),
      portColor: c(portColor, other.portColor),
      portFillColor: c(portFillColor, other.portFillColor),
      portRadius: d(portRadius, other.portRadius),
      portHitRadius: d(portHitRadius, other.portHitRadius),
      portLabelStyle: s(portLabelStyle, other.portLabelStyle),
      showPortLabels: pick ? showPortLabels : other.showPortLabels,
      edgeColor: c(edgeColor, other.edgeColor),
      edgeWidth: d(edgeWidth, other.edgeWidth),
      edgeSelectedColor: c(edgeSelectedColor, other.edgeSelectedColor),
      edgeCurve: pick ? edgeCurve : other.edgeCurve,
      edgeDashed: pick ? edgeDashed : other.edgeDashed,
      edgeDashPattern: pick ? edgeDashPattern : other.edgeDashPattern,
      edgeArrow: pick ? edgeArrow : other.edgeArrow,
      edgeArrowSize: d(edgeArrowSize, other.edgeArrowSize),
      edgeCornerRadius: d(edgeCornerRadius, other.edgeCornerRadius),
      edgeHitWidth: d(edgeHitWidth, other.edgeHitWidth),
      edgeLabelBackground: c(edgeLabelBackground, other.edgeLabelBackground),
      edgeLabelBorderColor: c(edgeLabelBorderColor, other.edgeLabelBorderColor),
      edgeLabelStyle: s(edgeLabelStyle, other.edgeLabelStyle),
      hierarchyEdgeColor: c(hierarchyEdgeColor, other.hierarchyEdgeColor),
      hierarchyEdgeWidth: d(hierarchyEdgeWidth, other.hierarchyEdgeWidth),
      hierarchyEdgeCurve: pick ? hierarchyEdgeCurve : other.hierarchyEdgeCurve,
      hierarchyEdgeDashed:
          pick ? hierarchyEdgeDashed : other.hierarchyEdgeDashed,
      connectionPreviewColor:
          c(connectionPreviewColor, other.connectionPreviewColor),
      invalidConnectionColor:
          c(invalidConnectionColor, other.invalidConnectionColor),
      selectionFillColor: c(selectionFillColor, other.selectionFillColor),
      selectionBorderColor: c(selectionBorderColor, other.selectionBorderColor),
      dropTargetColor: c(dropTargetColor, other.dropTargetColor),
      minimapBackground: c(minimapBackground, other.minimapBackground),
      minimapNodeColor: c(minimapNodeColor, other.minimapNodeColor),
      minimapSelectedNodeColor:
          c(minimapSelectedNodeColor, other.minimapSelectedNodeColor),
      minimapViewportColor: c(minimapViewportColor, other.minimapViewportColor),
      minimapBorderColor: c(minimapBorderColor, other.minimapBorderColor),
      controlsBackground: c(controlsBackground, other.controlsBackground),
      controlsForeground: c(controlsForeground, other.controlsForeground),
      controlsBorderColor: c(controlsBorderColor, other.controlsBorderColor),
      badgeColor: c(badgeColor, other.badgeColor),
      badgeTextStyle: s(badgeTextStyle, other.badgeTextStyle),
      nodeTypes: pick ? nodeTypes : other.nodeTypes,
    );
  }
}
