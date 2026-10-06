import 'dart:ui';

import '../model/node.dart';
import '../model/port.dart';

class _PortSlot {
  const _PortSlot(this.side, this.t, this.explicit);
  final PortSide side;
  final double t;
  final bool explicit;
}

final Expando<Map<String, _PortSlot>> _slotCache = Expando('portSlots');

Map<String, _PortSlot> _slotsOf(NodeData<Object?> node) {
  final cached = _slotCache[node.ports];
  if (cached != null) return cached;
  final counts = <PortSide, int>{};
  for (final p in node.ports) {
    if (p.offset == null) counts[p.side] = (counts[p.side] ?? 0) + 1;
  }
  final seen = <PortSide, int>{};
  final out = <String, _PortSlot>{};
  for (final p in node.ports) {
    if (p.offset != null) {
      out[p.id] = _PortSlot(p.side, p.offset!, true);
    } else {
      final i = seen[p.side] = (seen[p.side] ?? -1) + 1;
      out[p.id] = _PortSlot(p.side, (i + 0.5) / counts[p.side]!, false);
    }
  }
  // Las listas `const []` son compartidas; no se pueden usar como clave de
  // Expando de forma útil, pero tampoco tienen puertos.
  if (node.ports.isNotEmpty) _slotCache[node.ports] = out;
  return out;
}

/// Utilidades geométricas de nodos y puertos.
abstract final class NodeGeometry {
  /// Espacio superior reservado a la cabecera en los lados izquierdo/derecho
  /// sólo si el nodo tiene al menos esta altura libre extra.
  static const double _minPortArea = 28;

  static double effectiveTopInset(Size size, double topInset) =>
      size.height >= topInset + _minPortArea ? topInset : 0;

  /// Posición local (relativa a la esquina del nodo) del centro de un puerto.
  static Offset portLocalPosition(
    NodeData<Object?> node,
    Size size,
    String portId, {
    double topInset = 0,
  }) {
    final slot = _slotsOf(node)[portId];
    if (slot == null) return size.center(Offset.zero);
    final w = size.width, h = size.height;
    switch (slot.side) {
      case PortSide.left:
      case PortSide.right:
        final double y;
        if (slot.explicit) {
          y = h * slot.t;
        } else {
          final inset = effectiveTopInset(size, topInset);
          y = inset + (h - inset) * slot.t;
        }
        return Offset(slot.side == PortSide.left ? 0 : w, y);
      case PortSide.top:
        return Offset(w * slot.t, 0);
      case PortSide.bottom:
        return Offset(w * slot.t, h);
    }
  }

  /// Anclaje de una conexión flotante (sin puerto): punto medio del lado de
  /// [rect] que mira hacia [towards].
  static (Offset, PortSide) floatingAnchor(Rect rect, Offset towards) {
    final c = rect.center;
    final d = towards - c;
    // Normalizamos por el tamaño para que el lado elegido sea coherente con
    // la forma del rectángulo.
    final nx = d.dx / (rect.width / 2 + 1);
    final ny = d.dy / (rect.height / 2 + 1);
    if (nx.abs() >= ny.abs()) {
      return nx >= 0
          ? (rect.centerRight, PortSide.right)
          : (rect.centerLeft, PortSide.left);
    }
    return ny >= 0
        ? (rect.bottomCenter, PortSide.bottom)
        : (rect.topCenter, PortSide.top);
  }
}
