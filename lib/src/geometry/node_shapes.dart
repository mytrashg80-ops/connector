import 'dart:math' as math;
import 'dart:ui';

import '../model/node.dart';
import '../model/node_style.dart';
import 'node_geometry.dart';

/// Geometría de las formas de nodo ([NodeShape]).
abstract final class NodeShapes {
  /// Zona (local) que ocupa la forma dentro del nodo. Sólo difiere del nodo
  /// entero en el círculo: arriba y centrado, con el título debajo.
  static Rect bodyRect(NodeShape shape, Size size) {
    if (shape != NodeShape.circle) return Offset.zero & size;
    final d = math.min(size.width, size.height);
    return Rect.fromLTWH((size.width - d) / 2, 0, d, d);
  }

  /// Contorno de la forma dentro de [r].
  static Path path(NodeShape shape, Rect r, double radius) {
    switch (shape) {
      case NodeShape.card:
      case NodeShape.box:
        return Path()
          ..addRRect(RRect.fromRectAndRadius(r, Radius.circular(radius)));
      case NodeShape.pill:
        return Path()
          ..addRRect(RRect.fromRectAndRadius(
              r, Radius.circular(math.min(r.width, r.height) / 2)));
      case NodeShape.circle:
        final d = math.min(r.width, r.height);
        return Path()
          ..addOval(Rect.fromCenter(center: r.center, width: d, height: d));
      case NodeShape.diamond:
        return Path()
          ..moveTo(r.center.dx, r.top)
          ..lineTo(r.right, r.center.dy)
          ..lineTo(r.center.dx, r.bottom)
          ..lineTo(r.left, r.center.dy)
          ..close();
      case NodeShape.hexagon:
        final inset = math.min(r.width * 0.25, r.height * 0.5 * 0.58);
        return Path()
          ..moveTo(r.left + inset, r.top)
          ..lineTo(r.right - inset, r.top)
          ..lineTo(r.right, r.center.dy)
          ..lineTo(r.right - inset, r.bottom)
          ..lineTo(r.left + inset, r.bottom)
          ..lineTo(r.left, r.center.dy)
          ..close();
    }
  }

  /// Posición local de un puerto: en el borde de la forma (bajo la cabecera
  /// en las tarjetas).
  static Offset portLocalPosition(NodeData<Object?> node, NodeShape shape,
      Size size, String portId, double headerHeight) {
    final body = bodyRect(shape, size);
    return body.topLeft +
        NodeGeometry.portLocalPosition(node, body.size, portId,
            topInset: shape == NodeShape.card ? headerHeight : 0);
  }
}
