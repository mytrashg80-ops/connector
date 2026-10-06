import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'edge.dart';

/// Qué crea el usuario al tirar una línea desde un nodo.
enum ConnectorKind {
  /// Una conexión ([EdgeData]): flujos, rutas, dependencias…
  edge,

  /// Un enlace de jerarquía: el nodo de destino pasa a ser hijo del de
  /// origen (cambia su `parentId`).
  hierarchy,
}

/// Plantilla de los conectores que se crean desde la UI.
///
/// Se asigna en `NodeEditorConfig.newConnector`. Para [ConnectorKind.edge]
/// las propiedades visuales se copian a la conexión nueva (las que son
/// `null` usan las del tema).
@immutable
class ConnectorStyle {
  const ConnectorStyle({
    this.kind = ConnectorKind.edge,
    this.curve,
    this.color,
    this.width,
    this.dashed,
    this.arrow,
    this.animated = false,
    this.label,
  });

  /// Enlaces de jerarquía (padre → hijo).
  static const hierarchy = ConnectorStyle(kind: ConnectorKind.hierarchy);

  final ConnectorKind kind;
  final EdgeCurve? curve;
  final Color? color;
  final double? width;
  final bool? dashed;
  final bool? arrow;
  final bool animated;
  final String? label;

  bool get isHierarchy => kind == ConnectorKind.hierarchy;

  /// Construye la conexión con este estilo.
  EdgeData toEdge({
    required String id,
    required String sourceNodeId,
    String? sourcePortId,
    required String targetNodeId,
    String? targetPortId,
  }) =>
      EdgeData(
        id: id,
        sourceNodeId: sourceNodeId,
        sourcePortId: sourcePortId,
        targetNodeId: targetNodeId,
        targetPortId: targetPortId,
        label: label,
        curve: curve,
        color: color,
        width: width,
        dashed: dashed,
        arrow: arrow,
        animated: animated,
      );

  ConnectorStyle copyWith({
    ConnectorKind? kind,
    EdgeCurve? curve,
    Color? color,
    double? width,
    bool? dashed,
    bool? arrow,
    bool? animated,
    String? label,
  }) =>
      ConnectorStyle(
        kind: kind ?? this.kind,
        curve: curve ?? this.curve,
        color: color ?? this.color,
        width: width ?? this.width,
        dashed: dashed ?? this.dashed,
        arrow: arrow ?? this.arrow,
        animated: animated ?? this.animated,
        label: label ?? this.label,
      );

  @override
  bool operator ==(Object other) =>
      other is ConnectorStyle &&
      other.kind == kind &&
      other.curve == curve &&
      other.color == color &&
      other.width == width &&
      other.dashed == dashed &&
      other.arrow == arrow &&
      other.animated == animated &&
      other.label == label;

  @override
  int get hashCode =>
      Object.hash(kind, curve, color, width, dashed, arrow, animated, label);
}
