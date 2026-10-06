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
