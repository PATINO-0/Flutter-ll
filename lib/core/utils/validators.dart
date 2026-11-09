/// Valida correo, nombres y contraseñas antes de enviar formularios al servidor.
class Validators {
  Validators._();

  static final RegExp _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  /// Comprueba que el correo tenga contenido y una estructura válida antes del envío.
  static String? email(String? value) {
    final email = value?.trim() ?? '';

    if (email.isEmpty) {
      return 'Ingresa tu correo electrónico.';
    }

    if (!_emailRegex.hasMatch(email)) {
      return 'Ingresa un correo electrónico válido.';
    }

    return null;
  }

  /// Comprueba que el campo de contraseña tenga contenido sin modificar sus caracteres.
  static String? password(String? value) {
    if (value == null || value.isEmpty) {
      return 'Ingresa tu contraseña.';
    }

    return null;
  }

  /// Comprueba el nombre antes de registrar una cuenta.
  static String? fullName(String? value) {
    final name = value?.trim() ?? ''; // Ignora espacios externos.
    if (name.length < 3) {
      return 'Ingresa tu nombre completo (mínimo 3 caracteres).';
    }
    if (name.length > 100) {
      return 'El nombre no puede superar los 100 caracteres.';
    }
    return null; // El nombre cumple los límites del servidor.
  }

  /// Aplica los mismos requisitos mínimos que la creación administrativa.
  static String? newPassword(String? value) {
    if ((value ?? '').length < 8) {
      return 'Usa una contraseña de al menos 8 caracteres.';
    }
    if (value!.length > 72) {
      return 'La contraseña no puede superar los 72 caracteres.';
    }
    return null; // No altera los espacios ni el contenido de la contraseña.
  }

  /// Evita registrar una contraseña distinta a la confirmada.
  static String? confirmPassword(String? value, String password) {
    if (value != password || (value ?? '').isEmpty) {
      return 'Las contraseñas no coinciden.';
    }
    return null; // Ambas entradas contienen la misma contraseña.
  }
}
