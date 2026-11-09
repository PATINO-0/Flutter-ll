import '../../../auth/domain/entities/user_profile.dart'; // Representa las cuentas administradas.
import '../../../auth/domain/entities/user_role.dart'; // Restringe los roles a los valores admitidos.

/// Define las operaciones exclusivas del administrador sin depender de Supabase.
abstract class UserManagementRepository {
  /// Actualiza los datos de acceso y los roles conservando las restricciones del último administrador.
  Future<void> updateUser({
    required String userId,
    required String fullName,
    required String email,
    required List<UserRole> roles,
  });

  /// Retira el acceso de una cuenta sin destruir sus convenios ni sus documentos históricos.
  Future<void> deactivateUser(String userId);

  /// Consulta una página de usuarios con los roles vigentes del servidor.
  Future<List<UserProfile>> listUsers({required int page});

  /// Sustituye los roles de una cuenta mediante una operación protegida.
  Future<void> updateRoles({
    required String userId,
    required List<UserRole> roles,
  });

  /// Crea una cuenta desde el servidor sin reemplazar la sesión del administrador.
  Future<void> createUser({
    required String fullName, // Nombre del nuevo perfil.
    required String email, // Correo de la nueva cuenta.
    required String password, // Contraseña inicial de acceso.
    required List<UserRole> roles, // Roles elegidos por el administrador.
  });
}
