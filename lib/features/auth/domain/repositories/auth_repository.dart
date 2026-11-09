import '../entities/auth_session_event.dart';

abstract class AuthRepository {
  /// Registra un cliente y devuelve si su correo necesita confirmación.
  Future<bool> signUp({
    required String fullName,
    required String email,
    required String password,
  });

  Future<void> signIn({required String email, required String password});

  Future<void> signOut();

  String? get currentUserId;

  String? get currentUserEmail;

  bool get hasSession;

  Stream<AuthSessionEvent> get authStateChanges;
}
