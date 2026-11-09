/// Transporta un mensaje de error comprensible sin publicar detalles internos del servidor.
class AppException implements Exception {
  const AppException(this.userMessage);

  final String
  userMessage; // Conserva solamente el texto que puede presentarse en la interfaz.

  /// Expone únicamente el mensaje preparado para el usuario.
  @override
  String toString() => userMessage;
}
