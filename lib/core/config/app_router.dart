import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/domain/entities/auth_session_event.dart';
import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/auth/presentation/pages/register_page.dart'; // Expone el registro público.
import '../../features/administration/presentation/pages/administration_page.dart'; // Expone el panel protegido.
import '../../features/auth/presentation/providers/auth_providers.dart';
import '../../features/dashboard/presentation/pages/dashboard_page.dart';
import '../constants/app_routes.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final authRepository = ref.watch(authRepositoryProvider);

  final refreshNotifier = AuthRouterRefreshNotifier(
    authRepository.authStateChanges,
  );

  ref.onDispose(refreshNotifier.dispose);

  final router = GoRouter(
    initialLocation: AppRoutes.dashboard,
    refreshListenable: refreshNotifier,
    redirect: (context, state) async {
      final authenticated = authRepository.hasSession;
      final currentPath = state.uri.path;

      // El registro y el inicio de sesión son las únicas rutas públicas.
      final onPublicPage =
          currentPath == AppRoutes.login || currentPath == AppRoutes.register;

      if (!authenticated && !onPublicPage) {
        return AppRoutes.login;
      }

      if (authenticated && onPublicPage) {
        return AppRoutes.dashboard;
      }

      // Consulta permisos actuales al abrir una ruta administrativa, incluso desde un enlace directo.
      if (authenticated && currentPath == AppRoutes.administration) {
        try {
          final userId = authRepository.currentUserId;
          if (userId == null) return AppRoutes.login;
          final profile = await ref
              .read(profileRepositoryProvider)
              .findById(userId);
          if (profile?.isAdmin != true) return AppRoutes.dashboard;
        } catch (_) {
          return AppRoutes
              .dashboard; // Deniega el acceso si no se pueden verificar los permisos.
        }
      }

      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.register, // Permite crear una cuenta sin sesión.
        builder: (context, state) => const RegisterPage(),
      ),
      GoRoute(
        path: AppRoutes
            .administration, // Mantiene la administración en una ruta independiente.
        builder: (context, state) => const AdministrationPage(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) {
          return const LoginPage();
        },
      ),
      GoRoute(
        path: AppRoutes.dashboard,
        builder: (context, state) {
          return const DashboardPage();
        },
      ),
    ],
  );

  ref.onDispose(router.dispose);

  return router;
});

class AuthRouterRefreshNotifier extends ChangeNotifier {
  AuthRouterRefreshNotifier(Stream<AuthSessionEvent> stream) {
    _subscription = stream.listen(
      (_) {
        notifyListeners();
      },
      onError: (Object error, StackTrace stackTrace) {
        notifyListeners();
      },
    );
  }

  late final StreamSubscription<AuthSessionEvent> _subscription;

  @override
  void dispose() {
    unawaited(_subscription.cancel());

    super.dispose();
  }
}
