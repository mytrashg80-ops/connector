import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';

/// Forma de la línea de una conexión.
enum EdgeCurve {
  /// Curva de Bézier suave (estilo Unreal / Blender).
  bezier,

  /// Tramos ortogonales con esquinas redondeadas.
  smoothStep,

  /// Tramos ortogonales con esquinas rectas.
  step,

  /// Línea recta.
  straight,
}

/// Conexión dirigida entre dos nodos.
///
/// Si [sourcePortId]/[targetPortId] son `null` la conexión es "flotante":
/// se ancla al lado del nodo más cercano al otro extremo (ideal para mapas
/// mentales sin puertos).
@immutable
class EdgeData {
  const EdgeData({
    required this.id,
    required this.sourceNodeId,
    required this.targetNodeId,
    this.sourcePortId,
    this.targetPortId,
    this.label,
    this.curve,
    this.color,
    this.width,
    this.dashed,
    this.animated = false,
    this.arrow,
    this.metadata,
  });

  final String id;
  final String sourceNodeId;
  final String? sourcePortId;
  final String targetNodeId;
  final String? targetPortId;

  /// Texto mostrado en el centro de la conexión.
  final String? label;

  /// `null` usa el del tema.
  final EdgeCurve? curve;
  final Color? color;
  final double? width;
  final bool? dashed;

  /// Anima el trazo discontinuo para mostrar el sentido del flujo.
  /// Sólo consume recursos mientras haya conexiones animadas visibles.
  final bool animated;

  /// Dibuja una flecha en el destino. `null` usa el del tema.
  final bool? arrow;

  /// Datos libres serializables.
  final Map<String, Object?>? metadata;

  bool touches(String nodeId) =>
      sourceNodeId == nodeId || targetNodeId == nodeId;

  /// `true` si conecta exactamente los mismos extremos.
  bool sameEnds(EdgeData other) =>
      other.sourceNodeId == sourceNodeId &&
      other.sourcePortId == sourcePortId &&
      other.targetNodeId == targetNodeId &&
      other.targetPortId == targetPortId;

  EdgeData copyWith({
    String? id,
    String? sourceNodeId,
    String? sourcePortId,
    String? targetNodeId,
    String? targetPortId,
    String? label,
    bool clearLabel = false,
    EdgeCurve? curve,
    Color? color,
    double? width,
    bool? dashed,
    bool? animated,
    bool? arrow,
    Map<String, Object?>? metadata,
  }) {
    return EdgeData(
      id: id ?? this.id,
      sourceNodeId: sourceNodeId ?? this.sourceNodeId,
      sourcePortId: sourcePortId ?? this.sourcePortId,
      targetNodeId: targetNodeId ?? this.targetNodeId,
      targetPortId: targetPortId ?? this.targetPortId,
      label: clearLabel ? null : (label ?? this.label),
      curve: curve ?? this.curve,
      color: color ?? this.color,
      width: width ?? this.width,
      dashed: dashed ?? this.dashed,
      animated: animated ?? this.animated,
      arrow: arrow ?? this.arrow,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'source': sourceNodeId,
        if (sourcePortId != null) 'sourcePort': sourcePortId,
        'target': targetNodeId,
        if (targetPortId != null) 'targetPort': targetPortId,
        if (label != null) 'label': label,
        if (curve != null) 'curve': curve!.name,
        if (color != null) 'color': color!.toARGB32(),
        if (width != null) 'width': width,
        if (dashed != null) 'dashed': dashed,
        if (animated) 'animated': true,
        if (arrow != null) 'arrow': arrow,
        if (metadata != null) 'metadata': metadata,
      };

  factory EdgeData.fromJson(Map<String, Object?> json) => EdgeData(
        id: json['id']! as String,
        sourceNodeId: json['source']! as String,
        sourcePortId: json['sourcePort'] as String?,
        targetNodeId: json['target']! as String,
        targetPortId: json['targetPort'] as String?,
        label: json['label'] as String?,
        curve: json['curve'] == null
            ? null
            : EdgeCurve.values.byName(json['curve']! as String),
        color: json['color'] == null ? null : Color(json['color']! as int),
        width: (json['width'] as num?)?.toDouble(),
        dashed: json['dashed'] as bool?,
        animated: json['animated'] as bool? ?? false,
        arrow: json['arrow'] as bool?,
        metadata: (json['metadata'] as Map?)?.cast<String, Object?>(),
      );

  @override
  String toString() =>
      'EdgeData($id, $sourceNodeId:$sourcePortId -> $targetNodeId:$targetPortId)';
}
