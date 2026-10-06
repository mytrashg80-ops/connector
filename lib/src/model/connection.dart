import 'node.dart';
import 'port.dart';

/// Datos de una conexión que se quiere crear.
class ConnectionRequest {
  const ConnectionRequest({
    required this.source,
    required this.target,
    this.sourcePort,
    this.targetPort,
  });

  final NodeData<Object?> source;
  final NodePort? sourcePort;
  final NodeData<Object?> target;
  final NodePort? targetPort;
}

/// Resultado de validar una conexión. `null` en [reason] significa válida.
class ConnectionCheck {
  const ConnectionCheck.valid() : reason = null;
  const ConnectionCheck.invalid(String this.reason);

  final String? reason;
  bool get isValid => reason == null;

  @override
  String toString() => isValid ? 'valid' : 'invalid: $reason';
}

/// Validador personalizado. Devuelve `null` si la conexión es válida o un
/// mensaje con el motivo del rechazo.
typedef ConnectionValidator = String? Function(ConnectionRequest request);
