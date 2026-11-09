import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riexport_ue/features/auth/domain/entities/user_role.dart';
import 'package:riexport_ue/features/commerce/presentation/providers/commerce_providers.dart';
import 'package:riexport_ue/features/dashboard/presentation/widgets/dashboard_home.dart';
import 'package:riexport_ue/features/exports/domain/export_models.dart';
import 'package:riexport_ue/features/exports/presentation/export_providers.dart';
import 'support/fake_repositories.dart';

CoffeeExportRequest request(String id, String status) => CoffeeExportRequest(
  id: id,
  number: 1,
  ownerId: 'owner',
  lotId: id,
  status: status,
  origin: '',
  destination: '',
  recipient: '',
  phone: '',
  documents: [],
  snapshot: {},
);

void main() {
  var queries = 0;
  Future<void> mount(
    WidgetTester tester,
    UserRole role, {
    bool fail = false,
  }) async {
    queries = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          coffeeExportLotsProvider.overrideWith((ref) async {
            queries++;
            return [];
          }),
          coffeeExportRequestsProvider.overrideWith((ref) async {
            queries++;
            if (fail) throw StateError('Conexión no disponible');
            return [
              request('1', 'pending'),
              request('2', 'approved'),
              request('3', 'rejected'),
            ];
          }),
          coffeeShipmentsProvider.overrideWith(
            (ref) async => [
              const CoffeeShipment(
                id: 's',
                code: 'DEMO',
                origin: '',
                destination: '',
                status: 'delivered',
                lotCode: 'l',
                weight: 100,
                events: [],
              ),
            ],
          ),
          customerAccountsProvider.overrideWith((ref) async {
            if (role == UserRole.associate) {
              throw StateError('El asociado no debe consultar clientes');
            }
            return [
              buildProfile([UserRole.client]),
              buildProfile([UserRole.associate]),
            ];
          }),
        ],
        child: MaterialApp(
          home: Scaffold(body: DashboardHome(profile: buildProfile([role]))),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'El personal ve conteos reales y separa solicitudes de transporte',
    (tester) async {
      await mount(tester, UserRole.worker);
      expect(find.text('Clientes y asociados'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('En revisión: 1'), findsOneWidget);
      expect(find.text('Aceptada: 1'), findsOneWidget);
      expect(find.text('Terminado · Entregado: 1'), findsOneWidget);
      expect(find.text('Borrador: 0'), findsOneWidget);
    },
  );
  testWidgets('El asociado no consulta ni muestra el total de clientes', (
    tester,
  ) async {
    await mount(tester, UserRole.associate);
    expect(find.text('Mis operaciones de café'), findsOneWidget);
    expect(find.text('Clientes y asociados'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  for (final role in [UserRole.client, UserRole.transporter]) {
    testWidgets('El rol ${role.name} no abre ni consulta el dashboard', (
      tester,
    ) async {
      await mount(tester, role);
      expect(
        find.text('No tienes acceso al dashboard de café.'),
        findsOneWidget,
      );
      expect(find.text('Solicitudes por estado'), findsNothing);
      expect(queries, 0);
    });
  }
  testWidgets(
    'Un fallo no se presenta como ausencia de exportaciones y permite reintentar',
    (tester) async {
      await mount(tester, UserRole.admin, fail: true);
      expect(
        find.text('No disponible. Actualiza para reintentar.'),
        findsNWidgets(2),
      );
      expect(find.text('En revisión: 0'), findsNothing);
      await tester.tap(find.text('Actualizar indicadores'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'No fue posible consultar los estados. Actualiza para reintentar.',
        ),
        findsOneWidget,
      );
    },
  );
}
