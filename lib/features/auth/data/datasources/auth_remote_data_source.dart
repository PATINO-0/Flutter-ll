import 'package:supabase_flutter/supabase_flutter.dart';

class AuthRemoteDataSource {
  const AuthRemoteDataSource(this._client);

  final SupabaseClient _client;

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
