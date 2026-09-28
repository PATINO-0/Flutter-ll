import '../entities/auth_session_event.dart';

abstract class AuthRepository {
  Future<void> signIn({required String email, required String password});

  Future<void> signOut();

  String? get currentUserId;

  String? get currentUserEmail;

  bool get hasSession;

  Stream<AuthSessionEvent> get authStateChanges;
}
