import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';

/// Forma de la caja de un nodo.
enum NodeShape {
  /// Tarjeta con cabecera (tipo e icono) y contenido. Es la forma por
  /// defecto.
  card,

  /// Caja sencilla: icono y texto, sin cabecera.
  box,

  /// Píldora (extremos redondos), ideal para etiquetas y estados.
  pill,

  /// Círculo con el icono en el centro y el título debajo (si el nodo es
  /// más alto que ancho queda espacio para él).
  circle,

  /// Rombo (decisiones).
  diamond,

  /// Hexágono.
  hexagon,
}

/// Trazo del borde de un nodo.
enum NodeBorderStyle { solid, dashed, dotted, none }

/// Aspecto propio de un nodo. Cada campo `null` usa el del tipo
/// (`NodeTypeStyle`) y, si tampoco lo tiene, el del tema.
///
/// ```dart
/// NodeData(
///   id: 'hito',
///   position: Offset.zero,
///   size: const Size(72, 96),
///   title: 'Entrega',
///   color: Colors.green,                // acento: icono, borde de color…
///   style: const NodeStyle(
///     shape: NodeShape.circle,
///     icon: 'flag',                     // clave de NodeEditorTheme.icons
///   ),
/// )
/// ```
@immutable
class NodeStyle {
  const NodeStyle({
    this.shape,
    this.icon,
    this.filled,
    this.fillColor,
    this.borderColor,
    this.borderWidth,
    this.borderStyle,
    this.textColor,
  });

  final NodeShape? shape;

  /// Clave del icono en `NodeEditorTheme.icons` (p. ej. `'flag'`). Se guarda
  /// como texto para que el nodo se pueda serializar a JSON.
  final String? icon;

  /// `false` = sólo líneas: sin relleno, se ve el lienzo a través.
  final bool? filled;
  final Color? fillColor;
  final Color? borderColor;
  final double? borderWidth;
  final NodeBorderStyle? borderStyle;
  final Color? textColor;

  bool get isEmpty =>
      shape == null &&
      icon == null &&
      filled == null &&
      fillColor == null &&
      borderColor == null &&
      borderWidth == null &&
      borderStyle == null &&
      textColor == null;

  /// Copia cambiando campos. Los `clearX` vuelven a "heredar" ese campo.
  NodeStyle copyWith({
    NodeShape? shape,
    String? icon,
    bool clearIcon = false,
    bool? filled,
    Color? fillColor,
    bool clearFillColor = false,
    Color? borderColor,
    bool clearBorderColor = false,
    double? borderWidth,
    NodeBorderStyle? borderStyle,
    Color? textColor,
    bool clearTextColor = false,
  }) =>
      NodeStyle(
        shape: shape ?? this.shape,
        icon: clearIcon ? null : (icon ?? this.icon),
        filled: filled ?? this.filled,
        fillColor: clearFillColor ? null : (fillColor ?? this.fillColor),
        borderColor:
            clearBorderColor ? null : (borderColor ?? this.borderColor),
        borderWidth: borderWidth ?? this.borderWidth,
        borderStyle: borderStyle ?? this.borderStyle,
        textColor: clearTextColor ? null : (textColor ?? this.textColor),
      );

  Map<String, Object?> toJson() => {
        if (shape != null) 'shape': shape!.name,
        if (icon != null) 'icon': icon,
        if (filled != null) 'filled': filled,
        if (fillColor != null) 'fill': fillColor!.toARGB32(),
        if (borderColor != null) 'border': borderColor!.toARGB32(),
        if (borderWidth != null) 'borderWidth': borderWidth,
        if (borderStyle != null) 'borderStyle': borderStyle!.name,
        if (textColor != null) 'text': textColor!.toARGB32(),
      };

  static NodeStyle fromJson(Map<String, Object?> json) {
    Color? color(String key) =>
        json[key] == null ? null : Color(json[key]! as int);
    T? byName<T extends Enum>(List<T> values, String key) {
      final name = json[key];
      for (final v in values) {
        if (v.name == name) return v;
      }
      return null;
    }

    return NodeStyle(
      shape: byName(NodeShape.values, 'shape'),
      icon: json['icon'] as String?,
      filled: json['filled'] as bool?,
      fillColor: color('fill'),
      borderColor: color('border'),
      borderWidth: (json['borderWidth'] as num?)?.toDouble(),
      borderStyle: byName(NodeBorderStyle.values, 'borderStyle'),
      textColor: color('text'),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is NodeStyle &&
      other.shape == shape &&
      other.icon == icon &&
      other.filled == filled &&
      other.fillColor == fillColor &&
      other.borderColor == borderColor &&
      other.borderWidth == borderWidth &&
      other.borderStyle == borderStyle &&
      other.textColor == textColor;

  @override
  int get hashCode => Object.hash(shape, icon, filled, fillColor, borderColor,
      borderWidth, borderStyle, textColor);
}
