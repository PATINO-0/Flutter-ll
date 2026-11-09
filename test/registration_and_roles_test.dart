import 'package:flutter/material.dart'; // Permite localizar campos y controles del formulario.
import 'package:flutter_riverpod/flutter_riverpod.dart'; // Sustituye dependencias externas en las pruebas.
import 'package:flutter_test/flutter_test.dart'; // Ejecuta las pruebas de interfaz y dominio.

import 'package:riexport_ue/app.dart'; // Ejecuta la aplicación con su router real.
import 'package:riexport_ue/core/config/app_router.dart'; // Comprueba también los accesos directos a rutas.
import 'package:riexport_ue/core/constants/app_routes.dart'; // Comparte las rutas protegidas y públicas.
import 'package:riexport_ue/core/errors/app_exception.dart'; // Simula errores recuperables.
import 'package:riexport_ue/core/utils/validators.dart'; // Comprueba las validaciones antes del envío.
import 'package:riexport_ue/features/administration/presentation/providers/administration_providers.dart'; // Sustituye el servicio administrativo.
import 'package:riexport_ue/features/auth/domain/entities/user_profile.dart'; // Comprueba la conversión segura de perfiles.
import 'package:riexport_ue/features/auth/domain/entities/user_role.dart'; // Define los escenarios de permisos.
import 'package:riexport_ue/features/auth/presentation/providers/auth_providers.dart'; // Sustituye autenticación y perfiles.

import 'support/fake_repositories.dart'; // Comparte implementaciones de prueba sin red.
import 'package:riexport_ue/features/commerce/presentation/providers/commerce_providers.dart'; // Aísla el catálogo y las notificaciones del proyecto real.

/// Inicia la aplicación con dependencias controladas y libera sus recursos al terminar.
Future<void> mountApp(
  WidgetTester tester, {
  required FakeAuthRepository auth,
  List<UserRole> roles = const [UserRole.client],
  FakeUserManagementRepository? management,
}) async {
  addTearDown(
    auth.events.close,
  ); // Libera el flujo de cambios de sesión del escenario.
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        commerceRepositoryProvider.overrideWithValue(
          FakeCommerceRepository(),
        ), // Permite probar los nuevos menús sin una conexión remota.
        authRepositoryProvider.overrideWithValue(
          auth,
        ), // Evita solicitudes reales de autenticación.
        profileRepositoryProvider.overrideWithValue(
          FakeProfileRepository(buildProfile(roles)),
        ),
        userManagementRepositoryProvider.overrideWithValue(
          management ?? FakeUserManagementRepository([]),
        ),
      ],
      child:
          const RiexportApp(), // Comprueba la integración con la navegación real.
    ),
  );
  await tester
      .pumpAndSettle(); // Espera la carga del perfil y las redirecciones.
}

/// Completa los campos visibles del registro con datos reproducibles.
Future<void> fillRegistration(
  WidgetTester tester, {
  String confirmation = 'password123',
}) async {
  final fields = find.byType(
    TextFormField,
  ); // Conserva el orden del formulario compartido.
  await tester.enterText(
    fields.at(0),
    'Persona de prueba',
  ); // Completa el nombre válido.
  await tester.enterText(
    fields.at(1),
    'person@example.com',
  ); // Completa el correo válido.
  await tester.enterText(
    fields.at(2),
    'password123',
  ); // Completa una contraseña admitida.
  await tester.enterText(
    fields.at(3),
    confirmation,
  ); // Permite probar una confirmación diferente.
}

void main() {
  testWidgets(
    'El menú móvil muestra las funciones del trabajador sin administración',
    (tester) async {
      tester.view.physicalSize = const Size(
        390,
        844,
      ); // Reproduce una pantalla móvil vertical.
      tester.view.devicePixelRatio =
          1; // Mantiene dimensiones reproducibles en la prueba.
      addTearDown(
        tester.view.resetPhysicalSize,
      ); // Restaura el tamaño original al terminar.
      addTearDown(
        tester.view.resetDevicePixelRatio,
      ); // Restaura la escala original de la vista.
      await mountApp(
        tester,
        auth: FakeAuthRepository(authenticated: true),
        roles: [UserRole.worker],
      );
      await tester.tap(
        find.byIcon(Icons.menu),
      ); // Abre la navegación del trabajador.
      await tester.pumpAndSettle(); // Espera que el menú quede visible.
      expect(
        find.text('Café'),
        findsOneWidget,
      ); // Conserva el módulo de productos existente.
      expect(
        find.text('Clientes'),
        findsOneWidget,
      ); // Habilita la gestión interna de clientes.
      expect(
        find.text('Exportaciones'),
        findsOneWidget,
      ); // Habilita la navegación operativa.
      expect(
        find.text('Administración de usuarios'),
        findsNothing,
      ); // Un trabajador no administra cuentas.
      expect(
        find.text('Convenios'),
        findsOneWidget,
      ); // El trabajador gestiona los convenios de los asociados.
      expect(
        tester.takeException(),
        isNull,
      ); // Comprueba que el menú no desborda en móvil.
    },
  );

  testWidgets(
    'El panel de administrador admite todos los módulos en escritorio',
    (tester) async {
      tester.view.physicalSize = const Size(
        1280,
        1100,
      ); // Reproduce el diseño de escritorio con etiquetas visibles.
      tester.view.devicePixelRatio =
          1; // Evita depender de la escala del equipo de pruebas.
      addTearDown(
        tester.view.resetPhysicalSize,
      ); // Restaura las dimensiones al terminar.
      addTearDown(
        tester.view.resetDevicePixelRatio,
      ); // Restaura la escala al terminar.
      await mountApp(
        tester,
        auth: FakeAuthRepository(authenticated: true),
        roles: [UserRole.admin],
      );
      expect(
        find.byType(NavigationRail),
        findsOneWidget,
      ); // Utiliza el menú lateral de escritorio.
      expect(
        find.text('Administración de usuarios'),
        findsOneWidget,
      ); // Presenta el acceso administrativo adicional.
      expect(
        find.text('Convenios'),
        findsOneWidget,
      ); // Habilita la navegación de convenios al administrador.
      expect(
        tester.takeException(),
        isNull,
      ); // Comprueba que todos los destinos caben en el menú.
    },
  );

  test(
    'Los perfiles descartan roles desconocidos y no conceden permisos cuando no hay roles',
    () {
      final profile = UserProfile.fromMap({
        'id': 'person',
        'full_name': 'Persona',
        'email': 'person@example.com',
        'created_at': '2026-11-08T00:00:00Z',
        'updated_at': '2026-11-08T00:00:00Z',
        'roles': [
          {'role': 'owner'},
          {'role': 'client'},
          {'role': 'client'},
        ],
      }); // Reproduce roles malformados, desconocidos y duplicados.
      expect(profile.roles, [
        UserRole.client,
      ]); // Conserva solamente permisos reconocidos sin duplicados.
      expect(
        profile.isAdmin,
        isFalse,
      ); // Nunca interpreta un valor desconocido como administrador.
      expect(
        buildProfile([]).canManageOperations,
        isFalse,
      ); // Un perfil sin roles no gestiona operaciones.
      expect(
        buildProfile([UserRole.worker]).canManageOperations,
        isTrue,
      ); // Un trabajador accede a sus módulos.
      expect(
        buildProfile([UserRole.associate]).canManageAgreements,
        isTrue,
      ); // Un asociado accede a convenios.
    },
  );

  test(
    'Las validaciones distinguen el acceso existente de los requisitos para contraseñas nuevas',
    () {
      expect(
        Validators.password('short'),
        isNull,
      ); // No bloquea cuentas antiguas por una regla nueva.
      expect(
        Validators.newPassword('short'),
        isNotNull,
      ); // Exige ocho caracteres en las altas.
      expect(
        Validators.newPassword('password123'),
        isNull,
      ); // Admite una contraseña de longitud válida.
      expect(
        Validators.fullName('  '),
        isNotNull,
      ); // Rechaza nombres vacíos tras normalizarlos.
      expect(
        Validators.email('invalid'),
        isNotNull,
      ); // Rechaza correos sin un formato válido.
    },
  );

  testWidgets(
    'El registro público solicita confirmación y nunca ofrece elegir roles',
    (tester) async {
      final auth =
          FakeAuthRepository(); // Simula un proyecto que exige confirmar el correo.
      await mountApp(
        tester,
        auth: auth,
      ); // Muestra inicialmente el inicio de sesión.
      await tester.tap(
        find.text('¿No tienes una cuenta? Regístrate'),
      ); // Abre el registro desde la opción pública.
      await tester.pumpAndSettle(); // Espera el cambio de ruta.
      expect(
        find.byType(CheckboxListTile),
        findsNothing,
      ); // Impide elegir roles en el registro público.
      await fillRegistration(
        tester,
      ); // Completa el formulario con datos válidos.
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Crear cuenta'),
      ); // Desplaza el formulario en pantallas pequeñas.
      await tester.tap(
        find.widgetWithText(FilledButton, 'Crear cuenta'),
      ); // Solicita el registro público.
      await tester
          .pumpAndSettle(); // Espera el resultado de la autenticación simulada.
      expect(
        find.text('Revisa tu correo'),
        findsOneWidget,
      ); // Explica el siguiente paso antes de iniciar sesión.
      expect(
        auth.hasSession,
        isFalse,
      ); // No concede una sesión antes de confirmar el correo.
      expect(auth.signUpCalls, 1); // Envía una sola solicitud de registro.
    },
  );

  testWidgets('Una confirmación distinta impide enviar el registro', (
    tester,
  ) async {
    final auth =
        FakeAuthRepository(); // Permite comprobar si se llamó al servidor.
    await mountApp(tester, auth: auth); // Inicia la aplicación sin sesión.
    await tester.tap(find.text('¿No tienes una cuenta? Regístrate'));
    await tester.pumpAndSettle(); // Espera el formulario de registro.
    await fillRegistration(
      tester,
      confirmation: 'different123',
    ); // Introduce una confirmación equivocada.
    await tester.ensureVisible(
      find.widgetWithText(FilledButton, 'Crear cuenta'),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Crear cuenta'));
    await tester.pumpAndSettle(); // Presenta la validación local.
    expect(find.text('Las contraseñas no coinciden.'), findsOneWidget);
    expect(auth.signUpCalls, 0); // No crea solicitudes con datos inválidos.
  });

  testWidgets('El registro con sesión automática abre el panel de cliente', (
    tester,
  ) async {
    final auth = FakeAuthRepository(
      requiresConfirmation: false,
    ); // Simula el acceso automático permitido por Supabase.
    await mountApp(tester, auth: auth);
    await tester.tap(find.text('¿No tienes una cuenta? Regístrate'));
    await tester.pumpAndSettle(); // Abre la pantalla pública.
    await fillRegistration(tester); // Completa los datos requeridos.
    await tester.ensureVisible(
      find.widgetWithText(FilledButton, 'Crear cuenta'),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Crear cuenta'));
    await tester
        .pumpAndSettle(); // Espera la redirección provocada por la sesión nueva.
    expect(
      find.text('Tienda de tarifas y destinos'),
      findsOneWidget,
    ); // Muestra el panel personalizado.
    expect(
      find.text('Quiero convertirme en asociado exportador'),
      findsOneWidget,
    ); // Refleja el permiso básico del registro.
  });

  testWidgets('Un error de registro conserva el formulario para reintentar', (
    tester,
  ) async {
    final auth = FakeAuthRepository()
      ..signUpError = const AppException('No fue posible crear la cuenta.');
    await mountApp(tester, auth: auth);
    await tester.tap(find.text('¿No tienes una cuenta? Regístrate'));
    await tester.pumpAndSettle(); // Espera la pantalla de alta.
    await fillRegistration(tester);
    await tester.ensureVisible(
      find.widgetWithText(FilledButton, 'Crear cuenta'),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Crear cuenta'));
    await tester.pumpAndSettle(); // Espera el error controlado del repositorio.
    expect(find.text('No fue posible crear la cuenta.'), findsOneWidget);
    expect(
      find.byType(TextFormField),
      findsNWidgets(4),
    ); // Conserva los datos para un nuevo intento.
  });

  testWidgets(
    'El cliente no ve administración y una ruta directa lo devuelve al panel',
    (tester) async {
      await mountApp(tester, auth: FakeAuthRepository(authenticated: true));
      expect(
        find.text('Administración de usuarios'),
        findsNothing,
      ); // Oculta el módulo exclusivo del administrador.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(RiexportApp)),
      );
      container
          .read(appRouterProvider)
          .go(
            AppRoutes.administration,
          ); // Simula un enlace directo a la ruta protegida.
      await tester.pumpAndSettle(); // Espera la comprobación de permisos.
      expect(
        container
            .read(appRouterProvider)
            .routeInformationProvider
            .value
            .uri
            .path,
        AppRoutes.dashboard,
      );
      expect(
        find.text('Tienda de tarifas y destinos'),
        findsOneWidget,
      ); // Conserva el acceso a las funciones propias.
    },
  );

  testWidgets('Una cuenta sin roles conserva un panel válido en escritorio', (
    tester,
  ) async {
    await mountApp(
      tester,
      auth: FakeAuthRepository(authenticated: true),
      roles: [],
    );
    expect(
      find.textContaining('Todavía no tienes roles asignados.'),
      findsOneWidget,
    );
    expect(
      tester.takeException(),
      isNull,
    ); // Comprueba que la navegación admite una sola sección.
  });

  testWidgets('El administrador asigna y retira varios roles desde el panel', (
    tester,
  ) async {
    final management = FakeUserManagementRepository([
      buildProfile([UserRole.client], id: 'target-user'),
    ]);
    await mountApp(
      tester,
      auth: FakeAuthRepository(authenticated: true),
      roles: [UserRole.admin],
      management: management,
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(RiexportApp)),
    );
    container
        .read(appRouterProvider)
        .go(
          AppRoutes.administration,
        ); // Abre el panel con una sesión autorizada.
    await tester.pumpAndSettle(); // Espera los usuarios disponibles.
    await tester.tap(
      find.byTooltip('Editar roles de Persona de prueba'),
    ); // Abre la edición del usuario seleccionado.
    await tester.pumpAndSettle(); // Espera el formulario de roles.
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'Nombre actualizado',
    ); // Comprueba que el administrador puede corregir datos además de roles.
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'updated@example.com',
    );
    tester.testTextInput
        .hide(); // Cierra el teclado antes de desplazar las opciones del diálogo.
    await tester
        .pumpAndSettle(); // Espera a que termine el ajuste del área visible.
    await tester.ensureVisible(
      find.widgetWithText(CheckboxListTile, 'Cliente'),
    );
    await tester.tap(
      find.widgetWithText(CheckboxListTile, 'Cliente'),
    ); // Retira la responsabilidad anterior.
    await tester.pump(); // Actualiza la selección antes de modificar otro rol.
    await tester.ensureVisible(
      find.widgetWithText(CheckboxListTile, 'Asociado'),
    ); // Mantiene visible el siguiente rol después del desplazamiento del formulario.
    await tester.tap(
      find.widgetWithText(CheckboxListTile, 'Asociado'),
    ); // Añade acceso a convenios.
    await tester.pump(); // Conserva la selección múltiple entre interacciones.
    await tester.ensureVisible(
      find.widgetWithText(CheckboxListTile, 'Trabajador'),
    ); // Desplaza el nuevo formulario de edición de datos hasta el último rol.
    await tester.tap(
      find.widgetWithText(CheckboxListTile, 'Trabajador'),
    ); // Añade acceso a operaciones.
    await tester.pump(); // Presenta el estado que se enviará al guardar.
    await tester.tap(
      find.widgetWithText(FilledButton, 'Guardar'),
    ); // Confirma la selección múltiple.
    await tester
        .pumpAndSettle(); // Espera el guardado y la actualización de la lista.
    expect(
      management.updatedUserId,
      'target-user',
    ); // Modifica solamente la cuenta seleccionada.
    expect(management.updatedName, 'Nombre actualizado');
    expect(
      management.updatedEmail,
      'updated@example.com',
    ); // Confirma que la interfaz envía el correo actualizado a la función del servidor.
    expect(
      management.updatedRoles,
      containsAll([UserRole.associate, UserRole.worker]),
    );
    expect(
      management.updatedRoles,
      isNot(contains(UserRole.client)),
    ); // Conserva la retirada del rol anterior.
  });

  testWidgets(
    'La creación administrativa conserva la sesión actual y envía los roles elegidos',
    (tester) async {
      final auth = FakeAuthRepository(
        authenticated: true,
      ); // Conserva una sesión administrativa vigente.
      final management = FakeUserManagementRepository(
        [],
      ); // Registra las creaciones solicitadas por la interfaz.
      await mountApp(
        tester,
        auth: auth,
        roles: [UserRole.admin],
        management: management,
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(RiexportApp)),
      );
      container.read(appRouterProvider).go(AppRoutes.administration);
      await tester.pumpAndSettle(); // Espera la consulta de usuarios.
      await tester.tap(find.widgetWithText(FilledButton, 'Crear usuario'));
      await tester.pumpAndSettle(); // Espera el formulario administrativo.
      await fillRegistration(
        tester,
      ); // Completa los datos compartidos de la cuenta.
      await tester.ensureVisible(
        find.widgetWithText(CheckboxListTile, 'Administrador'),
      );
      await tester.tap(
        find.widgetWithText(CheckboxListTile, 'Administrador'),
      ); // Añade el permiso elegido por el administrador.
      await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
      await tester.pumpAndSettle(); // Espera la confirmación del guardado.
      expect(management.createdUsers, 1); // Solicita una sola cuenta nueva.
      expect(
        management.createdRoles,
        contains(UserRole.admin),
      ); // Conserva la asignación administrativa.
      expect(
        auth.currentUserId,
        'current-user',
      ); // La cuenta creada nunca reemplaza la sesión del administrador.
      expect(
        auth.signUpCalls,
        0,
      ); // La administración utiliza el servicio de servidor en lugar del registro público.
    },
  );
}
