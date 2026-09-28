import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:riexport_ue/app.dart';
import 'package:riexport_ue/core/config/app_router.dart';

void main() {
  testWidgets('Muestra la ruta configurada', (WidgetTester tester) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('Pantalla de prueba'))),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appRouterProvider.overrideWithValue(router)],
        child: const RiexportApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pantalla de prueba'), findsOneWidget);
  });
}
