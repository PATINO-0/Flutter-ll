import 'dart:async'; // Mantiene consultas pendientes para reproducir una conexión lenta.
import 'package:flutter/material.dart'; // Comprueba tarjetas desplegadas, menús y formularios reales.
import 'package:flutter_riverpod/flutter_riverpod.dart'; // Observa los proveedores utilizados en producción.
import 'package:flutter_test/flutter_test.dart'; // Avanza los temporizadores sin esperar tiempo real.
import 'package:riexport_ue/app.dart'; // Ejecuta el dashboard y la navegación de la aplicación.
import 'package:riexport_ue/features/auth/domain/entities/user_profile.dart'; // Genera respuestas nuevas con los mismos permisos.
import 'package:riexport_ue/features/auth/domain/entities/user_role.dart'; // Simula promociones y revocaciones reales.
import 'package:riexport_ue/features/auth/domain/repositories/profile_repository.dart'; // Sustituye la consulta de perfiles.
import 'package:riexport_ue/features/auth/presentation/providers/auth_providers.dart'; // Controla las respuestas de autenticación.
import 'package:riexport_ue/features/commerce/presentation/providers/commerce_providers.dart'; // Sustituye avisos y conversaciones.
import 'package:riexport_ue/features/exports/domain/export_models.dart'; // Representa el envío mostrado en seguimiento.
import 'package:riexport_ue/features/exports/presentation/export_providers.dart'; // Mantiene las consultas de exportación de producción.
import 'support/fake_coffee_exports_repository.dart'; // Evita consultas y cargos reales.
import 'support/fake_repositories.dart'; // Comparte sesión, catálogo y perfiles ficticios.

class RefreshingProfileRepository implements ProfileRepository {
  UserProfile profile = buildProfile([
    UserRole.associate,
  ]); // Permite modificar los permisos durante el sondeo.
  int calls =
      0; // Detecta si el temporizador reinicia una consulta todavía pendiente.
  Completer<UserProfile?>?
  pending; // Simula una petición lenta sin cambiar sus datos.
  @override
  Future<UserProfile?> findById(String userId) async {
    calls++;
    if (pending != null) return pending!.future;
    await Future<void>.delayed(const Duration(milliseconds: 80));
    return UserProfile.fromMap(
      profile.toMap(),
    ); // Cada respuesta es otra instancia, como sucede al leer Supabase.
  }
}

class CountingExportsRepository extends FakeCoffeeExportsRepository {
  int shipmentQueries =
      0; // Detecta consultas provocadas únicamente por refrescar el perfil.
  Completer<List<CoffeeShipment>>?
  pending; // Mantiene pendiente una recarga para comprobar que el contenido no se desmonta.
  @override
  Future<List<CoffeeShipment>> shipments() async {
    shipmentQueries++;
    if (pending != null) return pending!.future;
    await Future<void>.delayed(const Duration(milliseconds: 80));
    return shipmentData;
  }
}

/// Monta la aplicación con un seguimiento activo y deja funcionando sus temporizadores reales.
Future<ProviderContainer> mountDashboard(
  WidgetTester tester,
  RefreshingProfileRepository profiles,
  CountingExportsRepository exports,
) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  final auth = FakeAuthRepository(authenticated: true);
  addTearDown(auth.events.close);
  exports.shipmentData.add(
    coffeeShipment('ACTIVO', 'in_transit')
      ..events.add({
        'status': 'in_transit',
        'notes': 'Anotación visible del envío',
        'location': 'Cali',
        'created_at': '2026-11-08T12:00:00Z',
      }),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        profileRepositoryProvider.overrideWithValue(profiles),
        commerceRepositoryProvider.overrideWithValue(FakeCommerceRepository()),
        coffeeExportsRepositoryProvider.overrideWithValue(exports),
      ],
      child: const RiexportApp(),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(RiexportApp)));
}

/// Selecciona una sección como lo haría el asociado desde su menú móvil.
Future<void> openSection(WidgetTester tester, String label) async {
  await tester.tap(find.byIcon(Icons.menu));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'El seguimiento conserva el envío desplegado mientras actualiza sus datos y comprueba permisos',
    (tester) async {
      final profiles = RefreshingProfileRepository();
      final exports = CountingExportsRepository();
      await mountDashboard(tester, profiles, exports);
      await openSection(tester, 'Seguimiento');
      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Anotación visible del envío'),
        findsOneWidget,
      );
      final queries = exports.shipmentQueries;
      exports.pending = Completer<List<CoffeeShipment>>();
      await tester.pump(const Duration(seconds: 15));
      await tester
          .pump(); // Observa también el intervalo en que la consulta del perfil está pendiente.
      await tester.pump(const Duration(milliseconds: 100));
      await tester
          .pump(); // La respuesta del perfil no debe provocar otra consulta del envío.
      expect(
        find.textContaining('Anotación visible del envío'),
        findsOneWidget,
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Anotación visible del envío'),
        findsOneWidget,
      );
      expect(
        exports.shipmentQueries,
        queries + 1,
      ); // Solo consulta el seguimiento una vez, sin duplicarlo por comprobar el perfil.
      exports.pending!.complete([
        coffeeShipment('NUEVO', 'received'),
        ...exports.shipmentData,
      ]);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Anotación visible del envío'),
        findsOneWidget,
      ); // Insertar otro registro tampoco cierra la tarjeta existente.
      expect(find.text('RIT-NUEVO · LOTE-NUEVO'), findsOneWidget);
      expect(
        profiles.calls,
        greaterThan(1),
      ); // La comprobación de permisos sigue activa.
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'El menú abierto permanece visible durante varias comprobaciones de permisos',
    (tester) async {
      final profiles = RefreshingProfileRepository();
      await mountDashboard(tester, profiles, CountingExportsRepository());
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      final scaffold = tester.state<ScaffoldState>(find.byType(Scaffold).first);
      for (var cycle = 0; cycle < 3; cycle++) {
        await tester.pump(const Duration(seconds: 15));
        await tester.pumpAndSettle();
        expect(scaffold.isDrawerOpen, isTrue);
        expect(find.text('Café'), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Una consulta lenta de permisos no se reinicia por cada intervalo del temporizador',
    (tester) async {
      final profiles = RefreshingProfileRepository();
      await mountDashboard(tester, profiles, CountingExportsRepository());
      profiles.pending = Completer<UserProfile?>();
      await tester.pump(const Duration(seconds: 15));
      await tester.pump();
      final pendingCalls = profiles.calls;
      await tester.pump(const Duration(seconds: 30));
      await tester.pump();
      expect(profiles.calls, pendingCalls);
      profiles.pending!.complete(UserProfile.fromMap(profiles.profile.toMap()));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Un cambio real de rol retira el módulo que ya no está autorizado',
    (tester) async {
      final profiles = RefreshingProfileRepository();
      await mountDashboard(tester, profiles, CountingExportsRepository());
      await openSection(tester, 'Seguimiento');
      expect(find.text('RIT-ACTIVO · LOTE-ACTIVO'), findsOneWidget);
      profiles.profile = buildProfile([UserRole.client]);
      await tester.pump(const Duration(seconds: 15));
      await tester.pumpAndSettle();
      expect(find.text('RIT-ACTIVO · LOTE-ACTIVO'), findsNothing);
      expect(find.text('Tienda de tarifas y destinos'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'El formulario y su destino desplegado permanecen abiertos durante el sondeo',
    (tester) async {
      final profiles = RefreshingProfileRepository();
      final exports = CountingExportsRepository()
        ..requestData.add(exportDraft())
        ..lotData.add(
          const CoffeeExportLot(
            id: 'lot',
            name: 'Café de prueba',
            origin: 'Popayán',
            weight: 100,
            notes: '',
            ownerId: 'current-user',
            cultivationId: 'crop',
            code: 'LOTE-1',
          ),
        );
      await mountDashboard(tester, profiles, exports);
      await openSection(tester, 'Exportaciones');
      await tester.tap(
        find.widgetWithText(FilledButton, 'Solicitar exportación'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Continuar'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).first,
        'Finca de origen pendiente de envío',
      );
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      final destination = find.byKey(
        const ValueKey('destination-Popayán-Bogotá'),
      );
      await tester.ensureVisible(destination);
      await tester.tap(destination);
      await tester.pumpAndSettle();
      expect(find.text('Cartagena'), findsOneWidget);
      for (var cycle = 0; cycle < 3; cycle++) {
        await tester.pump(const Duration(seconds: 15));
        await tester.pumpAndSettle();
        expect(find.text('Cartagena'), findsOneWidget);
      }
      await tester.tap(find.text('Cartagena'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller
            ?.text,
        'Finca de origen pendiente de envío',
      );
      expect(find.text('Total: COP 200000.00'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Una desactivación real bloquea el panel aunque existan datos anteriores',
    (tester) async {
      final profiles = RefreshingProfileRepository();
      await mountDashboard(tester, profiles, CountingExportsRepository());
      await openSection(tester, 'Seguimiento');
      profiles.profile = UserProfile.fromMap({
        ...profiles.profile.toMap(),
        'is_active': false,
      });
      await tester.pump(const Duration(seconds: 15));
      await tester.pumpAndSettle();
      expect(find.text('RIT-ACTIVO · LOTE-ACTIVO'), findsNothing);
      expect(
        find.text(
          'Tu acceso a Ritech fue retirado. Contacta al administrador.',
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Al pasar de trabajador a asociado se retiran los datos globales mientras se consulta su información propia',
    (tester) async {
      final profiles = RefreshingProfileRepository()
        ..profile = buildProfile([UserRole.worker]);
      final exports = CountingExportsRepository()
        ..shipmentData.add(coffeeShipment('OTRO-ASOCIADO', 'received'));
      await mountDashboard(tester, profiles, exports);
      await openSection(tester, 'Seguimiento');
      expect(
        find.text('RIT-OTRO-ASOCIADO · LOTE-OTRO-ASOCIADO'),
        findsOneWidget,
      );
      exports.pending = Completer<List<CoffeeShipment>>();
      profiles.profile = buildProfile([UserRole.associate]);
      await tester.pump(const Duration(seconds: 15));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(find.text('RIT-OTRO-ASOCIADO · LOTE-OTRO-ASOCIADO'), findsNothing);
      exports.pending!.complete([coffeeShipment('PROPIO', 'received')]);
      await tester.pumpAndSettle();
      expect(find.text('RIT-PROPIO · LOTE-PROPIO'), findsOneWidget);
      expect(find.text('RIT-OTRO-ASOCIADO · LOTE-OTRO-ASOCIADO'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
