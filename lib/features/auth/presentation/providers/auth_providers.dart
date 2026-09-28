import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/app_exception.dart';
import '../../data/datasources/auth_remote_data_source.dart';
import '../../data/repositories/supabase_auth_repository.dart';
import '../../data/repositories/supabase_profile_repository.dart';
import '../../domain/entities/auth_session_event.dart';
import '../../domain/entities/user_profile.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/repositories/profile_repository.dart';

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
  final authRepository = ref.watch(authRepositoryProvider);

  final userId = authRepository.currentUserId;

  if (userId == null) {
    return null;
  }

  return ref.watch(profileRepositoryProvider).findById(userId);
});

final authControllerProvider =
    NotifierProvider<AuthController, AsyncValue<bool>>(AuthController.new);

class AuthController extends Notifier<AsyncValue<bool>> {
  @override
  AsyncValue<bool> build() {
    final hasSession = ref.read(authRepositoryProvider).hasSession;

    return AsyncData(hasSession);
  }

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
