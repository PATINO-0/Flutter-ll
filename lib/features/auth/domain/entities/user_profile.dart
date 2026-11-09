import 'user_role.dart'; // Comparte los roles válidos del dominio.

/// Representa un perfil y los permisos que devuelve la base de datos.
class UserProfile {
  const UserProfile({
    required this.id,
    required this.fullName,
    required this.email,
    required this.createdAt,
    required this.updatedAt,
    this.roles = const [], // Un perfil sin roles no recibe permisos elevados.
    this.isActive =
        true, // Mantiene compatibilidad con perfiles anteriores a la revocación de acceso.
  });

  final String id;
  final String fullName;
  final String email;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<UserRole> roles; // Una cuenta puede tener varios roles.
  final bool
  isActive; // Impide mostrar funciones a una cuenta cuyo acceso fue eliminado.

  /// Selecciona el rol de mayor acceso cuando una cuenta tiene varias responsabilidades.
  UserRole? get effectiveRole {
    if (!isActive) {
      return null; // Una cuenta desactivada no tiene permisos efectivos.
    }
    UserRole? selected; // Comienza sin permisos predeterminados.
    for (final role in roles) {
      if (selected == null || role.priority > selected.priority) {
        selected = role; // Conserva únicamente el mayor nivel.
      }
    }
    return selected; // No modifica la lista de roles almacenados en Supabase.
  }

  /// Permite identificar el acceso al panel de administración.
  bool get isAdmin => effectiveRole == UserRole.admin;

  /// Autoriza la navegación de las operaciones internas de Ritech.
  bool get canManageOperations => isAdmin || effectiveRole == UserRole.worker;

  /// Autoriza la navegación de los convenios de asociados.
  bool get canManageAgreements =>
      canManageOperations || effectiveRole == UserRole.associate;

  /// Autoriza la navegación de las solicitudes de los clientes.
  bool get canCreateShipments =>
      canManageOperations || effectiveRole == UserRole.associate;

  /// Reserva el catálogo y la solicitud inicial al cliente, conservando acceso total para administración.
  bool get canAccessStore => isAdmin || effectiveRole == UserRole.client;

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    final createdAt = DateTime.parse(
      map['created_at'] as String,
    ); // Conserva la fecha de creación almacenada.
    // Admite tanto la relación de perfiles como el resultado de la consulta administrativa.
    final roles = <UserRole>[];
    for (final entry in map['roles'] as List? ?? const []) {
      final value = entry is Map ? entry['role'] : entry;
      final role = UserRole.fromValue(value?.toString() ?? '');
      if (role != null && !roles.contains(role)) roles.add(role);
    }
    return UserProfile(
      id: map['id'] as String,
      fullName: map['full_name'] as String? ?? 'Usuario',
      email: map['email'] as String? ?? '',
      isActive:
          map['is_active'] as bool? ??
          true, // Reconoce la revocación aunque el token todavía exista.
      createdAt: createdAt, // Comparte la fecha validada del perfil.
      updatedAt:
          DateTime.tryParse(map['updated_at'] as String? ?? '') ??
          createdAt, // Admite perfiles antiguos que todavía no se actualizaron.
      roles: List.unmodifiable(
        roles,
      ), // Impide modificar los permisos del perfil en memoria.
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'full_name': fullName,
      'email': email,
      'is_active':
          isActive, // Conserva el estado de acceso al serializar un perfil.
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'roles': roles
          .map((role) => role.value)
          .toList(), // Serializa los roles conocidos.
    };
  }
}
