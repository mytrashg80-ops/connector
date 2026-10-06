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
    this.enableAlignmentGuides = true,
    this.alignmentSnapDistance = 6,
    this.animations = const NodeEditorAnimations(),
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

  /// Al arrastrar o redimensionar nodos muestra guías cuando sus bordes o
  /// centros quedan alineados con los de otros nodos visibles, y los atrae
  /// a esa posición. Mantén Ctrl/⌘ pulsado para desactivarlo un momento.
  final bool enableAlignmentGuides;

  /// Distancia (en píxeles de pantalla) a la que una guía atrae al nodo.
  final double alignmentSnapDistance;

  /// Animaciones de la interfaz (aparecer, borrar, arrastrar, deshacer,
  /// plegar ramas, cámara…). Usa [NodeEditorAnimations.none] para
  /// desactivarlas todas.
  final NodeEditorAnimations animations;

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
    bool? enableAlignmentGuides,
    double? alignmentSnapDistance,
    NodeEditorAnimations? animations,
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
      enableAlignmentGuides:
          enableAlignmentGuides ?? this.enableAlignmentGuides,
      alignmentSnapDistance:
          alignmentSnapDistance ?? this.alignmentSnapDistance,
      animations: animations ?? this.animations,
    );
  }
}

/// Qué animaciones usa el editor y cómo.
///
/// Las animaciones son sólo visuales: el modelo (posiciones, nodos,
/// conexiones, historial, JSON) cambia al instante y la animación muestra la
/// transición encima. Si el sistema pide reducir el movimiento
/// (`MediaQuery.disableAnimations`) se desactivan solas, salvo que
/// [respectReduceMotion] sea `false`.
///
/// ```dart
/// NodeEditor(
///   controller: controller,
///   config: const NodeEditorConfig(
///     animations: NodeEditorAnimations(nodeExit: false),
///     // o NodeEditorAnimations.none para ninguna
///   ),
/// )
/// ```
@immutable
class NodeEditorAnimations {
  const NodeEditorAnimations({
    this.enabled = true,
    this.duration = const Duration(milliseconds: 260),
    this.curve = Curves.easeOutCubic,
    this.nodeEnter = true,
    this.nodeExit = true,
    this.dragLift = true,
    this.liftScale = 1.04,
    this.moveTransitions = true,
    this.collapse = true,
    this.edgeEnter = true,
    this.edgeExit = true,
    this.camera = true,
    this.cameraDuration = const Duration(milliseconds: 380),
    this.maxAnimatedNodes = 250,
    this.respectReduceMotion = true,
  });

  /// Sin ninguna animación.
  static const none = NodeEditorAnimations(enabled: false);

  /// Interruptor general.
  final bool enabled;

  /// Duración de las animaciones de nodos y conexiones.
  final Duration duration;

  /// Curva de los desplazamientos (deshacer, auto-organizar, plegar…).
  final Curve curve;

  /// Los nodos nuevos aparecen creciendo (al crearlos, pegarlos, duplicarlos
  /// o al deshacer un borrado).
  final bool nodeEnter;

  /// Los nodos borrados se encogen y se desvanecen.
  final bool nodeExit;

  /// Al arrastrar, los nodos se "levantan" (crecen un poco y proyectan
  /// sombra) y al soltarlos se asientan con un pequeño rebote.
  final bool dragLift;

  /// Escala de los nodos levantados.
  final double liftScale;

  /// Los nodos se deslizan a su nueva posición cuando ésta cambia fuera de
  /// un arrastre: deshacer/rehacer, auto-organizar, flechas del teclado o
  /// cambios hechos por API.
  final bool moveTransitions;

  /// Al plegar una rama sus nodos se recogen hacia el padre; al desplegarla
  /// salen de él.
  final bool collapse;

  /// Las conexiones y enlaces nuevos se dibujan desde el origen.
  final bool edgeEnter;

  /// Las conexiones y enlaces eliminados se desvanecen.
  final bool edgeExit;

  /// Transiciones suaves de cámara al ajustar la vista o hacer zoom con los
  /// botones y el teclado (`fitView(animate: true)` y similares).
  final bool camera;
  final Duration cameraDuration;

  /// Si un cambio afecta a más nodos que esto, se aplica sin animar (p. ej.
  /// al cargar un documento entero).
  final int maxAnimatedNodes;

  /// Desactiva las animaciones si el sistema pide reducir el movimiento.
  final bool respectReduceMotion;

  NodeEditorAnimations copyWith({
    bool? enabled,
    Duration? duration,
    Curve? curve,
    bool? nodeEnter,
    bool? nodeExit,
    bool? dragLift,
    double? liftScale,
    bool? moveTransitions,
    bool? collapse,
    bool? edgeEnter,
    bool? edgeExit,
    bool? camera,
    Duration? cameraDuration,
    int? maxAnimatedNodes,
    bool? respectReduceMotion,
  }) {
    return NodeEditorAnimations(
      enabled: enabled ?? this.enabled,
      duration: duration ?? this.duration,
      curve: curve ?? this.curve,
      nodeEnter: nodeEnter ?? this.nodeEnter,
      nodeExit: nodeExit ?? this.nodeExit,
      dragLift: dragLift ?? this.dragLift,
      liftScale: liftScale ?? this.liftScale,
      moveTransitions: moveTransitions ?? this.moveTransitions,
      collapse: collapse ?? this.collapse,
      edgeEnter: edgeEnter ?? this.edgeEnter,
      edgeExit: edgeExit ?? this.edgeExit,
      camera: camera ?? this.camera,
      cameraDuration: cameraDuration ?? this.cameraDuration,
      maxAnimatedNodes: maxAnimatedNodes ?? this.maxAnimatedNodes,
      respectReduceMotion: respectReduceMotion ?? this.respectReduceMotion,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is NodeEditorAnimations &&
      other.enabled == enabled &&
      other.duration == duration &&
      other.curve == curve &&
      other.nodeEnter == nodeEnter &&
      other.nodeExit == nodeExit &&
      other.dragLift == dragLift &&
      other.liftScale == liftScale &&
      other.moveTransitions == moveTransitions &&
      other.collapse == collapse &&
      other.edgeEnter == edgeEnter &&
      other.edgeExit == edgeExit &&
      other.camera == camera &&
      other.cameraDuration == cameraDuration &&
      other.maxAnimatedNodes == maxAnimatedNodes &&
      other.respectReduceMotion == respectReduceMotion;

  @override
  int get hashCode => Object.hash(
        enabled,
        duration,
        curve,
        nodeEnter,
        nodeExit,
        dragLift,
        liftScale,
        moveTransitions,
        collapse,
        edgeEnter,
        edgeExit,
        camera,
        cameraDuration,
        maxAnimatedNodes,
        respectReduceMotion,
      );
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
