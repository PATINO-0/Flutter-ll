import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  const AppConfig({
    required this.supabaseUrl,
    required this.supabasePublishableKey,
  });

  final String supabaseUrl;
  final String supabasePublishableKey;

  factory AppConfig.fromEnvironment() {
    final supabaseUrl = dotenv.get('SUPABASE_URL', fallback: '').trim();
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
