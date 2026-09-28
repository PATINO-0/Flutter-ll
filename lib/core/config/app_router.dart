import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/domain/entities/auth_session_event.dart';
import '../../features/auth/presentation/pages/login_page.dart';
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
    redirect: (context, state) {
      final authenticated = authRepository.hasSession;
      final currentPath = state.uri.path;

      final onLogin = currentPath == AppRoutes.login;

      if (!authenticated && !onLogin) {
        return AppRoutes.login;
      }

      if (authenticated && onLogin) {
        return AppRoutes.dashboard;
      }

      return null;
    },
    routes: [
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
