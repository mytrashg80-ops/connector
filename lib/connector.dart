/// Editor de nodos de alto rendimiento para Flutter.
///
/// Crea, conecta, mueve y jerarquiza nodos: organigramas, sucursales,
/// cadenas de ensamblado y distribución, inventarios y mapas mentales.
library;

export 'src/controller/editor_actions.dart';
export 'src/controller/node_editor_controller.dart';
export 'src/controller/spatial_index.dart';
export 'src/controller/viewport.dart';
export 'src/geometry/edge_path.dart' show EdgeGeometry, buildEdgeGeometry;
export 'src/geometry/node_geometry.dart';
export 'src/geometry/node_shapes.dart';
export 'src/layout/graph_layout.dart';
export 'src/layout/layouts.dart';
export 'src/model/connection.dart';
export 'src/model/connector_style.dart';
export 'src/model/edge.dart';
export 'src/model/node.dart';
export 'src/model/node_style.dart';
export 'src/model/port.dart';
export 'src/theme/node_editor_theme.dart';
export 'src/theme/node_icons.dart';
export 'src/widgets/alignment_guides.dart';
export 'src/widgets/default_node.dart';
export 'src/widgets/editor_config.dart';
export 'src/widgets/minimap.dart';
export 'src/widgets/node_editor.dart';
export 'src/widgets/node_preview.dart';
