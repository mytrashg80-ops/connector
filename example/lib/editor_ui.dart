// Interfaz propia de la aplicación alrededor del editor: menú contextual,
// barra de acciones de la selección y controles de la cámara.
//
// El paquete `connector` no construye nada de esto. Sólo entrega qué hay bajo
// el puntero o seleccionado (`EditorTarget`) y las operaciones que sabe hacer
// (`EditorAction`). Aquí decidimos textos, iconos, orden y estilo.

import 'dart:async';

import 'package:connector/connector.dart';
import 'package:flutter/material.dart';

// ------------------------------------------------------------- textos/iconos

String curveName(EdgeCurve c) => switch (c) {
      EdgeCurve.bezier => 'Curva',
      EdgeCurve.smoothStep => 'Ortogonal suave',
      EdgeCurve.step => 'Escalones',
      EdgeCurve.straight => 'Recta',
    };

/// Texto de una acción del editor en esta aplicación.
String actionLabel(EditorAction a, EditorTarget<Object?> target) =>
    switch (a.command) {
      EditorCommand.duplicate => 'Duplicar',
      EditorCommand.delete => 'Eliminar',
      EditorCommand.deleteWithDescendants => 'Eliminar con descendientes',
      EditorCommand.collapse => 'Colapsar',
      EditorCommand.expand => 'Expandir',
      EditorCommand.detachFromParent => 'Quitar de su padre',
      EditorCommand.lock => 'Bloquear',
      EditorCommand.unlock => 'Desbloquear',
      EditorCommand.bringToFront => 'Traer al frente',
      EditorCommand.resetStyle => 'Restablecer aspecto',
      EditorCommand.focus => target is SelectionTarget
          ? 'Encuadrar selección'
          : 'Centrar en pantalla',
      EditorCommand.deleteEdge => 'Eliminar conexión',
      EditorCommand.straightenEdge ||
      EditorCommand.straightenLink =>
        'Enderezar trazado',
      EditorCommand.toggleEdgeAnimation =>
        a.selected ? 'Detener animación' : 'Animar flujo',
      EditorCommand.setEdgeCurve =>
        'Trazado: ${curveName(a.value as EdgeCurve)}',
      EditorCommand.reverseEdge => 'Invertir sentido',
      EditorCommand.unlink => switch (target) {
          LinkTarget(:final parent?) => 'Separar de "${parent.title}"',
          _ => 'Separar de su padre',
        },
      EditorCommand.selectAll => 'Seleccionar todo',
      EditorCommand.clearSelection => 'Quitar selección',
      EditorCommand.fitView => 'Ajustar vista',
      EditorCommand.undo => 'Deshacer',
      EditorCommand.redo => 'Rehacer',
    };

IconData actionIcon(EditorAction a) => switch (a.command) {
      EditorCommand.duplicate => Icons.copy_all_outlined,
      EditorCommand.delete || EditorCommand.deleteEdge => Icons.delete_outline,
      EditorCommand.deleteWithDescendants => Icons.delete_sweep_outlined,
      EditorCommand.collapse => Icons.unfold_less,
      EditorCommand.expand => Icons.unfold_more,
      EditorCommand.detachFromParent || EditorCommand.unlink => Icons.link_off,
      EditorCommand.lock => Icons.lock_outline,
      EditorCommand.unlock => Icons.lock_open,
      EditorCommand.bringToFront => Icons.flip_to_front,
      EditorCommand.resetStyle => Icons.format_color_reset_outlined,
      EditorCommand.focus => Icons.center_focus_strong_outlined,
      EditorCommand.straightenEdge ||
      EditorCommand.straightenLink =>
        Icons.straighten,
      EditorCommand.toggleEdgeAnimation =>
        a.selected ? Icons.motion_photos_paused_outlined : Icons.animation,
      EditorCommand.setEdgeCurve => switch (a.value) {
          EdgeCurve.bezier => Icons.gesture,
          EdgeCurve.smoothStep => Icons.turn_right,
          EdgeCurve.step => Icons.stairs_outlined,
          _ => Icons.horizontal_rule,
        },
      EditorCommand.reverseEdge => Icons.swap_horiz,
      EditorCommand.selectAll => Icons.select_all,
      EditorCommand.clearSelection => Icons.deselect,
      EditorCommand.fitView => Icons.fit_screen_outlined,
      EditorCommand.undo => Icons.undo,
      EditorCommand.redo => Icons.redo,
    };

// ------------------------------------------------------------ menú contextual

/// Opción propia de la aplicación (no del editor) en un menú.
class AppMenuItem {
  const AppMenuItem(this.icon, this.label, this.onSelected,
      {this.destructive = false});
  final IconData icon;
  final String label;
  final FutureOr<void> Function() onSelected;
  final bool destructive;
}

/// Muestra el menú contextual de la aplicación: primero sus propias
/// opciones ([appItems]) y después las acciones del editor que queremos
/// ofrecer, agrupadas y con las destructivas al final.
Future<void> showEditorContextMenu(
  BuildContext context,
  EditorContextMenuDetails<Object?> details, {
  List<AppMenuItem> appItems = const [],
  Set<EditorCommand> hide = const {},
}) async {
  final actions = [
    for (final a in details.actions)
      if (!hide.contains(a.command)) a
  ];
  final safe = actions.where((a) => !a.destructive).toList();
  final danger = actions.where((a) => a.destructive).toList();
  final scheme = Theme.of(context).colorScheme;

  PopupMenuItem<FutureOr<void> Function()> item(
          IconData icon, String label, FutureOr<void> Function() run,
          {bool enabled = true,
          bool destructive = false,
          bool checked = false}) =>
      PopupMenuItem(
        value: run,
        enabled: enabled,
        height: 40,
        child: Row(children: [
          Icon(icon, size: 18, color: destructive ? scheme.error : null),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label,
                style: destructive ? TextStyle(color: scheme.error) : null),
          ),
          if (checked) ...[
            const SizedBox(width: 12),
            Icon(Icons.check, size: 16, color: scheme.primary),
          ],
        ]),
      );

  final entries = <PopupMenuEntry<FutureOr<void> Function()>>[
    for (final i in appItems)
      item(i.icon, i.label, i.onSelected, destructive: i.destructive),
    if (appItems.isNotEmpty && safe.isNotEmpty) const PopupMenuDivider(),
    for (final a in safe)
      item(actionIcon(a), actionLabel(a, details.target), a.call,
          enabled: a.enabled,
          checked: a.selected && a.command == EditorCommand.setEdgeCurve),
    if (danger.isNotEmpty && (appItems.isNotEmpty || safe.isNotEmpty))
      const PopupMenuDivider(),
    for (final a in danger)
      item(actionIcon(a), actionLabel(a, details.target), a.call,
          enabled: a.enabled, destructive: true),
  ];
  if (entries.isEmpty) return;

  final p = details.globalPosition;
  final run = await showMenu<FutureOr<void> Function()>(
    context: context,
    position: RelativeRect.fromLTRB(p.dx, p.dy, p.dx, p.dy),
    items: entries,
  );
  await run?.call();
}

// ------------------------------------------------- barra de la selección

/// Botón de la barra flotante de la selección.
class ToolbarButton {
  const ToolbarButton(this.icon, this.tooltip, this.onPressed,
      {this.active = false, this.destructive = false});

  /// Botón a partir de una acción del editor.
  factory ToolbarButton.action(EditorAction a, EditorTarget<Object?> target) =>
      ToolbarButton(
        actionIcon(a),
        actionLabel(a, target),
        a.enabled ? a.call : null,
        active: a.selected,
        destructive: a.destructive,
      );

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool active;
  final bool destructive;
}

/// Barra flotante con el estilo de la aplicación (Material 3).
class SelectionToolbar extends StatelessWidget {
  const SelectionToolbar({super.key, this.label, required this.buttons});

  final String? label;
  final List<ToolbarButton?> buttons;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      elevation: 3,
      shadowColor: Colors.black54,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (label != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Text(label!,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium),
              ),
            ),
          for (final b in buttons)
            if (b == null)
              Container(
                width: 1,
                height: 20,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                color: scheme.outlineVariant,
              )
            else
              IconButton(
                tooltip: b.tooltip,
                onPressed: b.onPressed,
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                isSelected: b.active,
                color: b.destructive ? scheme.error : null,
                icon: Icon(b.icon),
              ),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------- controles cámara

/// Controles de zoom, encuadre, historial y bloqueo construidos por la
/// aplicación con los métodos del controlador.
class CanvasControls extends StatelessWidget {
  const CanvasControls({super.key, required this.controller});

  final NodeEditorController<Object?> controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: ListenableBuilder(
        listenable: Listenable.merge([c.history, c.locked]),
        builder: (context, _) {
          Widget b(IconData icon, String tip, VoidCallback? onTap,
                  {bool selected = false}) =>
              IconButton(
                tooltip: tip,
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                isSelected: selected,
                onPressed: onTap,
                icon: Icon(icon),
              );
          return Padding(
            padding: const EdgeInsets.all(2),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              b(Icons.add, 'Acercar',
                  () => c.viewport.zoomBy(1.2, animate: true)),
              b(Icons.remove, 'Alejar',
                  () => c.viewport.zoomBy(1 / 1.2, animate: true)),
              b(Icons.fit_screen_outlined, 'Ajustar vista',
                  () => c.fitView(animate: true)),
              const SizedBox(width: 24, child: Divider(height: 8)),
              b(Icons.undo, 'Deshacer', c.canUndo ? c.undo : null),
              b(Icons.redo, 'Rehacer', c.canRedo ? c.redo : null),
              b(
                c.locked.value ? Icons.lock_outline : Icons.lock_open_outlined,
                c.locked.value ? 'Desbloquear edición' : 'Bloquear edición',
                () => c.locked.value = !c.locked.value,
                selected: c.locked.value,
              ),
            ]),
          );
        },
      ),
    );
  }
}
