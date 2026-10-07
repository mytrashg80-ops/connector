## 0.7.0

- **La interfaz la construye la aplicación.** El editor ya no añade controles,
  minimapa ni el botón × de la línea seleccionada por defecto
  (`showControls`, `showMinimap` y el nuevo `showEdgeDeleteButton` son
  `false`); siguen disponibles como piezas opcionales.
- `NodeEditor.onContextMenu` (`EditorContextMenuDetails`): un único callback
  para el clic derecho / pulsación larga con el destino (`EditorTarget`:
  `NodeTarget`, `SelectionTarget`, `EdgeTarget`, `LinkTarget`,
  `CanvasTarget`), las posiciones y las acciones disponibles.
- `NodeEditor.selectionOverlayBuilder` (`EditorSelectionDetails`): barra de
  acciones propia junto a la selección, colocada y movida por el editor.
- `EditorAction` / `EditorCommand` y `controller.actionsFor`, `actionFor`,
  `targetForNode`: operaciones listas para ejecutar, sin texto ni icono.
- `controller.setNodeStyle` y `resetNodeStyle` (varios nodos, un paso de
  deshacer), `NodeShapes.suggestedSize` y el widget `NodePreview`.
- Ejemplo: menú contextual, barra flotante de la selección, controles de la
  cámara y diálogo de estilo construidos por la app (`editor_ui.dart`).

## 0.6.0

- **Formas de nodo** (`NodeShape`): tarjeta, caja, píldora, círculo con icono
  en el centro (y título debajo), rombo y hexágono.
- **Estilo por nodo** con `NodeData.style` (`NodeStyle`): forma, icono,
  relleno o sólo líneas, color de relleno, color/grosor/trazo del borde
  (`NodeBorderStyle.solid`, `dashed`, `dotted`, `none`) y color del texto.
  Se serializa a JSON y forma parte del historial.
- `NodeTypeStyle` acepta `shape`, `filled`, `borderStyle` y `borderWidth`
  para dar estilo a todo un tipo.
- Iconos por clave: `NodeIcons.all` y `NodeEditorTheme.icons` (ampliable).
- `NodeEditorTheme.resolveNodeStyle`, `shapeOf`, `anchorRect` y
  `portLocalPosition`; `NodeShapes` (siluetas) y `NodeShapePainter`.
- `NodeData.copyWith(clearColor:, clearStyle:)`.
- Las líneas se anclan a la silueta, los puertos se colocan en su borde y la
  vista lejana (LOD) dibuja cada forma.
- Ejemplo: tipos Hito, Decisión, Proceso, Etiqueta, Marco y Nota; diálogo
  "Forma, color e icono" en el menú del nodo (también para varios nodos);
  escenario "Diagrama de proceso".

## 0.5.0

- **Crear conectores de cualquier tipo desde la UI:** tiradores **+** en los
  lados del nodo bajo el ratón o del seleccionado (también en táctil).
  Arrastrar uno hasta otro nodo crea un enlace de jerarquía padre → hijo o
  una conexión, con o sin puertos (`NodeEditorConfig.connectorHandles`,
  `NodeEditorConfig.newConnector`).
- Nuevo `ConnectorStyle` / `ConnectorKind` (`ConnectorStyle.hierarchy`):
  curva, color, grosor, discontinua, flecha, animada y etiqueta de los
  conectores nuevos. `NodeEditorController.connect(style:)`.
- La jerarquía creada así se valida (ciclos, `canReparent`), avisa por
  `onParentChanged` y explica el rechazo en `onConnectionRejected`.
- `ConnectionDropDetails.style` dice qué conector se soltó en el vacío.
- Las conexiones desde puertos usan el estilo de `newConnector`.
- Ejemplo: selector "Conector" en la barra (jerarquía, flujo, ortogonal,
  recta, discontinua, animada). Soltar en el vacío crea un hijo o un nodo
  conectado según el tipo.

## 0.4.0

- **Animaciones opcionales** (`NodeEditorConfig.animations`,
  `NodeEditorAnimations`, `NodeEditorAnimations.none`):
  - nodos que aparecen creciendo y desaparecen encogiéndose;
  - al arrastrar, los nodos se levantan con sombra y al soltarlos se asientan
    con un rebote;
  - los nodos se deslizan cuando su posición cambia fuera de un arrastre
    (deshacer/rehacer, auto-organizar, teclado, API);
  - plegar y desplegar ramas recoge y saca los hijos del padre;
  - las conexiones y enlaces nuevos se dibujan y los borrados se desvanecen;
  - transiciones de cámara: `fitView(animate:)`, `centerOnNode(animate:)`,
    `NodeViewport.zoomBy(animate:)`, `centerOn(animate:)`,
    `fitRect(animate:)`, `animateTo`, `isAnimating` y `stopAnimation`.
    Los botones de zoom y ajustar y los atajos de teclado las usan.
- Las animaciones son sólo visuales (el modelo cambia al instante), respetan
  "reducir movimiento" del sistema y no cuestan nada en reposo.
- `NodeEditorController.isAnimatingLayout`. `applyLayout(fitAfter: true)`
  encuadra con una transición de cámara.
- Ejemplo: botón "Animaciones" para activarlas o desactivarlas.

## 0.3.0

- **Enlaces de jerarquía editables:** las líneas padre → hijo se resaltan,
  se seleccionan (`selectLinks`, `selectedLinkIds`, `toggleLinkSelection`),
  se borran con × o Supr (el hijo pasa a raíz) y sus extremos se arrastran
  para cambiar el padre o pasar el enlace a otro nodo
  (`NodeEditorController.moveLinkToChild`). Nuevos `onLinkTap` y
  `onLinkContextMenu`. `deleteSelection` también rompe los enlaces
  seleccionados.
- **Trazado manual de líneas:** arrastrar una conexión o un enlace hace que
  pase por ese punto (`EdgeData.bend`, `NodeData.linkBend`,
  `setEdgeBend`, `setLinkBend`, `buildEdgeGeometry(via:)`). El punto es
  relativo a los nodos, así que los acompaña; volver a su sitio la endereza.
  Los extremos sin puerto salen por el lado que mira al punto de paso.
- **Guías de alineación** al arrastrar y redimensionar, con imán
  (`NodeEditorConfig.enableAlignmentGuides`, `alignmentSnapDistance`,
  `NodeEditorTheme.alignmentGuideColor`, `AlignmentSnapper`). Ctrl/⌘ las
  desactiva mientras se mantiene.
- Ejemplo: menú contextual de los enlaces y "Enderezar trazado"; corregido un
  fallo al romper un enlace (`onParentChanged` con padre `null`).

## 0.2.0

- **Arrastre en tiempo real:** los nodos siguen al puntero mientras se
  arrastran (antes sólo se veían al soltar). Nuevo
  `beginHistoryGroup` / `endHistoryGroup` para agrupar un gesto en un paso
  de deshacer sin retener las notificaciones.
- **Redimensionar nodos** arrastrando sus bordes (ratón) o las esquinas del
  nodo seleccionado (táctil), con tamaño visible mientras se arrastra.
  `NodeEditorConfig.enableNodeResize`, `minNodeSize`, `NodeEditor.canResize`,
  `onNodeResized` y `NodeEditorController.setNodeRect`.
- **Editar conexiones:** resaltado al pasar el ratón, tiradores en los
  extremos, botón de borrar en la conexión seleccionada, arrastrar un
  extremo para reconectar o soltarlo en el vacío para desconectar,
  Ctrl/⌘ + arrastrar un puerto para mover su conexión y Alt + clic para
  romperlas. `NodeEditorConfig.enableEdgeEditing`, `onEdgeReconnected`,
  `onEdgeDisconnected` y `NodeEditorController.reconnectEdge`.
- Cursores del ratón según lo que hay debajo (mover, conectar, redimensionar).
- `NodeEditorState.showDropPreview` para mostrar la silueta de un elemento
  que se arrastra desde una paleta propia.
- `EdgeData.copyWith` admite `clearSourcePort` / `clearTargetPort`.

## 0.1.0

- Primera versión: `NodeEditor`, `NodeEditorController`, temas claro/oscuro,
  puertos tipados, conexiones (bézier, ortogonales, rectas, animadas),
  jerarquía con colapso, deshacer/rehacer, layouts automáticos, minimapa,
  controles y serialización JSON.
