import 'package:flutter/material.dart'; // Prepara el motor visual antes de utilizar servicios de plataforma.
import 'package:flutter_dotenv/flutter_dotenv.dart'; // Carga únicamente la configuración pública utilizada por el cliente.
import 'package:flutter_riverpod/flutter_riverpod.dart'; // Mantiene un contenedor de estado compartido por los módulos.

import 'app.dart'; // Construye el enrutamiento y la presentación de Ritech.
import 'core/config/app_config.dart'; // Valida los datos obligatorios del entorno.
import 'core/services/supabase_service.dart'; // Inicializa autenticación, base de datos y almacenamiento.

/// Carga la configuración, inicializa Supabase y abre la aplicación dentro del contenedor de estado.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized(); // Habilita los servicios nativos antes de leer archivos de configuración.

  await dotenv.load(
    fileName: '.env',
  ); // Lee la URL del proyecto y su clave publicable.
  final config =
      AppConfig.fromEnvironment(); // Interrumpe un arranque incompleto con un diagnóstico explícito.
  await SupabaseService.initialize(
    config,
  ); // Espera a que el cliente esté disponible para todos los repositorios.

  runApp(
    const ProviderScope(child: RiexportApp()),
  ); // Inicia la aplicación con sus dependencias observables.
}
