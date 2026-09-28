import 'package:flutter/material.dart';

import 'features/dashboard/presentation/pages/dashboard_page.dart';

class CoffeeExportApp extends StatelessWidget {
  const CoffeeExportApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Exportación de café',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
      ),
      home: const DashboardPage(),
    );
  }
}
