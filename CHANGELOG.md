## 1.0.0

Primera versión estable.

- Editor de nodos con lienzo infinito, culling por índice espacial, nivel de
  detalle y capa de conexiones cacheada.
- Nodos con cualquier widget como cuerpo, formas (tarjeta, caja, píldora,
  círculo, rombo, hexágono), colores, iconos y bordes sólidos, discontinuos o
  punteados.
- Puertos tipados, conexiones (Bézier, ortogonal, recta) con etiquetas,
  flechas, trazo discontinuo y flujo animado; creación, reconexión y trazado
  libre desde la UI.
- Jerarquía padre → hijo con colapsar/expandir, re-parentado y enlaces
  editables.
- Historial de deshacer/rehacer, guías de alineación, redimensionado, atajos
  de teclado, auto-organización (árbol, capas, radial, mapa mental, rejilla)
  y serialización JSON.
- Animaciones opcionales.
- La aplicación construye toda la interfaz: `onContextMenu`,
  `selectionOverlayBuilder`, `EditorTarget` / `EditorAction`,
  `NodePreview` y `NodeEditorMinimap` como pieza independiente.
