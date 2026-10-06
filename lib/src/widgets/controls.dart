import 'package:flutter/material.dart';

import '../controller/node_editor_controller.dart';
import '../theme/node_editor_theme.dart';

/// Barra de controles: zoom, ajustar vista, deshacer/rehacer y bloqueo.
class NodeEditorControls<T> extends StatelessWidget {
  const NodeEditorControls({
    super.key,
    required this.controller,
    this.theme,
    this.zoomStep = 1.2,
    this.axis = Axis.vertical,
    this.showZoom = true,
    this.showFit = true,
    this.showHistory = true,
    this.showLock = true,
  });

  final NodeEditorController<T> controller;
  final NodeEditorTheme? theme;
  final double zoomStep;
  final Axis axis;
  final bool showZoom;
  final bool showFit;
  final bool showHistory;
  final bool showLock;

  @override
  Widget build(BuildContext context) {
    final t = theme ?? NodeEditorTheme.of(context);
    final c = controller;
    Widget button(IconData icon, String tooltip, VoidCallback? onTap,
            {bool active = false}) =>
        _ControlButton(
          icon: icon,
          tooltip: tooltip,
          onTap: onTap,
          color: active ? t.accentColor : t.controlsForeground,
        );

    final children = <Widget>[
      if (showZoom) ...[
        button(Icons.add, 'Acercar', () => c.viewport.zoomBy(zoomStep)),
        button(Icons.remove, 'Alejar', () => c.viewport.zoomBy(1 / zoomStep)),
      ],
      if (showFit)
        button(Icons.fit_screen_outlined, 'Ajustar vista', () => c.fitView()),
      if (showHistory)
        ValueListenableBuilder<int>(
          valueListenable: c.history,
          builder: (context, _, __) => Flex(
            direction: axis,
            mainAxisSize: MainAxisSize.min,
            children: [
              button(Icons.undo, 'Deshacer', c.canUndo ? c.undo : null),
              button(Icons.redo, 'Rehacer', c.canRedo ? c.redo : null),
            ],
          ),
        ),
      if (showLock)
        ValueListenableBuilder<bool>(
          valueListenable: c.locked,
          builder: (context, locked, _) => button(
            locked ? Icons.lock_outline : Icons.lock_open_outlined,
            locked ? 'Desbloquear edición' : 'Bloquear edición',
            () => c.locked.value = !locked,
            active: locked,
          ),
        ),
    ];

    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.controlsBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.controlsBorderColor),
        boxShadow: t.nodeShadow,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Flex(
            direction: axis,
            mainAxisSize: MainAxisSize.min,
            children: children,
          ),
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    required this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: SizedBox(
          width: 32,
          height: 32,
          child: Icon(
            icon,
            size: 18,
            color: onTap == null ? color.withValues(alpha: 0.35) : color,
          ),
        ),
      ),
    );
  }
}
