import 'dart:math' as math;

import 'package:connector/connector.dart';
import 'package:flutter/material.dart';

/// Dato de negocio del ejemplo. En tu app puede ser cualquier clase.
typedef Item = Map<String, Object?>;

/// Estilos por tipo de nodo (colores e iconos), compartidos por los temas.
const Map<String, NodeTypeStyle> nodeTypeStyles = {
  'company': NodeTypeStyle(
      label: 'Empresa', icon: Icons.business, color: Color(0xFF6366F1)),
  'region': NodeTypeStyle(
      label: 'Región', icon: Icons.public, color: Color(0xFF0EA5E9)),
  'branch': NodeTypeStyle(
      label: 'Sucursal', icon: Icons.storefront, color: Color(0xFF10B981)),
  'warehouse': NodeTypeStyle(
      label: 'Almacén',
      icon: Icons.warehouse_outlined,
      color: Color(0xFFF59E0B)),
  'employee': NodeTypeStyle(
      label: 'Empleado', icon: Icons.person_outline, color: Color(0xFF8B5CF6)),
  'department': NodeTypeStyle(
      label: 'Departamento',
      icon: Icons.groups_outlined,
      color: Color(0xFFEC4899)),
  'part': NodeTypeStyle(
      label: 'Pieza', icon: Icons.settings_outlined, color: Color(0xFF64748B)),
  'station': NodeTypeStyle(
      label: 'Estación',
      icon: Icons.precision_manufacturing_outlined,
      color: Color(0xFFF97316)),
  'product': NodeTypeStyle(
      label: 'Producto',
      icon: Icons.inventory_2_outlined,
      color: Color(0xFF22C55E)),
  'supplier': NodeTypeStyle(
      label: 'Proveedor',
      icon: Icons.factory_outlined,
      color: Color(0xFFEF4444)),
  'transport': NodeTypeStyle(
      label: 'Transporte',
      icon: Icons.local_shipping_outlined,
      color: Color(0xFF06B6D4)),
  'customer': NodeTypeStyle(
      label: 'Cliente',
      icon: Icons.person_pin_circle_outlined,
      color: Color(0xFFA855F7)),
  'category': NodeTypeStyle(
      label: 'Categoría',
      icon: Icons.category_outlined,
      color: Color(0xFF3B82F6)),
  'idea': NodeTypeStyle(
      label: 'Idea', icon: Icons.lightbulb_outline, color: Color(0xFFEAB308)),
  // Formas: cada tipo trae su forma y borde por defecto, y cada nodo puede
  // cambiarlos (y el color y el icono) con `NodeData.style`.
  'milestone': NodeTypeStyle(
      label: 'Hito',
      icon: Icons.flag_outlined,
      color: Color(0xFF14B8A6),
      shape: NodeShape.circle),
  'decision': NodeTypeStyle(
      label: 'Decisión',
      icon: Icons.help_outline,
      color: Color(0xFFF59E0B),
      shape: NodeShape.diamond),
  'process': NodeTypeStyle(
      label: 'Proceso',
      icon: Icons.sync,
      color: Color(0xFF6366F1),
      shape: NodeShape.hexagon),
  'tag': NodeTypeStyle(
      label: 'Etiqueta',
      icon: Icons.label_outline,
      color: Color(0xFFEC4899),
      shape: NodeShape.pill),
  'frame': NodeTypeStyle(
      label: 'Marco',
      icon: Icons.crop_square,
      color: Color(0xFF0EA5E9),
      shape: NodeShape.box,
      filled: false),
  'note': NodeTypeStyle(
      label: 'Nota',
      icon: Icons.sticky_note_2_outlined,
      color: Color(0xFFEAB308),
      shape: NodeShape.box,
      filled: false,
      borderStyle: NodeBorderStyle.dashed),
};

/// Puertos por defecto según el tipo.
List<NodePort> portsFor(String type) => switch (type) {
      'part' => const [
          NodePort.output(id: 'out', label: 'Pieza', type: 'part')
        ],
      'station' => const [
          NodePort.input(id: 'a', label: 'Entrada A', type: 'part'),
          NodePort.input(id: 'b', label: 'Entrada B', type: 'part'),
          NodePort.output(id: 'out', label: 'Subensamble'),
        ],
      'product' => const [
          NodePort.input(id: 'in'),
          NodePort.output(id: 'out', type: 'shipment'),
        ],
      'supplier' => const [
          NodePort.output(id: 'out', label: 'Envío', type: 'shipment'),
        ],
      'warehouse' || 'transport' || 'branch' => const [
          NodePort.input(id: 'in', label: 'Recibe', type: 'shipment'),
          NodePort.output(id: 'out', label: 'Despacha', type: 'shipment'),
        ],
      'customer' => const [
          NodePort.input(id: 'in', label: 'Pedido', type: 'shipment'),
        ],
      _ => const [],
    };

Size sizeFor(String type) => switch (type) {
      'employee' => const Size(220, 72),
      'idea' => const Size(150, 44),
      'milestone' => const Size(88, 112),
      'decision' => const Size(170, 110),
      'process' => const Size(190, 72),
      'tag' => const Size(170, 44),
      'frame' => const Size(200, 72),
      'note' => const Size(210, 72),
      'product' => const Size(220, 116),
      'station' => const Size(220, 120),
      'company' ||
      'region' ||
      'department' ||
      'category' =>
        const Size(210, 64),
      _ => const Size(200, 96),
    };

NodeData<Item> makeNode(
  String id,
  String type,
  String title, {
  Offset position = Offset.zero,
  String? subtitle,
  String? parentId,
  Item? data,
  bool autoSize = false,
  bool withPorts = true,
  Color? color,
}) {
  return NodeData<Item>(
    id: id,
    type: type,
    title: title,
    subtitle: subtitle,
    position: position,
    size: sizeFor(type),
    ports: withPorts ? portsFor(type) : const [],
    parentId: parentId,
    data: data,
    autoSize: autoSize || type == 'idea',
    color: color,
  );
}

class Scenario {
  const Scenario({
    required this.name,
    required this.icon,
    required this.build,
    required this.layout,
    this.hierarchyAxis = Axis.vertical,
    this.curve = EdgeCurve.bezier,
  });

  final String name;
  final IconData icon;
  final (List<NodeData<Item>>, List<EdgeData>) Function() build;
  final GraphLayout layout;
  final Axis hierarchyAxis;
  final EdgeCurve curve;
}

final scenarios = <Scenario>[
  Scenario(
    name: 'Organigrama',
    icon: Icons.account_tree_outlined,
    build: _orgChart,
    layout: const TreeLayout(siblingGap: 24, levelGap: 64),
    curve: EdgeCurve.smoothStep,
  ),
  Scenario(
    name: 'Empresa y sucursales',
    icon: Icons.business_outlined,
    build: _company,
    layout: const TreeLayout(
        direction: LayoutDirection.leftToRight, siblingGap: 18, levelGap: 90),
    hierarchyAxis: Axis.horizontal,
  ),
  Scenario(
    name: 'Cadena de ensamblado',
    icon: Icons.precision_manufacturing_outlined,
    build: _assembly,
    layout: const LayeredLayout(layerGap: 110, nodeGap: 36),
    curve: EdgeCurve.smoothStep,
  ),
  Scenario(
    name: 'Cadena de distribución',
    icon: Icons.local_shipping_outlined,
    build: _distribution,
    layout: const LayeredLayout(layerGap: 120, nodeGap: 28),
  ),
  Scenario(
    name: 'Estructura de inventario',
    icon: Icons.inventory_2_outlined,
    build: _inventory,
    layout: const TreeLayout(siblingGap: 20, levelGap: 60),
    curve: EdgeCurve.smoothStep,
  ),
  Scenario(
    name: 'Mapa mental',
    icon: Icons.bubble_chart_outlined,
    build: _mindMap,
    layout: const MindMapLayout(),
    hierarchyAxis: Axis.horizontal,
  ),
  Scenario(
    name: 'Diagrama de proceso',
    icon: Icons.schema_outlined,
    build: _process,
    layout: const _PresetLayout(_processPositions),
    curve: EdgeCurve.smoothStep,
  ),
  Scenario(
    name: 'Prueba de estrés (3000)',
    icon: Icons.speed,
    build: () => _stress(3000),
    layout: const GridLayout(gap: Size(60, 60)),
  ),
];

(List<NodeData<Item>>, List<EdgeData>) _orgChart() {
  final people = <(String, String, String, String?)>[
    ('ceo', 'Laura Méndez', 'Directora general', null),
    ('coo', 'Andrés Ruiz', 'Operaciones', 'ceo'),
    ('cfo', 'Marta Gil', 'Finanzas', 'ceo'),
    ('cto', 'Diego Paredes', 'Tecnología', 'ceo'),
    ('log', 'Sofía Navarro', 'Jefa de logística', 'coo'),
    ('alm', 'Pablo Ortega', 'Jefe de almacén', 'coo'),
    ('com', 'Lucía Romero', 'Compras', 'coo'),
    ('cont', 'Javier Soto', 'Contabilidad', 'cfo'),
    ('tes', 'Elena Vidal', 'Tesorería', 'cfo'),
    ('dev', 'Carlos León', 'Desarrollo', 'cto'),
    ('sop', 'Ana Castro', 'Soporte', 'cto'),
    ('op1', 'Raúl Peña', 'Operario', 'alm'),
    ('op2', 'Irene Lara', 'Operaria', 'alm'),
    ('op3', 'Hugo Ramos', 'Operario', 'alm'),
    ('chf', 'Nerea Cruz', 'Chófer', 'log'),
  ];
  return (
    [
      for (final (id, name, role, parent) in people)
        makeNode(id, 'employee', name,
            subtitle: role, parentId: parent, data: {'role': role}),
    ],
    const [],
  );
}

(List<NodeData<Item>>, List<EdgeData>) _company() {
  final nodes = <NodeData<Item>>[
    makeNode('co', 'company', 'Grupo Ferretero S.A.'),
    makeNode('n', 'region', 'Región Norte', parentId: 'co'),
    makeNode('c', 'region', 'Región Centro', parentId: 'co'),
    makeNode('s', 'region', 'Región Sur', parentId: 'co'),
  ];
  var i = 0;
  for (final (region, cities) in [
    ('n', ['Monterrey', 'Saltillo', 'Chihuahua']),
    ('c', ['CDMX Centro', 'CDMX Sur', 'Querétaro', 'Puebla']),
    ('s', ['Mérida', 'Oaxaca']),
  ]) {
    for (final city in cities) {
      final id = 'b${i++}';
      nodes.add(makeNode(id, 'branch', city,
          subtitle: 'Sucursal',
          parentId: region,
          data: {'stock': 120 + i * 13}));
      if (i.isEven) {
        nodes.add(makeNode('w$id', 'warehouse', 'Almacén $city',
            subtitle: 'Almacén local', parentId: id));
      }
    }
  }
  return (nodes, const []);
}

(List<NodeData<Item>>, List<EdgeData>) _assembly() {
  final nodes = [
    makeNode('p1', 'part', 'Carcasa', subtitle: 'Aluminio'),
    makeNode('p2', 'part', 'Motor 12V', subtitle: 'Proveedor externo'),
    makeNode('p3', 'part', 'Placa base', subtitle: 'Rev. C'),
    makeNode('p4', 'part', 'Batería', subtitle: 'Li-ion 4Ah'),
    makeNode('p5', 'part', 'Tornillería', subtitle: 'Kit M3'),
    makeNode('s1', 'station', 'Montaje motor', subtitle: 'Estación 1'),
    makeNode('s2', 'station', 'Electrónica', subtitle: 'Estación 2'),
    makeNode('s3', 'station', 'Ensamble final', subtitle: 'Estación 3'),
    makeNode('pr', 'product', 'Taladro TX-200',
        subtitle: 'Producto terminado', data: {'stock': 64, 'max': 100}),
    makeNode('wh', 'warehouse', 'Almacén central', subtitle: 'Producto final'),
  ];
  EdgeData e(String id, String s, String sp, String t, String tp,
          [String? label, bool animated = false]) =>
      EdgeData(
          id: id,
          sourceNodeId: s,
          sourcePortId: sp,
          targetNodeId: t,
          targetPortId: tp,
          label: label,
          animated: animated);
  return (
    nodes,
    [
      e('e1', 'p1', 'out', 's1', 'a'),
      e('e2', 'p2', 'out', 's1', 'b'),
      e('e3', 'p3', 'out', 's2', 'a'),
      e('e4', 'p4', 'out', 's2', 'b'),
      e('e5', 's1', 'out', 's3', 'a', 'Chasis'),
      e('e6', 's2', 'out', 's3', 'b', 'Electrónica'),
      e('e7', 's3', 'out', 'pr', 'in', null, true),
      e('e8', 'pr', 'out', 'wh', 'in', 'Embalaje', true),
      e('e9', 'p5', 'out', 's3', 'a'),
    ],
  );
}

(List<NodeData<Item>>, List<EdgeData>) _distribution() {
  final nodes = <NodeData<Item>>[
    makeNode('sup1', 'supplier', 'Aceros del Norte'),
    makeNode('sup2', 'supplier', 'Plásticos MX'),
    makeNode('cen', 'warehouse', 'CEDIS Central', subtitle: '12 000 m²'),
    makeNode('r1', 'warehouse', 'CEDIS Norte'),
    makeNode('r2', 'warehouse', 'CEDIS Sur'),
    makeNode('t1', 'transport', 'Ruta 14', subtitle: 'Camión 3.5 t'),
    makeNode('b1', 'branch', 'Sucursal Monterrey'),
    makeNode('b2', 'branch', 'Sucursal Saltillo'),
    makeNode('b3', 'branch', 'Sucursal Mérida'),
    makeNode('c1', 'customer', 'Constructora Delta'),
    makeNode('c2', 'customer', 'Pedido online #8812'),
  ];
  var k = 0;
  EdgeData e(String s, String t, [String? label, bool animated = true]) =>
      EdgeData(
          id: 'd${k++}',
          sourceNodeId: s,
          sourcePortId: 'out',
          targetNodeId: t,
          targetPortId: 'in',
          label: label,
          animated: animated);
  return (
    nodes,
    [
      e('sup1', 'cen', 'Acero'),
      e('sup2', 'cen', 'Resinas'),
      e('cen', 'r1', 'Semanal'),
      e('cen', 'r2', 'Quincenal'),
      e('r1', 't1'),
      e('t1', 'b1'),
      e('t1', 'b2'),
      e('r2', 'b3', 'Ruta 22'),
      e('b1', 'c1', 'Entrega', false),
      e('r1', 'c2', 'Paquetería', false),
    ],
  );
}

(List<NodeData<Item>>, List<EdgeData>) _inventory() {
  final nodes = <NodeData<Item>>[
    makeNode('root', 'category', 'Inventario general'),
    makeNode('herr', 'category', 'Herramientas', parentId: 'root'),
    makeNode('elec', 'category', 'Material eléctrico', parentId: 'root'),
    makeNode('plom', 'category', 'Plomería', parentId: 'root'),
    makeNode('herr-e', 'category', 'Eléctricas', parentId: 'herr'),
    makeNode('herr-m', 'category', 'Manuales', parentId: 'herr'),
  ];
  final rnd = math.Random(7);
  var i = 0;
  for (final (parent, items) in [
    ('herr-e', ['Taladro TX-200', 'Esmeriladora 4"']),
    ('herr-m', ['Martillo 16oz', 'Juego de llaves']),
    ('elec', ['Cable THW 12', 'Contacto doble', 'Foco LED 9W']),
    ('plom', ['Tubo PVC 1/2"', 'Llave de paso']),
  ]) {
    for (final name in items) {
      final max = 100 + rnd.nextInt(400);
      nodes.add(makeNode('prod${i++}', 'product', name,
          subtitle: 'SKU ${1000 + i * 37}',
          parentId: parent,
          withPorts: false,
          data: {'stock': rnd.nextInt(max), 'max': max}));
    }
  }
  return (nodes, const []);
}

(List<NodeData<Item>>, List<EdgeData>) _mindMap() {
  final tree = <(String, String, String?)>[
    ('m', 'Optimizar inventario', null),
    ('m1', 'Reducir merma', 'm'),
    ('m2', 'Rotación de stock', 'm'),
    ('m3', 'Proveedores', 'm'),
    ('m4', 'Tecnología', 'm'),
    ('m11', 'Control de caducidad', 'm1'),
    ('m12', 'Auditorías mensuales', 'm1'),
    ('m21', 'Análisis ABC', 'm2'),
    ('m22', 'FIFO en almacén', 'm2'),
    ('m23', 'Liquidar lento movimiento', 'm2'),
    ('m31', 'Negociar consignación', 'm3'),
    ('m32', 'Evaluar tiempos de entrega', 'm3'),
    ('m41', 'Lectores de código', 'm4'),
    ('m42', 'Alertas de reorden', 'm4'),
    ('m43', 'Este editor de nodos', 'm4'),
  ];
  const palette = [
    Color(0xFFEF4444),
    Color(0xFF10B981),
    Color(0xFF3B82F6),
    Color(0xFFF59E0B),
  ];
  final branchColor = <String, Color>{};
  var b = 0;
  return (
    [
      for (final (id, title, parent) in tree)
        makeNode(
          id,
          'idea',
          title,
          parentId: parent,
          color: parent == null
              ? null
              : (parent == 'm'
                  ? (branchColor[id] = palette[b++ % palette.length])
                  : branchColor[id] = branchColor[parent]!),
        ),
    ],
    const [],
  );
}

(List<NodeData<Item>>, List<EdgeData>) _stress(int count) {
  const types = ['product', 'warehouse', 'branch', 'part', 'supplier'];
  final rnd = math.Random(1);
  final nodes = [
    for (var i = 0; i < count; i++)
      makeNode('s$i', types[i % types.length], 'Elemento $i',
          subtitle: 'Lote ${rnd.nextInt(9999)}',
          data: {'stock': rnd.nextInt(100), 'max': 100}),
  ];
  final edges = <EdgeData>[];
  for (var i = 1; i < count; i++) {
    final j = math.max(0, i - 1 - rnd.nextInt(60));
    edges.add(EdgeData(id: 'se$i', sourceNodeId: 's$j', targetNodeId: 's$i'));
  }
  return (nodes, edges);
}

(List<NodeData<Item>>, List<EdgeData>) _process() {
  final nodes = <NodeData<Item>>[
    makeNode('start', 'milestone', 'Pedido recibido',
        color: const Color(0xFF22C55E)),
    makeNode('val', 'process', 'Validar pedido', subtitle: 'Pago y datos'),
    makeNode('stock', 'decision', '¿Hay stock?'),
    makeNode('prov', 'frame', 'Pedir a proveedor', subtitle: '3 a 5 días'),
    makeNode('prep', 'warehouse', 'Preparar envío',
        subtitle: 'Almacén central', withPorts: false),
    makeNode('ruta', 'tag', 'En ruta'),
    makeNode('end', 'milestone', 'Entregado', color: const Color(0xFFEF4444)),
    makeNode('nota', 'note', 'Revisar caducidad antes de enviar'),
  ];
  // Iconos propios por nodo (claves de `NodeIcons.all`).
  nodes[5] = nodes[5].copyWith(style: const NodeStyle(icon: 'truck'));
  nodes[0] = nodes[0].copyWith(style: const NodeStyle(icon: 'play'));
  nodes[6] = nodes[6].copyWith(style: const NodeStyle(icon: 'check'));
  var k = 0;
  EdgeData e(String s, String t,
          {String? label, bool dashed = false, bool arrow = true}) =>
      EdgeData(
          id: 'f${k++}',
          sourceNodeId: s,
          targetNodeId: t,
          label: label,
          dashed: dashed,
          arrow: arrow);
  return (
    nodes,
    [
      e('start', 'val'),
      e('val', 'stock'),
      e('stock', 'prep', label: 'Sí'),
      e('stock', 'prov', label: 'No'),
      e('prov', 'prep'),
      e('prep', 'ruta'),
      e('ruta', 'end'),
      e('nota', 'ruta', dashed: true, arrow: false),
    ],
  );
}

/// Posiciones fijas del diagrama de proceso (con ramas arriba y abajo).
const _processPositions = <String, Offset>{
  'start': Offset(0, 0),
  'val': Offset(150, 8),
  'stock': Offset(410, -11),
  'prep': Offset(680, -4),
  'ruta': Offset(950, 22),
  'end': Offset(1190, 0),
  'prov': Offset(395, 180),
  'nota': Offset(930, 170),
};

/// Layout que coloca los nodos conocidos en posiciones dadas y deja el resto
/// donde están.
class _PresetLayout extends GraphLayout {
  const _PresetLayout(this.positions);

  final Map<String, Offset> positions;

  @override
  Map<String, Offset> compute(LayoutInput input) => {
        for (final n in input.nodes) n.id: positions[n.id] ?? n.position,
      };
}
