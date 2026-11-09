import 'package:supabase_flutter/supabase_flutter.dart';

class AuthRemoteDataSource {
  const AuthRemoteDataSource(this._client);

  final SupabaseClient _client;

  /// Envía únicamente datos personales; el servidor asigna el rol de cliente.
  Future<bool> signUp({
    required String fullName,
    required String email,
    required String password,
  }) async {
    final response = await _client.auth.signUp(
      email: email, // Correo que se utilizará para iniciar sesión.
      password: password, // Supabase almacena y protege la contraseña.
      data: {'full_name': fullName}, // Los metadatos nunca contienen permisos.
    );
    return response.session ==
        null; // Respeta la confirmación configurada en Supabase.
  }

  Future<void> signIn({required String email, required String password}) async {
    await _client.auth.signInWithPassword(email: email, password: password);
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  String? get currentUserId {
    return _client.auth.currentUser?.id;
  }

  String? get currentUserEmail {
    return _client.auth.currentUser?.email;
  }

  bool get hasSession {
    return _client.auth.currentSession != null;
  }

  Stream<AuthState> get authStateChanges {
    return _client.auth.onAuthStateChange;
  }
}
