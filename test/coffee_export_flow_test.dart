import 'package:flutter/material.dart'; // Localiza las pantallas y sus controles.
import 'package:flutter_riverpod/flutter_riverpod.dart'; // Sustituye la red en cada escenario de interfaz.
import 'package:flutter_test/flutter_test.dart'; // Comprueba filtros, autorización y permisos.
import 'package:riexport_ue/app.dart'; // Comprueba también el menú real por rol.
import 'package:riexport_ue/features/auth/domain/entities/user_role.dart'; // Define asociados, empleados y transportadores de prueba.
import 'package:riexport_ue/features/auth/presentation/providers/auth_providers.dart'; // Conserva una sesión controlada.
import 'package:riexport_ue/features/commerce/presentation/providers/commerce_providers.dart'; // Sustituye atención y notificaciones.
import 'package:riexport_ue/features/exports/domain/export_models.dart'; // Describe lotes y envíos del escenario.
import 'package:riexport_ue/features/exports/presentation/export_pages.dart'; // Prueba historial, seguimiento y solicitudes.
import 'package:riexport_ue/features/exports/presentation/export_providers.dart'; // Sustituye el repositorio de exportaciones.
import 'package:riexport_ue/features/exports/presentation/export_request_form_page.dart'; // Comprueba las autorizaciones del asociado.
import 'package:riexport_ue/features/exports/presentation/transport_pages.dart'; // Comprueba la toma y entrega por el transportador.
import 'support/fake_repositories.dart'; // Comparte sesión y perfil sin Supabase.
import 'support/fake_coffee_exports_repository.dart'; // Conserva los datos del nuevo flujo sin efectos remotos.

Future<void> mount(
  WidgetTester tester,
  FakeCoffeeExportsRepository repository, {
  Widget? page,
  UserRole role = UserRole.associate,
}) async {
  final auth = FakeAuthRepository(authenticated: true);
  addTearDown(auth.events.close);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        profileRepositoryProvider.overrideWithValue(
          FakeProfileRepository(buildProfile([role])),
        ),
        commerceRepositoryProvider.overrideWithValue(FakeCommerceRepository()),
        coffeeExportsRepositoryProvider.overrideWithValue(repository),
      ],
      child: page == null ? const RiexportApp() : MaterialApp(home: page),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test(
    'Un lote aprobado no es elegible y un rechazo libera su reserva para corregir',
    () {
      Map<String, dynamic> row(String status) => {
        'id': 'lot',
        'owner_id': 'owner',
        'cultivation_id': 'crop',
        'lot_code': 'LOTE-1',
        'name': 'Café',
        'origin': 'Finca',
        'weight_kg': 100,
        'notes': '',
        'exports': [
          {'status': status},
        ],
      };
      expect(CoffeeExportLot.fromMap(row('approved')).canRequest, isFalse);
      expect(CoffeeExportLot.fromMap(row('pending')).canRequest, isFalse);
      expect(CoffeeExportLot.fromMap(row('rejected')).canRequest, isTrue);
      expect(CoffeeExportLot.fromMap(row('draft')).canRequest, isTrue);
      expect(
        buildProfile([
          UserRole.client,
          UserRole.transporter,
        ]).canManageOperations,
        isFalse,
      );
      expect(
        buildProfile([UserRole.transporter]).canAccessCoffee,
        isFalse,
      ); // Transporte no hereda las funciones del personal.
    },
  );
  testWidgets(
    'Mis envíos solo muestra entregas realizadas y no permite crear solicitudes',
    (tester) async {
      final repository = FakeCoffeeExportsRepository()
        ..shipmentData.addAll([
          coffeeShipment('ACTIVO', 'in_transit'),
          coffeeShipment('ENTREGADO', 'delivered'),
        ]);
      await mount(
        tester,
        repository,
        page: const Scaffold(body: CoffeeShipmentHistoryPage()),
      );
      expect(find.text('RIT-ENTREGADO · LOTE-ENTREGADO'), findsOneWidget);
      expect(find.text('RIT-ACTIVO · LOTE-ACTIVO'), findsNothing);
      expect(
        find.widgetWithText(FilledButton, 'Solicitar exportación'),
        findsNothing,
      );
    },
  );
  testWidgets(
    'Seguimiento excluye lotes entregados y conserva únicamente exportaciones activas',
    (tester) async {
      final repository = FakeCoffeeExportsRepository()
        ..shipmentData.addAll([
          coffeeShipment('ACTIVO', 'received'),
          coffeeShipment('ENTREGADO', 'delivered'),
        ]);
      await mount(
        tester,
        repository,
        page: const Scaffold(body: CoffeeShipmentHistoryPage(tracking: true)),
      );
      expect(find.text('RIT-ACTIVO · LOTE-ACTIVO'), findsOneWidget);
      expect(find.text('RIT-ENTREGADO · LOTE-ENTREGADO'), findsNothing);
    },
  );
  testWidgets(
    'La solicitud requiere autorizar el costo calculado y los datos antes de llegar al chat de Envíos',
    (tester) async {
      final repository = FakeCoffeeExportsRepository()
        ..requestData.add(exportDraft());
      await mount(
        tester,
        repository,
        page: const ExportRequestFormPage(lotId: 'lot'),
      );
      final submit = find.widgetWithText(
        FilledButton,
        'Enviar solicitud al chat de Envíos',
      );
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(repository.submissions, 0);
      final charge = find.widgetWithText(
        CheckboxListTile,
        'Autorizo registrar un cargo de COP 120000.00 en mi cuenta Ritech si la exportación es aceptada.',
      );
      await tester.ensureVisible(charge);
      await tester.tap(charge);
      await tester.pump();
      final data = find.widgetWithText(
        CheckboxListTile,
        'He leído y autorizo el tratamiento de datos para esta exportación y su entrega.',
      );
      await tester.ensureVisible(data);
      await tester.tap(data);
      await tester.pump();
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(repository.submissions, 1);
      expect(repository.chargeAuthorization, isTrue);
      expect(repository.dataAuthorization, isTrue);
      expect(repository.submittedRateId, 'rate');
      expect(find.text('Envíos · EXP-000001'), findsOneWidget);
      await tester.pumpWidget(const SizedBox()); // Cancela el sondeo del chat.
    },
  );
  testWidgets(
    'Exportaciones rechaza abrir una solicitud si no existe un lote elegible',
    (tester) async {
      await mount(
        tester,
        FakeCoffeeExportsRepository(),
        page: const Scaffold(body: CoffeeExportsPage()),
      );
      await tester.tap(
        find.widgetWithText(FilledButton, 'Solicitar exportación'),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Registra en Café un cultivo y un lote que no tenga otra solicitud pendiente o exportación aprobada.',
        ),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'El transportador confirma la entrega antes de finalizar el seguimiento',
    (tester) async {
      final repository = FakeCoffeeExportsRepository();
      await mount(
        tester,
        repository,
        role: UserRole.transporter,
        page: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => FilledButton(
              onPressed: () => showDeliveryUpdate(
                context,
                ref,
                coffeeShipment(
                  'ACTIVO',
                  'in_transit',
                  driverId: 'current-user',
                ),
              ),
              child: const Text('Actualizar'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Actualizar'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Terminado · Entregado').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).first,
        'El destinatario recibió el lote',
      );
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Registrar actualización'),
      );
      await tester.pumpAndSettle();
      expect(repository.lastDeliveryStatus, isNull);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Registrar actualización'),
      );
      await tester.pumpAndSettle();
      expect(repository.lastDeliveryStatus, 'delivered');
      expect(repository.deliveryConfirmed, isTrue);
    },
  );
  testWidgets(
    'El transportador solo ve envíos y su chat; no accede a cultivos ni clientes',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio =
          1; // Comprueba el menú móvil del transportador.
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await mount(
        tester,
        FakeCoffeeExportsRepository(),
        role: UserRole.transporter,
      );
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      expect(find.text('Envíos'), findsOneWidget);
      expect(find.text('Chat de transporte'), findsOneWidget);
      expect(find.text('Clientes'), findsNothing);
      expect(find.text('Café'), findsNothing);
      expect(find.text('Administración de usuarios'), findsNothing);
      await tester.pumpWidget(
        const SizedBox(),
      ); // Cancela las consultas periódicas del transportador y del dashboard.
    },
  );
  testWidgets(
    'El asociado tiene café, convenios propios, exportaciones y atención sin funciones de empleado',
    (tester) async {
      await mount(tester, FakeCoffeeExportsRepository());
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      expect(find.text('Café'), findsOneWidget);
      expect(find.text('Convenios'), findsOneWidget);
      expect(find.text('Exportaciones'), findsOneWidget);
      expect(find.text('Tienda'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Chat de atención'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(Drawer),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('Chat de atención'), findsOneWidget);
      expect(find.text('Clientes'), findsNothing);
      expect(find.text('Transportadores'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Cambiar el destino recalcula el importe y elimina la autorización anterior',
    (tester) async {
      final repository = FakeCoffeeExportsRepository()
        ..requestData.add(exportDraft());
      await mount(
        tester,
        repository,
        page: const ExportRequestFormPage(lotId: 'lot'),
      );
      final charge = find.byType(CheckboxListTile).first;
      await tester.ensureVisible(charge);
      await tester.tap(charge);
      await tester.pump();
      expect(tester.widget<CheckboxListTile>(charge).value, isTrue);
      final destination = find.byKey(
        const ValueKey('destination-Popayán-Bogotá'),
      );
      await tester.ensureVisible(destination);
      await tester.tap(destination);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cartagena').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(charge);
      expect(tester.widget<CheckboxListTile>(charge).value, isFalse);
      expect(find.text('Total: COP 200000.00'), findsOneWidget);
      expect(
        find.text(
          'Autorizo registrar un cargo de COP 200000.00 en mi cuenta Ritech si la exportación es aceptada.',
        ),
        findsOneWidget,
      );
      expect(repository.submissions, 0);
    },
  );

  testWidgets(
    'La selección excluye rutas desactivadas, no habilitadas y tarifas por volumen',
    (tester) async {
      final repository = FakeCoffeeExportsRepository()
        ..requestData.add(exportDraft())
        ..rateData.addAll([
          exportRate(
            'inactive',
            'Origen desactivado',
            'Destino desactivado',
            10,
            active: false,
          ),
          exportRate(
            'import-only',
            'Solo importación',
            'Destino importación',
            10,
            enabled: false,
          ),
          exportRate(
            'volume',
            'Origen por volumen',
            'Destino por volumen',
            10,
            unit: 'm³',
          ),
        ]);
      await mount(
        tester,
        repository,
        page: const ExportRequestFormPage(lotId: 'lot'),
      );
      await tester.tap(find.byKey(const ValueKey('origin-Popayán')));
      await tester.pumpAndSettle();
      expect(find.text('Solo importación'), findsNothing);
      expect(find.text('Origen desactivado'), findsNothing);
      expect(find.text('Origen por volumen'), findsNothing);
      expect(find.text('Popayán').last, findsOneWidget);
    },
  );

  testWidgets(
    'Sin rutas habilitadas no se permite autorizar ni enviar una exportación',
    (tester) async {
      final repository = FakeCoffeeExportsRepository()
        ..requestData.add(exportDraft())
        ..rateData.clear();
      await mount(
        tester,
        repository,
        page: const ExportRequestFormPage(lotId: 'lot'),
      );
      expect(
        find.text(
          'No hay rutas y tarifas habilitadas para exportar café. Contacta al equipo de atención.',
        ),
        findsOneWidget,
      );
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(
        find.widgetWithText(FilledButton, 'Enviar solicitud al chat de Envíos'),
        findsNothing,
      );
      expect(repository.submissions, 0);
    },
  );
}
