import 'package:flutter/material.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Exportación de café')),
      body: const Center(
        child: Text('Bienvenido a la plataforma de exportación de café'),
      ),
    );
  }
}
