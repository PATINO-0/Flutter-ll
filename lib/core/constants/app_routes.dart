/// Centraliza las rutas públicas y protegidas para evitar direcciones duplicadas.
class AppRoutes {
  AppRoutes._();

  static const String login =
      '/login'; // Expone el acceso a cuentas registradas.
  static const String register =
      '/register'; // Habilita el registro sin una sesión previa.
  static const String administration =
      '/administration'; // Muestra la gestión protegida de usuarios.
  static const String dashboard =
      '/dashboard'; // Abre el menú calculado según los roles vigentes.
}
