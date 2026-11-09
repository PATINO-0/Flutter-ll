import 'package:flutter_riverpod/flutter_riverpod.dart'; // Conecta el módulo con sus dependencias.

import '../../../../core/errors/app_exception.dart'; // Representa los accesos no autorizados.
import '../../../auth/domain/entities/user_profile.dart'; // Define el resultado de la lista.
import '../../../auth/domain/entities/user_role.dart'; // Comprueba el rol efectivo sin depender de cada respuesta del perfil.
import '../../../auth/presentation/providers/auth_providers.dart'; // Comparte el cliente y el perfil actual.
import '../../data/repositories/supabase_user_management_repository.dart'; // Implementa las operaciones remotas.
import '../../domain/repositories/user_management_repository.dart'; // Evita acoplar la pantalla a Supabase.

/// Proporciona el repositorio de administración con la sesión actual.
final userManagementRepositoryProvider = Provider<UserManagementRepository>((
  ref,
) {
  return SupabaseUserManagementRepository(ref.watch(supabaseClientProvider));
});

/// Carga cada página solo después de comprobar el perfil autenticado.
final adminUsersProvider = FutureProvider.autoDispose
    .family<List<UserProfile>, int>((ref, page) async {
      final access = await ref.watch(
        currentUserAccessProvider.future,
      ); // Cambios de nombre o consultas de comprobación no recargan la lista abierta.
      if (!access.isActive || access.role != UserRole.admin) {
        throw const AppException(
          'No tienes permiso para administrar usuarios.',
        );
      }
      if (!ref.mounted) {
        return const []; // Descarta consultas cuya pantalla ya se cerró.
      }
      return ref
          .watch(userManagementRepositoryProvider)
          .listUsers(page: page); // El servidor vuelve a validar los permisos.
    });
