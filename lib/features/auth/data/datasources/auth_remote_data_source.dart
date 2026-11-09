import 'package:supabase_flutter/supabase_flutter.dart'; // Accede a Auth, datos y archivos con la sesión autenticada.

/// Encapsula el registro, acceso, cierre y lectura de sesión mediante Supabase Auth.
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

  /// Autentica las credenciales y conserva un mensaje recuperable si el servidor las rechaza.
  Future<void> signIn({required String email, required String password}) async {
    await _client.auth.signInWithPassword(email: email, password: password);
  }

  /// Cierra la sesión actual y propaga el resultado a la navegación autenticada.
  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  /// Obtiene el identificador de la cuenta autenticada sin confiar en datos del formulario.
  String? get currentUserId {
    return _client.auth.currentUser?.id;
  }

  /// Obtiene el correo que Supabase Auth verificó para la sesión actual.
  String? get currentUserEmail {
    return _client.auth.currentUser?.email;
  }

  /// Indica si existe una sesión que la navegación pueda utilizar.
  bool get hasSession {
    return _client.auth.currentSession != null;
  }

  Stream<AuthState> get authStateChanges {
    return _client.auth.onAuthStateChange;
  }
}
