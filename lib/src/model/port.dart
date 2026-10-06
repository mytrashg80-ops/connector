import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';

/// Lado del nodo en el que se dibuja un puerto.
enum PortSide {
  left,
  top,
  right,
  bottom;

  /// Vector normal (hacia fuera del nodo) del lado.
  (double, double) get normal => switch (this) {
        PortSide.left => (-1, 0),
        PortSide.top => (0, -1),
        PortSide.right => (1, 0),
        PortSide.bottom => (0, 1),
      };

  bool get isHorizontal => this == PortSide.left || this == PortSide.right;

  PortSide get opposite => switch (this) {
        PortSide.left => PortSide.right,
        PortSide.top => PortSide.bottom,
        PortSide.right => PortSide.left,
        PortSide.bottom => PortSide.top,
      };
}

/// Dirección del flujo que admite un puerto.
enum PortDirection {
  /// Sólo recibe conexiones.
  input,

  /// Sólo origina conexiones.
  output,

  /// Origina y recibe conexiones (útil para mapas mentales).
  both,
}

/// Punto de conexión de un nodo.
@immutable
class NodePort {
  const NodePort({
    required this.id,
    this.side = PortSide.left,
    this.direction = PortDirection.input,
    this.label,
    this.type,
    this.color,
    this.maxConnections,
    this.offset,
  });

  /// Puerto de entrada (lado izquierdo por defecto).
  const NodePort.input({
    required this.id,
    this.side = PortSide.left,
    this.label,
    this.type,
    this.color,
    this.maxConnections,
    this.offset,
  }) : direction = PortDirection.input;

  /// Puerto de salida (lado derecho por defecto).
  const NodePort.output({
    required this.id,
    this.side = PortSide.right,
    this.label,
    this.type,
    this.color,
    this.maxConnections,
    this.offset,
  }) : direction = PortDirection.output;

  final String id;
  final PortSide side;
  final PortDirection direction;
  final String? label;

  /// Tipo lógico usado para validar compatibilidad entre puertos.
  /// `null` acepta cualquier tipo.
  final String? type;

  /// Color del puerto. `null` usa el del tema.
  final Color? color;

  /// Máximo de conexiones permitidas. `null` = ilimitadas.
  final int? maxConnections;

  /// Posición relativa (0..1) a lo largo del lado.
  /// `null` = se reparte automáticamente con los demás puertos del lado.
  final double? offset;

  bool get canSend => direction != PortDirection.input;
  bool get canReceive => direction != PortDirection.output;

  NodePort copyWith({
    String? id,
    PortSide? side,
    PortDirection? direction,
    String? label,
    String? type,
    Color? color,
    int? maxConnections,
    double? offset,
  }) {
    return NodePort(
      id: id ?? this.id,
      side: side ?? this.side,
      direction: direction ?? this.direction,
      label: label ?? this.label,
      type: type ?? this.type,
      color: color ?? this.color,
      maxConnections: maxConnections ?? this.maxConnections,
      offset: offset ?? this.offset,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'side': side.name,
        'direction': direction.name,
        if (label != null) 'label': label,
        if (type != null) 'type': type,
        if (color != null) 'color': color!.toARGB32(),
        if (maxConnections != null) 'maxConnections': maxConnections,
        if (offset != null) 'offset': offset,
      };

  factory NodePort.fromJson(Map<String, Object?> json) => NodePort(
        id: json['id']! as String,
        side: PortSide.values.byName(json['side'] as String? ?? 'left'),
        direction: PortDirection.values
            .byName(json['direction'] as String? ?? 'input'),
        label: json['label'] as String?,
        type: json['type'] as String?,
        color: json['color'] == null ? null : Color(json['color']! as int),
        maxConnections: json['maxConnections'] as int?,
        offset: (json['offset'] as num?)?.toDouble(),
      );

  @override
  bool operator ==(Object other) =>
      other is NodePort &&
      other.id == id &&
      other.side == side &&
      other.direction == direction &&
      other.label == label &&
      other.type == type &&
      other.color == color &&
      other.maxConnections == maxConnections &&
      other.offset == offset;

  @override
  int get hashCode => Object.hash(
      id, side, direction, label, type, color, maxConnections, offset);

  @override
  String toString() => 'NodePort($id, ${side.name}, ${direction.name})';
}
