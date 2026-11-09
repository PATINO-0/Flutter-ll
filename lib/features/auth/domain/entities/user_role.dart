/// Define los roles que el servidor permite asignar a una cuenta.
enum UserRole {
  admin('admin', 'Administrador', 'Administra usuarios, roles y operaciones.'),
  client(
    'client',
    'Cliente',
    'Consulta tarifas y solicita convertirse en asociado.',
  ),
  associate(
    'associate',
    'Asociado',
    'Gestiona sus envíos, exportaciones y seguimiento.',
  ),
  worker(
    'worker',
    'Trabajador',
    'Gestiona clientes y revisa convenios y exportaciones.',
  ),
  transporter(
    'transporter',
    'Transportador',
    'Toma envíos compatibles y actualiza su recogida, ubicación y entrega.',
  );

  /// Relaciona el identificador de la base de datos con su texto visible.
  const UserRole(this.value, this.label, this.description);

  final String value; // Identificador utilizado por Supabase.
  final String label; // Nombre del rol que se muestra al usuario.
  final String description; // Explicación breve de sus responsabilidades.

  /// Define una jerarquía explícita que no depende del orden de la enumeración.
  int get priority => switch (this) {
    UserRole.admin => 5, // Administración conserva acceso a todos los módulos.
    UserRole.worker =>
      4, // El personal atiende clientes y gestiona operaciones.
    UserRole.transporter =>
      3, // El transportador tiene un espacio operativo restringido.
    UserRole.associate =>
      2, // Los asociados acceden a sus operaciones de comercio.
    UserRole.client => 1, // El cliente accede al catálogo y a su vinculación.
  };

  /// Descarta valores desconocidos sin conceder permisos por defecto.
  static UserRole? fromValue(String value) {
    for (final role in values) {
      if (role.value == value) return role;
    }
    return null;
  }
}
