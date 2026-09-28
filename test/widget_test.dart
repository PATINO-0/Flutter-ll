import 'package:flutter_test/flutter_test.dart';

import 'package:flutterll/app.dart';

void main() {
  testWidgets('Muestra la pantalla inicial', (WidgetTester tester) async {
    await tester.pumpWidget(const CoffeeExportApp());

    expect(find.text('Exportación de café'), findsOneWidget);
    expect(
      find.text('Bienvenido a la plataforma de exportación de café'),
      findsOneWidget,
    );
  });
}
