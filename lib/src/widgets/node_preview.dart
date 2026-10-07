import 'package:flutter/widgets.dart';

import '../model/node.dart';
import '../theme/node_editor_theme.dart';
import 'default_node.dart';
import 'editor_config.dart';

/// Dibuja un nodo tal y como se ve en el editor, pero fuera de él: para la
/// vista previa de un diálogo de estilo, una paleta de tipos, un tooltip…
///
/// Se escala para caber en el espacio disponible conservando sus
/// proporciones ([fit]).
class NodePreview<T> extends StatelessWidget {
  const NodePreview({
    super.key,
    required this.node,
    this.theme,
    this.nodeBuilder,
    this.state = const NodeViewState(),
    this.fit = BoxFit.contain,
  });

  final NodeData<T> node;

  /// `null` usa el tema del contexto.
  final NodeEditorTheme? theme;

  /// El mismo `nodeBuilder` que le pasas al editor (opcional).
  final NodeWidgetBuilder<T>? nodeBuilder;
  final NodeViewState state;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final t = theme ?? NodeEditorScope.themeOf(context);
    return FittedBox(
      fit: fit,
      child: SizedBox.fromSize(
        size: node.size,
        child: NodeEditorScope(
          theme: t,
          child: Builder(
            builder: (context) =>
                nodeBuilder?.call(context, node, state) ??
                DefaultNodeBody(node: node, state: state, theme: t),
          ),
        ),
      ),
    );
  }
}
