import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'features/dashboard/presentation/pages/dashboard_page.dart';

class CoffeeExportApp extends StatelessWidget {
  const CoffeeExportApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Exportación de café',
      theme: AppTheme.light,
      home: const DashboardPage(),
    );
  }
}
