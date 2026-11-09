/// Representa la existencia de sesión y la identidad que debe observar la navegación.
class AuthSessionEvent {
  const AuthSessionEvent({required this.isAuthenticated, this.userId});

  final bool
  isAuthenticated; // Indica si el enrutador puede abrir pantallas privadas.
  final String?
  userId; // Permite diferenciar una renovación del token de un cambio de cuenta.
}
