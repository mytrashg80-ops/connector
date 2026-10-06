import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../model/node.dart';
import '../model/port.dart';

/// Qué hace la rueda del ratón.
enum WheelBehavior {
  /// La rueda hace zoom (Ctrl/⌘ + rueda desplaza).
  zoom,

  /// La rueda desplaza (Ctrl/⌘ + rueda hace zoom).
  pan,
}

/// Cuándo soltar un nodo sobre otro lo convierte en su hijo.
enum ReparentMode {
  /// Nunca desde la UI (sólo por API).
  none,

  /// Sólo manteniendo Alt mientras se arrastra.
  withModifier,

  /// Siempre que se suelte encima de otro nodo.
  always,
}

/// Opciones de comportamiento del editor.
@immutable
class NodeEditorConfig {
  const NodeEditorConfig({
    this.readOnly = false,
    this.showGrid = true,
    this.snapToGrid = false,
    this.showMinimap = true,
    this.showControls = true,
    this.minimapAlignment = Alignment.bottomRight,
    this.controlsAlignment = Alignment.bottomLeft,
    this.minimapSize = const Size(200, 136),
    this.dragMovesDescendants = true,
    this.reparentMode = ReparentMode.withModifier,
    this.wheelBehavior = WheelBehavior.zoom,
    this.zoomStep = 1.2,
    this.lodScale = 0.3,
    this.labelMinScale = 0.45,
    this.cullMargin = 0.5,
    this.showHierarchyLinks = true,
    this.hierarchyAxis = Axis.vertical,
    this.enableKeyboardShortcuts = true,
    this.showPorts = true,
    this.marqueeOnEmptyDrag = false,
    this.doubleTapToFit = false,
    this.enableNodeResize = true,
    this.minNodeSize = const Size(72, 36),
    this.enableEdgeEditing = true,
  });

  /// Sólo permite navegar y seleccionar.
  final bool readOnly;
  final bool showGrid;
  final bool snapToGrid;
  final bool showMinimap;
  final bool showControls;
  final Alignment minimapAlignment;
  final Alignment controlsAlignment;
  final Size minimapSize;

  /// Al arrastrar un nodo se mueve todo su subárbol (como en mapas mentales).
  final bool dragMovesDescendants;
  final ReparentMode reparentMode;
  final WheelBehavior wheelBehavior;
  final double zoomStep;

  /// Por debajo de esta escala los nodos se pintan como rectángulos simples
  /// sin widgets (nivel de detalle). Permite ver miles de nodos con fluidez.
  final double lodScale;

  /// Por debajo de esta escala no se dibujan etiquetas de conexiones.
  final double labelMinScale;

  /// Margen (fracción del viewport) en el que se mantienen construidos los
  /// nodos fuera de pantalla para evitar reconstrucciones al desplazarse.
  final double cullMargin;

  /// Dibuja líneas padre → hijo para la jerarquía.
  final bool showHierarchyLinks;

  /// Eje de las líneas de jerarquía: vertical (organigrama) u horizontal
  /// (mapa mental / árbol de izquierda a derecha).
  final Axis hierarchyAxis;
  final bool enableKeyboardShortcuts;

  /// Dibuja los puertos sobre el widget de cada nodo.
  final bool showPorts;

  /// Si es `true`, arrastrar sobre el fondo crea una selección rectangular
  /// (y el desplazamiento se hace con botón central / dos dedos). Si es
  /// `false` se necesita Shift para la selección rectangular.
  final bool marqueeOnEmptyDrag;

  /// Doble toque en el fondo ajusta la vista.
  final bool doubleTapToFit;

  /// Permite redimensionar nodos arrastrando sus bordes (ratón) o las
  /// esquinas del nodo seleccionado (táctil). Usa `NodeEditor.canResize`
  /// para vetarlo por nodo.
  final bool enableNodeResize;

  /// Tamaño mínimo al redimensionar desde la UI.
  final Size minNodeSize;

  /// Permite editar conexiones existentes: arrastrar sus extremos para
  /// reconectarlas o soltarlas en el vacío para desconectarlas, y el botón
  /// de borrar de la conexión seleccionada.
  final bool enableEdgeEditing;

  NodeEditorConfig copyWith({
    bool? readOnly,
    bool? showGrid,
    bool? snapToGrid,
    bool? showMinimap,
    bool? showControls,
    Alignment? minimapAlignment,
    Alignment? controlsAlignment,
    Size? minimapSize,
    bool? dragMovesDescendants,
    ReparentMode? reparentMode,
    WheelBehavior? wheelBehavior,
    double? zoomStep,
    double? lodScale,
    double? labelMinScale,
    double? cullMargin,
    bool? showHierarchyLinks,
    Axis? hierarchyAxis,
    bool? enableKeyboardShortcuts,
    bool? showPorts,
    bool? marqueeOnEmptyDrag,
    bool? doubleTapToFit,
    bool? enableNodeResize,
    Size? minNodeSize,
    bool? enableEdgeEditing,
  }) {
    return NodeEditorConfig(
      readOnly: readOnly ?? this.readOnly,
      showGrid: showGrid ?? this.showGrid,
      snapToGrid: snapToGrid ?? this.snapToGrid,
      showMinimap: showMinimap ?? this.showMinimap,
      showControls: showControls ?? this.showControls,
      minimapAlignment: minimapAlignment ?? this.minimapAlignment,
      controlsAlignment: controlsAlignment ?? this.controlsAlignment,
      minimapSize: minimapSize ?? this.minimapSize,
      dragMovesDescendants: dragMovesDescendants ?? this.dragMovesDescendants,
      reparentMode: reparentMode ?? this.reparentMode,
      wheelBehavior: wheelBehavior ?? this.wheelBehavior,
      zoomStep: zoomStep ?? this.zoomStep,
      lodScale: lodScale ?? this.lodScale,
      labelMinScale: labelMinScale ?? this.labelMinScale,
      cullMargin: cullMargin ?? this.cullMargin,
      showHierarchyLinks: showHierarchyLinks ?? this.showHierarchyLinks,
      hierarchyAxis: hierarchyAxis ?? this.hierarchyAxis,
      enableKeyboardShortcuts:
          enableKeyboardShortcuts ?? this.enableKeyboardShortcuts,
      showPorts: showPorts ?? this.showPorts,
      marqueeOnEmptyDrag: marqueeOnEmptyDrag ?? this.marqueeOnEmptyDrag,
      doubleTapToFit: doubleTapToFit ?? this.doubleTapToFit,
      enableNodeResize: enableNodeResize ?? this.enableNodeResize,
      minNodeSize: minNodeSize ?? this.minNodeSize,
      enableEdgeEditing: enableEdgeEditing ?? this.enableEdgeEditing,
    );
  }
}

/// Estado visual de un nodo que recibe el `nodeBuilder`.
@immutable
class NodeViewState {
  const NodeViewState({
    this.selected = false,
    this.dropTarget = false,
    this.childCount = 0,
    this.connectedPorts = const {},
    this.readOnly = false,
    this.onToggleCollapsed,
  });

  final bool selected;

  /// Se está arrastrando otro nodo encima para convertirlo en hijo.
  final bool dropTarget;
  final int childCount;
  final Set<String> connectedPorts;
  final bool readOnly;

  /// Alterna el colapso de los hijos (null si no tiene hijos).
  final VoidCallback? onToggleCollapsed;

  bool get hasChildren => childCount > 0;

  @override
  bool operator ==(Object other) =>
      other is NodeViewState &&
      other.selected == selected &&
      other.dropTarget == dropTarget &&
      other.childCount == childCount &&
      other.readOnly == readOnly &&
      setEquals(other.connectedPorts, connectedPorts);

  @override
  int get hashCode => Object.hash(
      selected, dropTarget, childCount, readOnly, connectedPorts.length);
}

/// Construye el cuerpo visual de un nodo. Los puertos se dibujan encima
/// automáticamente (ver [NodeEditorConfig.showPorts]).
///
/// Devuelve `null` para usar el nodo por defecto.
typedef NodeWidgetBuilder<T> = Widget? Function(
    BuildContext context, NodeData<T> node, NodeViewState state);

/// Información de una conexión soltada sobre el fondo vacío.
@immutable
class ConnectionDropDetails<T> {
  const ConnectionDropDetails({
    required this.node,
    required this.port,
    required this.worldPosition,
    required this.globalPosition,
  });

  /// Nodo desde el que se arrastró.
  final NodeData<T> node;
  final NodePort? port;
  final Offset worldPosition;
  final Offset globalPosition;
}
