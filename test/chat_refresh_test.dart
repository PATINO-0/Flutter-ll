import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riexport_ue/core/errors/app_exception.dart';
import 'package:riexport_ue/features/auth/domain/entities/user_role.dart';
import 'package:riexport_ue/features/auth/presentation/providers/auth_providers.dart';
import 'package:riexport_ue/features/commerce/domain/entities/commerce_models.dart';
import 'package:riexport_ue/features/commerce/presentation/pages/support_chat_page.dart';
import 'package:riexport_ue/features/commerce/presentation/providers/commerce_providers.dart';
import 'support/fake_repositories.dart';

class ChatRepository extends FakeCommerceRepository {
  int sent = 0;
  bool reject = false;
  @override
  Future<void> sendMessage(String conversationId, String body) async {
    if (reject) throw const AppException('Envío rechazado de prueba');
    sent++;
    messages.add(
      SupportMessage(
        id: '$sent',
        senderId: 'current-user',
        body: body,
        kind: 'text',
        createdAt: DateTime.utc(2026, 11, 9),
      ),
    );
  }
}

void main() {
  Future<void> mount(WidgetTester tester, ChatRepository repo) async {
    final auth = FakeAuthRepository(authenticated: true);
    addTearDown(auth.events.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          currentUserProfileProvider.overrideWith(
            (ref) async => buildProfile([UserRole.associate]),
          ),
          commerceRepositoryProvider.overrideWithValue(repo),
        ],
        child: const MaterialApp(
          home: SupportChatPage(conversationId: 'demo', title: 'Chat DEMO'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Un envío confirmado actualiza el chat sin advertencia falsa ni duplicados',
    (tester) async {
      final repo = ChatRepository();
      await mount(tester, repo);
      await tester.enterText(find.byType(TextField), 'Café listo');
      await tester.tap(find.byTooltip('Enviar mensaje'));
      await tester.pumpAndSettle();
      expect(repo.sent, 1);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('Café listo'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Actualizar manualmente y el sondeo no devuelven Futures a setState',
    (tester) async {
      await mount(tester, ChatRepository());
      await tester.tap(find.byTooltip('Actualizar conversación'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Un rechazo real conserva el borrador y muestra su error', (
    tester,
  ) async {
    final repo = ChatRepository()..reject = true;
    await mount(tester, repo);
    await tester.enterText(find.byType(TextField), 'Conservar borrador');
    await tester.tap(find.byTooltip('Enviar mensaje'));
    await tester.pumpAndSettle();
    expect(repo.sent, 0);
    expect(find.text('Envío rechazado de prueba'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Conservar borrador',
    );
    await tester.pumpWidget(const SizedBox());
  });
}
