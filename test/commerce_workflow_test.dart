import 'dart:typed_data'; // Comprueba las cabeceras de documentos sin usar archivos reales.
import 'package:flutter/material.dart'; // Localiza controles y pantallas del flujo.
import 'package:flutter_riverpod/flutter_riverpod.dart'; // Sustituye los servicios externos por repositorios controlados.
import 'package:flutter_test/flutter_test.dart'; // Ejecuta las pruebas de interfaz y permisos.
import 'package:riexport_ue/core/errors/app_exception.dart'; // Comprueba errores de validación traducidos.
import 'package:riexport_ue/features/auth/domain/entities/user_role.dart'; // Define los niveles de acceso del escenario.
import 'package:riexport_ue/features/auth/domain/entities/user_profile.dart'; // Comprueba la pérdida de acceso de una cuenta desactivada.
import 'package:riexport_ue/features/auth/presentation/providers/auth_providers.dart'; // Conserva una sesión válida durante las pruebas.
import 'package:riexport_ue/features/commerce/data/repositories/supabase_commerce_repository.dart'; // Prueba la validación real de archivos.
import 'package:riexport_ue/features/commerce/domain/entities/commerce_models.dart'; // Construye expedientes sin información personal real.
import 'package:riexport_ue/features/commerce/presentation/pages/association_form_page.dart'; // Prueba la autorización y el envío del formulario.
import 'package:riexport_ue/features/commerce/presentation/pages/association_detail_page.dart'; // Prueba las decisiones del trabajador.
import 'package:riexport_ue/features/commerce/presentation/providers/commerce_providers.dart'; // Reemplaza las consultas del módulo.
import 'support/fake_repositories.dart'; // Comparte repositorios simulados sin red.

AssociationRequest draftRequest() => AssociationRequest(
  id: 'request',
  ownerId: 'current-user',
  status: 'draft',
  fullName: 'Persona de prueba',
  identityNumber: '12345678',
  phone: '+57 3001234567',
  address: 'Calle 10 número 20',
  businessDescription: 'Importación de productos comerciales',
  documents: [
    for (final kind in AgreementDocumentKind.values)
      RequestDocument(
        kind: kind.value,
        path: kind.value,
        name: '${kind.value}.pdf',
      ),
  ],
); // Conserva tres soportes ficticios completos.

Future<void> mount(
  WidgetTester tester,
  Widget page,
  FakeCommerceRepository repository, {
  List<UserRole> roles = const [UserRole.client],
}) async {
  final auth = FakeAuthRepository(authenticated: true);
  addTearDown(auth.events.close);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        profileRepositoryProvider.overrideWithValue(
          FakeProfileRepository(buildProfile(roles)),
        ),
        commerceRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(home: page),
    ),
  );
  await tester.pumpAndSettle(); // Espera la carga de los expedientes simulados.
}

void main() {
  test(
    'Predomina el rol de mayor acceso y una cuenta desactivada no conserva privilegios',
    () {
      expect(
        buildProfile([UserRole.client, UserRole.associate]).effectiveRole,
        UserRole.associate,
      );
      expect(
        buildProfile([UserRole.client, UserRole.associate]).canAccessStore,
        isTrue, // El asociado consulta las tarifas para seleccionar su ruta.
      );
      expect(
        buildProfile([UserRole.client, UserRole.worker]).canManageOperations,
        isTrue,
      );
      expect(buildProfile([UserRole.worker, UserRole.admin]).isAdmin, isTrue);
      expect(
        buildProfile([UserRole.client]).canCreateShipments,
        isFalse,
      ); // Un cliente no importa ni consulta envíos antes del convenio.
      final disabled = UserProfile.fromMap({
        ...buildProfile([UserRole.admin]).toMap(),
        'is_active': false,
      }); // Simula una sesión anterior a la eliminación de acceso.
      expect(disabled.effectiveRole, isNull);
      expect(
        disabled.isAdmin,
        isFalse,
      ); // No conserva privilegios por tener un token o rol antiguo.
    },
  );
  test(
    'Los soportes se validan por contenido y se rechazan formatos ajenos',
    () {
      expect(
        SupabaseCommerceRepository.documentType(
          Uint8List.fromList('%PDF-1.7'.codeUnits),
        ),
        'pdf',
      );
      expect(
        SupabaseCommerceRepository.documentType(
          Uint8List.fromList([255, 216, 255, 0]),
        ),
        'jpg',
      );
      expect(
        SupabaseCommerceRepository.documentType(
          Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
        ),
        'png',
      );
      expect(
        () => SupabaseCommerceRepository.documentType(
          Uint8List.fromList('<html>archivo falso.pdf</html>'.codeUnits),
        ),
        throwsA(isA<AppException>()),
      );
      expect(
        () => SupabaseCommerceRepository.documentType(
          Uint8List(10 * 1024 * 1024 + 1),
        ),
        throwsA(isA<AppException>()),
      );
    },
  );
  testWidgets(
    'El cliente debe aceptar el tratamiento de datos antes de enviar y continuar al chat',
    (tester) async {
      final repository = FakeCommerceRepository()..requests.add(draftRequest());
      await mount(
        tester,
        AssociationFormPage(customer: buildProfile([UserRole.client])),
        repository,
      );
      final send = find.widgetWithText(
        FilledButton,
        'Enviar solicitud y abrir chat',
      );
      await tester.ensureVisible(send);
      await tester.tap(send);
      await tester.pumpAndSettle();
      expect(
        repository.submittedCount,
        0,
      ); // No envía un expediente completo si falta la autorización.
      expect(
        find.text('Debes aceptar el tratamiento de datos antes de enviar.'),
        findsOneWidget,
      );
      final consent = find.byType(CheckboxListTile);
      await tester.ensureVisible(consent);
      await tester.tap(consent);
      await tester.pump();
      await tester.ensureVisible(send);
      await tester.tap(send);
      await tester.pumpAndSettle();
      expect(repository.submittedCount, 1);
      expect(repository.submittedConsent, isTrue);
      expect(
        find.text('Atención Ritech'),
        findsOneWidget,
      ); // Continúa la petición en el canal interno, sin enviar mensajes externos.
      await tester.pumpWidget(
        const SizedBox(),
      ); // Cancela el sondeo del chat al cerrar la prueba.
    },
  );
  testWidgets(
    'El trabajador rechaza una solicitud únicamente cuando explica las correcciones',
    (tester) async {
      final request = draftRequest();
      final repository = FakeCommerceRepository()
        ..requests.add(
          AssociationRequest(
            id: request.id,
            ownerId: request.ownerId,
            status: 'pending',
            fullName: request.fullName,
            identityNumber: request.identityNumber,
            phone: request.phone,
            address: request.address,
            businessDescription: request.businessDescription,
            documents: request.documents,
          ),
        );
      await mount(
        tester,
        const AssociationDetailPage(requestId: 'request'),
        repository,
        roles: [UserRole.worker],
      );
      final reject = find.widgetWithText(
        OutlinedButton,
        'Rechazar con correcciones',
      );
      await tester.ensureVisible(reject);
      await tester.tap(reject);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Confirmar'));
      await tester.pumpAndSettle();
      expect(repository.reviewedApproval, isNull);
      await tester.enterText(
        find.byType(TextFormField),
        'Adjunta una identificación legible',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Confirmar'));
      await tester.pumpAndSettle();
      expect(repository.reviewedApproval, isFalse);
      expect(repository.reviewedReason, 'Adjunta una identificación legible');
    },
  );
}
