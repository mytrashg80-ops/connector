# connector

Editor de nodos de alto rendimiento para Flutter, al estilo de los Blueprints
de Unreal. Sirve para crear, conectar, mover y jerarquizar nodos, y está pensado
para integrarse como **un widget más** dentro de una app de inventario:

- Organigramas (jerarquía entre empleados)
- Estructura de la empresa y sus sucursales
- Cadenas de ensamblado y de distribución
- Estructura del inventario (categorías → productos)
- Mapas mentales libres, sin ninguna estructura impuesta

Funciona en **web, Windows, macOS, Linux, Android e iOS**. No tiene
dependencias aparte de Flutter.

| Cadena de ensamblado | Mapa mental |
|---|---|
| ![Ensamblado](doc/ensamblado.png) | ![Mapa mental](doc/mapa_mental.png) |
| **Organigrama** | **Distribución (tema claro)** |
| ![Organigrama](doc/organigrama.png) | ![Distribución](doc/distribucion_claro.png) |

## Características

| | |
|---|---|
| **Nodos** | Cualquier widget como cuerpo (`nodeBuilder`), tarjeta por defecto, tamaño fijo o `autoSize`, bloqueo, colores por tipo |
| **Puertos** | Entrada/salida/ambos, en los 4 lados, con etiqueta, tipo lógico para validar compatibilidad y máximo de conexiones |
| **Conexiones** | Bézier, ortogonal redondeada, ortogonal, recta. Etiquetas, flechas, trazo discontinuo, flujo animado. Conexiones "flotantes" sin puertos |
| **Editar conexiones** | Resaltado al pasar el ratón, arrastrar un extremo para reconectar (o soltarlo en el vacío para desconectar), botón × en la conexión seleccionada, Alt + clic en un puerto para romper sus conexiones |
| **Tamaño** | Redimensionar arrastrando los bordes (ratón) o las esquinas del nodo seleccionado (táctil), con tamaño mínimo e imán a la rejilla |
| **Jerarquía** | `parentId` con detección de ciclos, colapsar/expandir subárboles, arrastrar un padre mueve su subárbol, **Alt + soltar** sobre otro nodo para asignarle padre |
| **Interacción** | Todo se ve en tiempo real mientras arrastras. Pan, zoom con rueda, pinza y trackpad, selección múltiple (Shift/Ctrl, rectángulo con Shift+arrastrar), imán a la rejilla, menús contextuales (clic derecho o pulsación larga), cursores según lo que hay debajo |
| **Edición** | Deshacer/rehacer con transacciones, duplicar, borrar, atajos de teclado |
| **Auto-organización** | `TreeLayout`, `LayeredLayout` (tipo Sugiyama), `RadialLayout`, `MindMapLayout`, `GridLayout`, con animación opcional |
| **Extras** | Minimapa, controles de zoom, serialización JSON, tema claro/oscuro totalmente personalizable |

## Instalación

```yaml
dependencies:
  connector:
    git:
      url: https://github.com/mytrashg80-ops/connector
```

## Uso rápido

```dart
import 'package:connector/connector.dart';

final controller = NodeEditorController<Producto>(
  nodes: [
    NodeData(
      id: 'almacen',
      type: 'warehouse',
      title: 'Almacén central',
      position: const Offset(0, 0),
      ports: const [NodePort.output(id: 'out', label: 'Despacha')],
    ),
    NodeData(
      id: 'sucursal',
      type: 'branch',
      title: 'Sucursal Norte',
      position: const Offset(320, 0),
      ports: const [NodePort.input(id: 'in', label: 'Recibe')],
    ),
  ],
);

controller.connect(
  sourceNodeId: 'almacen', sourcePortId: 'out',
  targetNodeId: 'sucursal', targetPortId: 'in',
  label: 'Semanal',
);

// En tu árbol de widgets (necesita un tamaño acotado):
NodeEditor<Producto>(
  controller: controller,
  theme: isDark ? NodeEditorTheme.dark() : NodeEditorTheme.light(),
  onNodeTap: (node) => abrirDetalle(node.data),
)
```

Hay una app de demostración completa en [`example/`](example/lib/main.dart)
(`cd example && flutter run -d chrome`) con 7 escenarios: organigrama, empresa y
sucursales, cadena de ensamblado, distribución, inventario, mapa mental y una
prueba de estrés con 3000 nodos.

## Modelo de datos

- **`NodeData<T>`**: inmutable. `id`, `position`, `size`, `type`, `title`,
  `subtitle`, `data` (tu objeto de negocio `T`), `ports`, `parentId`,
  `collapsed`, `locked`, `autoSize` y `color`.
- **`NodePort`**: `NodePort.input(...)`, `NodePort.output(...)` o `NodePort(direction: PortDirection.both)`.
  Usa `type` para impedir conexiones incompatibles y `maxConnections` para limitarlas.
- **`EdgeData`**: conexión dirigida entre nodos/puertos con `label`, `curve`,
  `color`, `width`, `dashed`, `animated`, `arrow` y `metadata`.

## Controlador

```dart
// Grafo
controller.addNode(nodo);
controller.updateNode(id, (n) => n.copyWith(title: 'Nuevo'));
controller.moveNodes(ids, const Offset(10, 0), includeDescendants: true);
controller.removeNodes(ids, withDescendants: false);
controller.connect(...);              // valida; devuelve null si no es válida
controller.checkConnection(...);      // motivo del rechazo
controller.connectionValidator = (r) => r.target.type == 'customer' ? null : 'Sólo clientes';
controller.reconnectEdge(edgeId, moveSource: false, nodeId: 'otro', portId: 'in');
controller.setNodeRect(id, const Rect.fromLTWH(0, 0, 240, 120)); // posición + tamaño

// Jerarquía
controller.setParent('empleado', 'jefe');   // false si crearía un ciclo
controller.childrenOf(id); controller.descendantsOf(id); controller.ancestorsOf(id);
controller.toggleCollapsed(id);

// Selección, cámara e historial
controller.selectNodes(ids); controller.selectedNodeIds;
controller.fitView(); controller.centerOnNode(id); controller.viewport.zoomBy(1.2);
controller.transaction(() { /* varias operaciones = un paso de deshacer */ });
controller.beginHistoryGroup(); /* gesto largo: notifica al momento */ controller.endHistoryGroup();
controller.undo(); controller.redo();

// Auto-organización (animada si pasas vsync)
await controller.applyLayout(const TreeLayout(), vsync: this, fitAfter: true);

// Persistencia
final json = controller.toJson(encodeData: (p) => p?.toJson());
controller.loadJson(json, decodeData: (raw) => Producto.fromJson(raw as Map));
```

El controlador es un `ChangeNotifier`, y además expone notificadores de grano
fino: `geometry`, `structure`, `edgesSignal`, `selection` y `history`. Escucha
sólo el que necesites; por ejemplo, una barra de estado que escuche
`structure` no se reconstruye mientras arrastras nodos.

## Nodos personalizados

```dart
NodeEditor<Empleado>(
  controller: controller,
  nodeBuilder: (context, node, state) {
    if (node.type != 'employee') return null; // null = tarjeta por defecto
    return MiTarjetaEmpleado(
      empleado: node.data!,
      seleccionado: state.selected,
      onColapsar: state.onToggleCollapsed,
    );
  },
)
```

- Los puertos se dibujan encima automáticamente (`NodeEditorConfig.showPorts`).
- `DefaultNodeBody(node:, state:, content:)` reutiliza la tarjeta por defecto
  y te deja añadir contenido propio (p. ej. una barra de stock).
- `NodeEditorScope.themeOf(context)` da acceso al tema dentro del nodo.
- El widget de cada nodo se cachea y **sólo se reconstruye cuando cambia su
  contenido o su estado** (selección, conexiones...). Moverlo no lo reconstruye.
  Por eso no conviene que tu `nodeBuilder` dependa de `node.position`.

## Tema (claro / oscuro / tus colores)

```dart
final temaOscuro = NodeEditorTheme.dark(
  accent: Colors.teal,
  nodeTypes: {
    'warehouse': NodeTypeStyle(label: 'Almacén', icon: Icons.warehouse, color: Colors.amber),
    'employee': NodeTypeStyle(label: 'Empleado', icon: Icons.person, color: Colors.purple),
  },
).copyWith(
  edgeCurve: EdgeCurve.smoothStep,
  gridStyle: GridStyle.lines,
  nodeRadius: 14,
);
```

- `NodeEditorTheme.light()`, `.dark()` y `.fromColorScheme(scheme)`.
- Unas 60 propiedades: fondo, rejilla, nodos, cabeceras, puertos,
  conexiones, etiquetas, enlaces de jerarquía, selección, minimapa y controles.
- También es un `ThemeExtension`: regístralo en tu `ThemeData` y el editor lo
  usará automáticamente. Si no pasas ninguno, el editor elige el claro o el
  oscuro según `Theme.of(context).brightness`.
- **Consejo de rendimiento:** crea los temas una sola vez (en un campo o en tu
  `ThemeData`), no dentro de `build`. El editor usa la identidad del tema para
  saber cuándo invalidar sus cachés.

## Configuración

`NodeEditorConfig` permite: `readOnly`, `showGrid`, `snapToGrid`,
`showMinimap`, `showControls`, `dragMovesDescendants`, `reparentMode`
(`none` / `withModifier` / `always`), `wheelBehavior` (`zoom` / `pan`),
`lodScale`, `labelMinScale`, `cullMargin`, `showHierarchyLinks`,
`hierarchyAxis`, `enableKeyboardShortcuts`, `marqueeOnEmptyDrag`,
`enableNodeResize`, `minNodeSize`, `enableEdgeEditing`...

Callbacks del widget: `onNodeTap`, `onNodeDoubleTap`, `onNodeContextMenu`,
`onEdgeTap`, `onEdgeContextMenu`, `onCanvasTap`, `onCanvasContextMenu`,
`onConnect`, `onConnectionRejected`, `onConnectionDropped` (para crear un nodo
ya conectado al soltar una conexión en el vacío), `onNodesMoved`,
`onParentChanged`, `canReparent`, `onNodeResized`, `canResize`,
`onEdgeReconnected` y `onEdgeDisconnected`.

Para soltar elementos desde tu propia paleta usa un `DragTarget` y
`GlobalKey<NodeEditorState<T>>().currentState!.globalToWorld(offset)`. Con
`showDropPreview(rect)` en `onMove` el editor dibuja la silueta del nodo donde
caerá (y `showDropPreview(null)` en `onLeave` / al soltar). Hay un ejemplo
completo en `example/lib/main.dart`.

### Atajos

| Acción | Atajo |
|---|---|
| Zoom | Rueda, pinza, trackpad, `+` / `-` |
| Desplazar | Arrastrar el fondo, botón central, dos dedos |
| Selección múltiple | Shift/Ctrl + clic, Shift + arrastrar (rectángulo), Ctrl+A |
| Conectar | Arrastrar desde un puerto de salida |
| Mover una conexión | Arrastrar su extremo (si está seleccionada o bajo el ratón), arrastrar desde una entrada ya conectada, o Ctrl/⌘ + arrastrar desde cualquier puerto |
| Desconectar | Soltar el extremo en el vacío, botón × de la conexión seleccionada, Supr, o Alt + clic en el puerto |
| Redimensionar | Arrastrar un borde o una esquina del nodo |
| Asignar padre | Mantener **Alt** al soltar un nodo sobre otro |
| Menú contextual | Clic derecho o pulsación larga |
| Eliminar | Supr / Retroceso |
| Deshacer / Rehacer | Ctrl/⌘+Z · Ctrl/⌘+Shift+Z · Ctrl+Y |
| Duplicar | Ctrl/⌘+D |
| Ajustar vista | F |
| Mover selección | Flechas (Shift = paso de rejilla) |

## Rendimiento

El editor está pensado para convivir con el resto de tu app sin acaparar
recursos:

1. **Culling con índice espacial.** Una rejilla hash (`SpatialIndex`) responde
   en O(celdas) qué nodos están cerca del viewport. Sólo esos nodos existen
   como widgets, aunque el grafo tenga miles.
2. **La cámara es una transformación de capa.** Al desplazar o hacer zoom no se
   reconstruye ni se vuelve a medir ningún widget: cada nodo es un
   `RepaintBoundary` y sólo se recompone la escena.
3. **Mover nodos sólo recoloca.** Arrastrar dispara un relayout que no vuelve a
   medir a los hijos (sus restricciones no cambian) y no reconstruye widgets.
4. **Conexiones en una capa cacheada.** Las líneas se pintan en una capa propia
   que sólo se repinta cuando cambia el grafo o la cámara sale de la región
   precalculada. La geometría de cada conexión se cachea y sólo se recalcula si
   se mueve alguno de sus extremos.
5. **Nivel de detalle (LOD).** Por debajo de `lodScale` los nodos se pintan como
   rectángulos simples, sin widgets. En la prueba de 3000 nodos, la vista
   general no construye ningún widget de nodo.
6. **Notificaciones de grano fino.** Cada capa escucha sólo lo que necesita, y la
   barra de estado o el minimapa no se recalculan al mover la cámara.
7. **Sin trabajo en reposo.** No hay timers ni tickers activos salvo que existan
   conexiones `animated: true`. El minimapa graba los nodos en una `Picture`
   que reutiliza mientras el grafo no cambie.
8. **Ayudas de edición en su propia capa.** El resaltado, los tiradores y el
   tamaño al redimensionar se pintan en una capa aparte, que sólo dibuja algo
   cuando hay una conexión bajo el ratón o algo seleccionado. Los gestos
   largos (arrastrar, redimensionar) agrupan el historial sin retener las
   notificaciones, así que se ven en tiempo real y siguen siendo un único paso
   de deshacer.

## Tests

```bash
flutter test
```

Cubren el modelo, la validación de conexiones, la jerarquía, el historial, la
serialización, el índice espacial, los layouts y la interacción del widget
(arrastrar, desplazar, conectar, LOD, cambio de tema y culling con 5000 nodos).
