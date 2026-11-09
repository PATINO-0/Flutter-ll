import '../entities/auth_session_event.dart'; // Reutiliza las entidades o servicios de auth_session_event.

/// Define el contrato de autenticación que comparten producción y las pruebas sin red.
abstract class AuthRepository {
  /// Registra un cliente y devuelve si su correo necesita confirmación.
  Future<bool> signUp({
    required String fullName,
    required String email,
    required String password,
  });

  /// Autentica las credenciales y conserva un mensaje recuperable si el servidor las rechaza.
  Future<void> signIn({required String email, required String password});

  /// Cierra la sesión actual y propaga el resultado a la navegación autenticada.
  Future<void> signOut();

  String? get currentUserId;

  String? get currentUserEmail;

  bool get hasSession;

  Stream<AuthSessionEvent> get authStateChanges;
}
