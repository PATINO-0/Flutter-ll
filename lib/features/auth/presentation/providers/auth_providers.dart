import 'package:flutter_riverpod/flutter_riverpod.dart'; // Comparte consultas, estado y dependencias entre módulos.
import 'package:supabase_flutter/supabase_flutter.dart'; // Accede a Auth, datos y archivos con la sesión autenticada.

import '../../../../core/errors/app_exception.dart'; // Reutiliza las entidades o servicios de app_exception.
import '../../data/datasources/auth_remote_data_source.dart'; // Reutiliza las entidades o servicios de auth_remote_data_source.
import '../../data/repositories/supabase_auth_repository.dart'; // Reutiliza las entidades o servicios de supabase_auth_repository.
import '../../data/repositories/supabase_profile_repository.dart'; // Reutiliza las entidades o servicios de supabase_profile_repository.
import '../../domain/entities/auth_session_event.dart'; // Reutiliza las entidades o servicios de auth_session_event.
import '../../domain/entities/user_profile.dart'; // Reutiliza las entidades o servicios de user_profile.
import '../../domain/entities/user_role.dart'; // Distingue cambios reales de permisos durante la comprobación periódica.
import '../../domain/repositories/auth_repository.dart'; // Reutiliza las entidades o servicios de auth_repository.
import '../../domain/repositories/profile_repository.dart'; // Reutiliza las entidades o servicios de profile_repository.

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final authRemoteDataSourceProvider = Provider<AuthRemoteDataSource>((ref) {
  return AuthRemoteDataSource(ref.watch(supabaseClientProvider));
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return SupabaseAuthRepository(ref.watch(authRemoteDataSourceProvider));
});

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return SupabaseProfileRepository(ref.watch(supabaseClientProvider));
});

final authSessionProvider = StreamProvider<AuthSessionEvent>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges;
});

final currentUserProfileProvider = FutureProvider.autoDispose<UserProfile?>((
  ref,
) async {
  ref.watch(
    authSessionProvider.select((session) => session.asData?.value.userId),
  ); // Recarga cuando cambia la cuenta, sin repetir consultas por cada renovación del token.
  final authRepository = ref.watch(authRepositoryProvider);

  final userId = authRepository.currentUserId;

  if (userId == null) {
    return null;
  }

  return ref.watch(profileRepositoryProvider).findById(userId);
});

/// Renueva los módulos únicamente cuando cambia la cuenta, su estado activo o su rol efectivo.
final currentUserAccessProvider =
    FutureProvider.autoDispose<
      ({String? userId, bool isActive, UserRole? role})
    >((ref) {
      return ref.watch(
        currentUserProfileProvider.selectAsync(
          (profile) => (
            userId: profile?.id,
            isActive: profile?.isActive ?? false,
            role: profile?.effectiveRole,
          ),
        ),
      ); // Otra respuesta del mismo perfil no desmonta listas, desplegables ni formularios.
    });

final authControllerProvider =
    NotifierProvider<AuthController, AsyncValue<bool>>(AuthController.new);

/// Coordina las acciones de autenticación y el estado de carga sin duplicar solicitudes.
class AuthController extends Notifier<AsyncValue<bool>> {
  /// Registra una cuenta sin permitir la selección pública de roles.
  Future<String?> signUp({
    required String fullName,
    required String email,
    required String password,
  }) async {
    if (state.isLoading) {
      return null; // Evita enviar dos solicitudes simultáneas.
    }
    state =
        const AsyncLoading(); // Desactiva el formulario durante el registro.
    try {
      await ref
          .read(authRepositoryProvider)
          .signUp(fullName: fullName, email: email, password: password);
      if (!ref.mounted) {
        return null; // Evita actualizar un controlador ya cerrado.
      }
      state = AsyncData(ref.read(authRepositoryProvider).hasSession);
      ref.invalidate(
        currentUserProfileProvider,
      ); // Carga el perfil creado por el servidor.
      return null; // La pantalla decide entre el panel y la confirmación del correo.
    } on AppException catch (error, stackTrace) {
      if (ref.mounted) state = AsyncError(error, stackTrace);
      return error.userMessage; // Presenta solamente mensajes traducidos.
    } catch (error, stackTrace) {
      if (ref.mounted) state = AsyncError(error, stackTrace);
      return 'No fue posible crear la cuenta. Intenta nuevamente.';
    }
  }

  @override
  AsyncValue<bool> build() {
    final hasSession = ref.read(authRepositoryProvider).hasSession;

    return AsyncData(hasSession);
  }

  /// Autentica las credenciales y conserva un mensaje recuperable si el servidor las rechaza.
  Future<String?> signIn({
    required String email,
    required String password,
  }) async {
    state = const AsyncLoading();

    try {
      await ref
          .read(authRepositoryProvider)
          .signIn(email: email, password: password);

      state = const AsyncData(true);

      ref.invalidate(currentUserProfileProvider);

      return null;
    } on AppException catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);

      return error.userMessage;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);

      return 'Ocurrió un problema inesperado.';
    }
  }

  /// Cierra la sesión actual y propaga el resultado a la navegación autenticada.
  Future<String?> signOut() async {
    state = const AsyncLoading();

    try {
      await ref.read(authRepositoryProvider).signOut();

      state = const AsyncData(false);

      ref.invalidate(currentUserProfileProvider);

      return null;
    } on AppException catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);

      return error.userMessage;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);

      return 'Ocurrió un problema inesperado.';
    }
  }
}
