import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/app_exception.dart';
import '../../domain/entities/auth_session_event.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_remote_data_source.dart';

class SupabaseAuthRepository implements AuthRepository {
  const SupabaseAuthRepository(this._dataSource);

  final AuthRemoteDataSource _dataSource;

  /// Normaliza los datos y traduce los errores del registro a mensajes en español.
  @override
  Future<bool> signUp({
    required String fullName,
    required String email,
    required String password,
  }) async {
    try {
      return await _dataSource.signUp(
        fullName: fullName.trim(), // Elimina espacios externos del nombre.
        email: email
            .trim()
            .toLowerCase(), // Mantiene uniforme el correo de acceso.
        password: password, // Conserva exactamente la contraseña ingresada.
      );
    } on AuthException catch (error) {
      switch (error.code) {
        case 'user_already_exists':
        case 'email_exists':
          throw const AppException(
            'Ya existe una cuenta con este correo. Inicia sesión.',
          );
        case 'weak_password':
          throw const AppException(
            'La contraseña no cumple los requisitos de seguridad del servidor.',
          );
        case 'over_email_send_rate_limit':
        case 'over_request_rate_limit':
          throw const AppException(
            'Se realizaron demasiados intentos. Espera unos minutos.',
          );
        case 'signup_disabled':
          throw const AppException(
            'El registro no está habilitado en este momento.',
          );
        default:
          throw const AppException(
            'No fue posible crear la cuenta. Intenta nuevamente.',
          );
      }
    } catch (_) {
      throw const AppException(
        'No fue posible registrarte. Verifica tu conexión e intenta nuevamente.',
      );
    }
  }

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
