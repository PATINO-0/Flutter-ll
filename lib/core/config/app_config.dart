import 'package:flutter_dotenv/flutter_dotenv.dart'; // Obtiene la configuración incluida durante la compilación del cliente.

/// Carga y valida la URL y la clave pública de Supabase desde el entorno local.
class AppConfig {
  const AppConfig({
    required this.supabaseUrl,
    required this.supabasePublishableKey,
  });

  final String
  supabaseUrl; // Identifica el proyecto al que se conectará Ritech.
  final String
  supabasePublishableKey; // Identifica al cliente público; no contiene privilegios de servidor.

  /// Rechaza un entorno incompleto antes de que se presenten errores de conexión en las pantallas.
  factory AppConfig.fromEnvironment() {
    final supabaseUrl = dotenv
        .get('SUPABASE_URL', fallback: '')
        .trim(); // Normaliza espacios del valor configurado.
    final supabasePublishableKey = dotenv
        .get('SUPABASE_PUBLISHABLE_KEY', fallback: '')
        .trim();

    if (supabaseUrl.isEmpty) {
      throw StateError('SUPABASE_URL no está configurada en el archivo .env.');
    }

    if (supabasePublishableKey.isEmpty) {
      throw StateError(
        'SUPABASE_PUBLISHABLE_KEY no está configurada en el archivo .env.',
      );
    }

    return AppConfig(
      supabaseUrl: supabaseUrl,
      supabasePublishableKey: supabasePublishableKey,
    );
  }
}
