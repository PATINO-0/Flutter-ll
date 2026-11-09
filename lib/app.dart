import 'package:flutter/material.dart'; // Construye los controles y estilos Material de la interfaz.
import 'package:flutter_riverpod/flutter_riverpod.dart'; // Comparte consultas, estado y dependencias entre módulos.
import 'package:flutter_localizations/flutter_localizations.dart'; // Traduce también los componentes internos de Flutter.

import 'core/config/app_router.dart'; // Reutiliza las entidades o servicios de app_router.
import 'core/theme/app_theme.dart'; // Reutiliza las entidades o servicios de app_theme.

/// Configura la aplicación Material, su idioma, tema y navegación autenticada.
class RiexportApp extends ConsumerWidget {
  const RiexportApp({super.key});

  /// Construye la interfaz y observa únicamente los datos que necesita esta vista.
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'Ritech', // Identifica la aplicación en el sistema operativo.
      debugShowCheckedModeBanner: false,
      locale: const Locale(
        'es',
        'CO',
      ), // Mantiene el idioma de fechas y controles coherente con los textos de Ritech.
      supportedLocales: const [Locale('es', 'CO')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.light,
      routerConfig: router,
    );
  }
}
