import 'dart:ui' show Color, Offset, Rect, Size;

import 'package:flutter/foundation.dart';

import 'port.dart';

/// Nodo del grafo.
///
/// Es inmutable: para modificarlo usa [copyWith] a través del
/// `NodeEditorController` (`updateNode`, `moveNodes`, `setParent`...).
///
/// `T` es el tipo del dato de negocio asociado (empleado, sucursal,
/// producto...). Usa `Object?` o `dynamic` si mezclas varios tipos.
@immutable
class NodeData<T> {
  const NodeData({
    required this.id,
    required this.position,
    this.size = const Size(200, 96),
    this.type = 'default',
    this.title = '',
    this.subtitle,
    this.data,
    this.ports = const [],
    this.parentId,
    this.collapsed = false,
    this.locked = false,
    this.autoSize = false,
    this.color,
  });

  final String id;

  /// Esquina superior izquierda en coordenadas del mundo.
  final Offset position;

  /// Tamaño del nodo. Con [autoSize] es el tamaño mínimo.
  final Size size;

  /// Tipo lógico (p. ej. `employee`, `branch`, `warehouse`). Se usa para
  /// elegir estilo (`NodeTypeStyle`) y para que tu `nodeBuilder` decida qué
  /// widget pintar.
  final String type;

  final String title;
  final String? subtitle;

  /// Dato de negocio asociado.
  final T? data;

  final List<NodePort> ports;

  /// Id del nodo padre en la jerarquía. `null` = nodo raíz.
  final String? parentId;

  /// Si es `true` los descendientes se ocultan.
  final bool collapsed;

  /// Si es `true` el nodo no se puede arrastrar ni borrar desde la UI.
  final bool locked;

  /// Si es `true` el widget del nodo se mide y puede crecer a partir de
  /// [size] (útil para mapas mentales con textos de longitud variable).
  /// Es ligeramente más costoso que un tamaño fijo.
  final bool autoSize;

  /// Color de acento propio. `null` usa el del tipo o el del tema.
  final Color? color;

  Rect get rect => position & size;

  NodePort? port(String portId) {
    for (final p in ports) {
      if (p.id == portId) return p;
    }
    return null;
  }

  NodeData<T> copyWith({
    Offset? position,
    Size? size,
    String? type,
    String? title,
    String? subtitle,
    T? data,
    List<NodePort>? ports,
    String? parentId,
    bool clearParent = false,
    bool? collapsed,
    bool? locked,
    bool? autoSize,
    Color? color,
  }) {
    return NodeData<T>(
      id: id,
      position: position ?? this.position,
      size: size ?? this.size,
      type: type ?? this.type,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      data: data ?? this.data,
      ports: ports ?? this.ports,
      parentId: clearParent ? null : (parentId ?? this.parentId),
      collapsed: collapsed ?? this.collapsed,
      locked: locked ?? this.locked,
      autoSize: autoSize ?? this.autoSize,
      color: color ?? this.color,
    );
  }

  /// `true` si todo excepto la posición es igual. Se usa internamente para
  /// evitar reconstruir widgets cuando un nodo sólo se mueve.
  bool sameContentAs(NodeData<T> other) =>
      identical(this, other) ||
      (other.id == id &&
          other.size == size &&
          other.type == type &&
          other.title == title &&
          other.subtitle == subtitle &&
          identical(other.data, data) &&
          listEquals(other.ports, ports) &&
          other.parentId == parentId &&
          other.collapsed == collapsed &&
          other.locked == locked &&
          other.autoSize == autoSize &&
          other.color == color);

  Map<String, Object?> toJson([Object? Function(T? data)? encodeData]) => {
        'id': id,
        'x': position.dx,
        'y': position.dy,
        'w': size.width,
        'h': size.height,
        'type': type,
        'title': title,
        if (subtitle != null) 'subtitle': subtitle,
        if (data != null) 'data': encodeData != null ? encodeData(data) : data,
        if (ports.isNotEmpty) 'ports': [for (final p in ports) p.toJson()],
        if (parentId != null) 'parentId': parentId,
        if (collapsed) 'collapsed': true,
        if (locked) 'locked': true,
        if (autoSize) 'autoSize': true,
        if (color != null) 'color': color!.toARGB32(),
      };

  static NodeData<T> fromJson<T>(
    Map<String, Object?> json, [
    T? Function(Object? raw)? decodeData,
  ]) {
    final raw = json['data'];
    return NodeData<T>(
      id: json['id']! as String,
      position: Offset((json['x'] as num? ?? 0).toDouble(),
          (json['y'] as num? ?? 0).toDouble()),
      size: Size((json['w'] as num? ?? 200).toDouble(),
          (json['h'] as num? ?? 96).toDouble()),
      type: json['type'] as String? ?? 'default',
      title: json['title'] as String? ?? '',
      subtitle: json['subtitle'] as String?,
      data: decodeData != null ? decodeData(raw) : raw as T?,
      ports: [
        for (final p in (json['ports'] as List?) ?? const [])
          NodePort.fromJson((p as Map).cast<String, Object?>()),
      ],
      parentId: json['parentId'] as String?,
      collapsed: json['collapsed'] as bool? ?? false,
      locked: json['locked'] as bool? ?? false,
      autoSize: json['autoSize'] as bool? ?? false,
      color: json['color'] == null ? null : Color(json['color']! as int),
    );
  }

  @override
  String toString() => 'NodeData($id, "$title", $position)';
}
