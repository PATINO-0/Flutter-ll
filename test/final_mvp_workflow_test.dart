import 'package:flutter/material.dart'; // Localiza los controles de vinculación y supervisión.
import 'package:flutter_riverpod/flutter_riverpod.dart'; // Sustituye el backend con repositorios controlados.
import 'package:flutter_test/flutter_test.dart'; // Comprueba aceptación, motivo y permisos visibles.
import 'package:riexport_ue/features/auth/domain/entities/user_role.dart'; // Define clientes, empleados y asociados de prueba.
import 'package:riexport_ue/features/auth/presentation/providers/auth_providers.dart'; // Proporciona la sesión y el perfil del escenario.
import 'package:riexport_ue/features/commerce/domain/entities/commerce_models.dart'; // Construye convenios sin datos de personas reales.
import 'package:riexport_ue/features/commerce/presentation/pages/customer_accounts_page.dart'; // Comprueba la gestión de un convenio por cliente.
import 'package:riexport_ue/features/commerce/presentation/pages/association_detail_page.dart'; // Comprueba que el titular acepte expresamente.
import 'package:riexport_ue/features/commerce/presentation/providers/commerce_providers.dart'; // Comparte expedientes y convenios.
import 'package:riexport_ue/features/exports/domain/export_models.dart'; // Construye un cultivo para supervisión.
import 'package:riexport_ue/features/exports/presentation/coffee_crops_page.dart'; // Comprueba el acceso de consulta del trabajador.
import 'package:riexport_ue/features/exports/presentation/export_providers.dart'; // Sustituye el inventario real de café.
import 'support/fake_repositories.dart'; // Comparte clientes y sesiones ficticias.
import 'support/fake_coffee_exports_repository.dart'; // Evita consultas a Supabase durante los tests.

/// Conserva una propuesta completa pendiente de la respuesta de su titular.
AssociationRequest pendingProposal() => AssociationRequest(
  id: 'request',
  ownerId: 'current-user',
  status: 'approved',
  fullName: 'Cliente de prueba',
  identityNumber: '12345678',
  phone: '3001234567',
  address: 'Calle de prueba 1',
  businessDescription: 'Exportación de café',
  documents: const [],
  agreementId: 'agreement',
  agreementStatus: 'awaiting_acceptance',
  agreementExpiresAt: DateTime.now().add(const Duration(days: 365)),
);

/// Instala los mismos proveedores de producción con una cuenta y un inventario locales.
Future<void> mountMvp(
  WidgetTester tester,
  Widget page,
  FakeCommerceRepository commerce, {
  UserRole role = UserRole.worker,
}) async {
  final auth = FakeAuthRepository(authenticated: true);
  commerce.customers.add(
    buildProfile([UserRole.client]),
  ); // Mantiene una cuenta comercial visible en el panel bajo prueba.
  addTearDown(auth.events.close);
  final coffee = FakeCoffeeExportsRepository()
    ..cropData.add(
      const CoffeeCultivation(
        id: 'crop',
        ownerId: 'owner',
        name: 'Cultivo observado',
        farm: 'Finca La Prueba',
        location: 'Popayán',
        variety: 'Caturra',
        hectares: 2.5,
        ownerName: 'Titular del cultivo',
        ownerEmail: 'owner@example.com',
      ),
    );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        profileRepositoryProvider.overrideWithValue(
          FakeProfileRepository(buildProfile([role])),
        ),
        commerceRepositoryProvider.overrideWithValue(commerce),
        coffeeExportsRepositoryProvider.overrideWithValue(coffee),
      ],
      child: MaterialApp(home: page),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'El empleado consulta el cultivo y su titular sin acciones de creación ni edición',
    (tester) async {
      await mountMvp(
        tester,
        const Scaffold(body: CoffeeCropsPage()),
        FakeCommerceRepository(),
      );
      expect(find.text('Cultivo observado'), findsOneWidget);
      expect(find.textContaining('Titular del cultivo'), findsOneWidget);
      expect(find.textContaining('owner@example.com'), findsOneWidget);
      expect(find.text('Registrar cultivo'), findsNothing);
      expect(find.text('Registrar lote'), findsNothing);
      expect(find.byTooltip('Editar cultivo'), findsNothing);
    },
  );

  testWidgets('El asociado conserva las acciones sobre sus propios cultivos', (
    tester,
  ) async {
    await mountMvp(
      tester,
      const Scaffold(body: CoffeeCropsPage()),
      FakeCommerceRepository(),
      role: UserRole.associate,
    );
    expect(find.text('Registrar cultivo'), findsOneWidget);
    expect(find.text('Registrar lote'), findsOneWidget);
    expect(find.byTooltip('Editar cultivo'), findsOneWidget);
  });

  testWidgets(
    'Clientes bloquea otra propuesta mientras existe un convenio abierto',
    (tester) async {
      final repository = FakeCommerceRepository();
      repository.agreements.add(
        Agreement(
          id: 'agreement',
          number: 1,
          request: pendingProposal(),
          createdAt: DateTime.now(),
          status: 'active',
          expiresAt: DateTime.now().add(const Duration(days: 365)),
        ),
      );
      await mountMvp(
        tester,
        const Scaffold(body: CustomerAccountsPage()),
        repository,
      );
      expect(find.text('Preparar convenio'), findsNothing);
      expect(find.text('Revocar convenio con motivo'), findsOneWidget);
      expect(find.textContaining('Activo'), findsOneWidget);
    },
  );

  testWidgets(
    'El empleado debe explicar la revocación antes de enviarla al titular',
    (tester) async {
      final repository = FakeCommerceRepository()
        ..agreements.add(
          Agreement(
            id: 'agreement',
            number: 1,
            request: pendingProposal(),
            createdAt: DateTime.now(),
          ),
        );
      await mountMvp(
        tester,
        const Scaffold(body: CustomerAccountsPage()),
        repository,
      );
      await tester.tap(find.text('Revocar convenio con motivo'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Confirmar'));
      await tester.pumpAndSettle();
      expect(repository.revokedAgreementId, isNull);
      await tester.enterText(
        find.byType(TextFormField),
        'Finalización solicitada por el cliente',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Confirmar'));
      await tester.pumpAndSettle();
      expect(repository.revokedAgreementId, 'agreement');
      expect(
        repository.agreementRevocationReason,
        'Finalización solicitada por el cliente',
      );
    },
  );

  testWidgets(
    'La propuesta no se acepta sin confirmar documentos, vigencia y tratamiento de datos',
    (tester) async {
      final repository = FakeCommerceRepository()
        ..requests.add(pendingProposal());
      await mountMvp(
        tester,
        const AssociationDetailPage(requestId: 'request'),
        repository,
        role: UserRole.client,
      );
      await tester.tap(find.text('Aceptar mi convenio'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Confirmar'));
      await tester.pumpAndSettle();
      expect(repository.respondedAgreementId, isNull);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.tap(find.widgetWithText(FilledButton, 'Confirmar'));
      await tester.pumpAndSettle();
      expect(repository.respondedAgreementId, 'agreement');
      expect(repository.agreementAccepted, isTrue);
      expect(repository.agreementTermsAccepted, isTrue);
    },
  );
}
