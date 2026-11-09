import '../entities/user_profile.dart'; // Reutiliza las entidades o servicios de user_profile.

/// Define la consulta de un perfil con sus permisos actuales.
abstract class ProfileRepository {
  /// Carga el perfil solicitado y sus permisos actuales con un límite de espera.
  Future<UserProfile?> findById(String userId);
}
