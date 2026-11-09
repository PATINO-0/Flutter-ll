import 'package:supabase_flutter/supabase_flutter.dart'; // Accede a Auth, datos y archivos con la sesión autenticada.

import '../config/app_config.dart'; // Reutiliza las entidades o servicios de app_config.

/// Inicializa una sola instancia del cliente público de Supabase antes de abrir la interfaz.
class SupabaseService {
  SupabaseService._();

  /// Conecta el cliente de Supabase con la URL y clave pública ya validadas.
  static Future<void> initialize(AppConfig config) async {
    await Supabase.initialize(
      url: config.supabaseUrl,
      publishableKey: config.supabasePublishableKey,
    );
  }
}
