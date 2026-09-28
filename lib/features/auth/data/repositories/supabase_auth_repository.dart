import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/app_exception.dart';
import '../../domain/entities/auth_session_event.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_remote_data_source.dart';

class SupabaseAuthRepository implements AuthRepository {
  const SupabaseAuthRepository(this._dataSource);

  final AuthRemoteDataSource _dataSource;

  @override
  Future<void> signIn({required String email, required String password}) async {
    try {
      await _dataSource.signIn(email: email.trim(), password: password);
    } catch (error) {
      throw AppException(_mapSignInError(error));
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _dataSource.signOut();
    } catch (_) {
      throw const AppException(
        'No fue posible cerrar la sesión. Intenta nuevamente.',
      );
    }
  }

  @override
  String? get currentUserId {
    return _dataSource.currentUserId;
  }

  @override
  String? get currentUserEmail {
    return _dataSource.currentUserEmail;
  }

  @override
  bool get hasSession {
    return _dataSource.hasSession;
  }

  @override
  Stream<AuthSessionEvent> get authStateChanges {
    return _dataSource.authStateChanges.map((state) {
      return AuthSessionEvent(
        isAuthenticated: state.session != null,
        userId: state.session?.user.id,
      );
    });
  }

  String _mapSignInError(Object error) {
    if (error is AuthException) {
      final message = error.message.toLowerCase();

      if (message.contains('invalid login credentials') ||
          message.contains('invalid credentials')) {
        return 'Correo o contraseña incorrectos.';
      }

      if (message.contains('email not confirmed')) {
        return 'El correo electrónico todavía no ha sido confirmado.';
      }

      if (message.contains('network') ||
          message.contains('connection') ||
          message.contains('fetch')) {
        return 'Verifica tu conexión e intenta nuevamente.';
      }

      return 'No fue posible iniciar sesión.';
    }

    final message = error.toString().toLowerCase();

    if (message.contains('network') ||
        message.contains('connection') ||
        message.contains('socket') ||
        message.contains('fetch')) {
      return 'Verifica tu conexión e intenta nuevamente.';
    }

    return 'Ocurrió un problema inesperado.';
  }
}
