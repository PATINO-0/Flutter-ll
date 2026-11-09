import 'dart:async'; // Simula una consulta que no responde para comprobar el tiempo de espera.
import 'dart:convert'; // Construye las respuestas simuladas de Supabase.

import 'package:flutter/material.dart'; // Localiza el dashboard y sus indicadores de carga.
import 'package:flutter_riverpod/flutter_riverpod.dart'; // Sustituye únicamente las dependencias externas.
import 'package:flutter_test/flutter_test.dart'; // Ejecuta las pruebas de regresión del perfil.
import 'package:http/http.dart'
    as http; // Representa las respuestas HTTP simuladas.
import 'package:http/testing.dart'; // Evita contactar al proyecto real durante las pruebas.
import 'package:supabase_flutter/supabase_flutter.dart'; // Ejecuta las consultas del cliente oficial.

import 'package:riexport_ue/app.dart'; // Comprueba la navegación real de la aplicación.
import 'package:riexport_ue/core/errors/app_exception.dart'; // Comprueba los errores traducidos para el usuario.
import 'package:riexport_ue/features/auth/data/repositories/supabase_profile_repository.dart'; // Prueba el repositorio utilizado en producción.
import 'package:riexport_ue/features/auth/domain/entities/user_role.dart'; // Verifica los permisos resultantes.
import 'package:riexport_ue/features/auth/presentation/providers/auth_providers.dart'; // Conecta el repositorio real con la pantalla.

import 'support/fake_repositories.dart'; // Simula una sesión de usuario válida.
import 'package:riexport_ue/features/commerce/presentation/providers/commerce_providers.dart'; // Aísla las consultas del catálogo mientras se prueba el perfil real.

/// Devuelve el perfil previo a la migración, sin incluir una relación de roles.
Map<String, dynamic> profileData() => {
  'id': 'current-user', // Corresponde a la sesión simulada.
  'full_name':
      'Cliente nuevo', // Identifica el perfil mostrado en el dashboard.
  'email': 'client@example.com', // Utiliza un dominio reservado para pruebas.
  'created_at':
      '2026-11-08T00:00:00Z', // Mantiene reproducible la fecha del registro.
  'updated_at':
      '2026-11-08T00:00:00Z', // Representa el formato almacenado por Supabase.
};

/// Reproduce la respuesta real de Supabase cuando todavía no existe la tabla de roles.
SupabaseClient createLegacyClient({
  String? roleErrorCode =
      'PGRST205', // Reproduce por defecto la tabla ausente del proyecto real.
  List<String> roles = const [
    'client',
  ], // Permite comprobar también los roles ya configurados.
  bool missingProfile = false, // Simula una cuenta que todavía no tiene perfil.
  bool missingUpdatedAt =
      false, // Reproduce perfiles antiguos sin fecha de actualización.
  bool profileNeverResponds =
      false, // Simula la petición que mantendría la pantalla cargando.
}) {
  final httpClient = MockClient((request) async {
    if (request.url.path.endsWith('/profiles') &&
        !request.url.query.contains('user_roles')) {
      if (profileNeverResponds) {
        return Completer<http.Response>()
            .future; // No completa la petición para comprobar el límite de espera.
      }
      final data =
          profileData(); // Conserva los mismos campos que devuelve el backend.
      if (missingUpdatedAt) {
        data['updated_at'] =
            null; // Admite cuentas que nunca actualizaron su perfil.
      }
      return http.Response(
        jsonEncode(
          missingProfile ? [] : [data],
        ), // Reproduce la respuesta real de una consulta GET antes de maybeSingle.
        200,
        request:
            request, // Conserva la petición que utiliza el cliente oficial para interpretar la respuesta.
        headers: {'content-type': 'application/json'},
      );
    }
    if (request.url.path.endsWith('/user_roles') && roleErrorCode == null) {
      return http.Response(
        jsonEncode(
          roles.map((role) => {'role': role}).toList(),
        ), // Conserva exactamente los permisos del servidor, incluso una lista vacía.
        200,
        request:
            request, // Mantiene la petición requerida por el cliente de PostgREST.
        headers: {
          'content-type': 'application/json',
        }, // Identifica la respuesta como datos JSON.
      );
    }
    return http.Response(
      jsonEncode({
        'code': request.url.path.endsWith('/user_roles')
            ? roleErrorCode
            : 'PGRST200',
        'message': 'Could not find user_roles in the schema cache',
      }),
      404,
      request:
          request, // Permite que PostgREST interprete el código real del error de esquema.
      headers: {'content-type': 'application/json'},
    ); // Reproduce el fallo que impedía cargar el perfil completo.
  });
  return SupabaseClient(
    'https://test.supabase.co', // Impide utilizar la configuración del proyecto real.
    'test-key', // Utiliza una clave ficticia sin permisos.
    httpClient:
        httpClient, // Atiende todas las solicitudes dentro de la prueba.
    authOptions: const AuthClientOptions(
      autoRefreshToken: false,
    ), // No inicia tareas periódicas de autenticación.
  );
}

void main() {
  test(
    'Los roles administrativos del servidor se conservan sin sustituirlos por cliente',
    () async {
      final client = createLegacyClient(
        roleErrorCode: null,
        roles: ['admin', 'client'],
      ); // Reproduce la cuenta de prueba después de la migración.
      addTearDown(client.dispose); // Libera el cliente del escenario.
      final profile = await SupabaseProfileRepository(
        client,
      ).findById('current-user');
      expect(
        profile?.isAdmin,
        isTrue,
      ); // Conserva el acceso al panel administrativo.
      expect(
        profile?.roles,
        containsAll([UserRole.admin, UserRole.client]),
      ); // Conserva todos los roles verificados.
    },
  );

  test(
    'Una cuenta sin roles no recupera automáticamente un rol que el administrador retiró',
    () async {
      final client = createLegacyClient(
        roleErrorCode: null,
        roles: [],
      ); // Reproduce una revocación explícita de permisos.
      addTearDown(client.dispose); // Libera el cliente del escenario.
      final profile = await SupabaseProfileRepository(
        client,
      ).findById('current-user');
      expect(
        profile?.roles,
        isEmpty,
      ); // No interpreta una lista vacía como una migración pendiente.
      expect(
        profile?.isAdmin,
        isFalse,
      ); // No concede permisos administrativos por defecto.
    },
  );

  test(
    'Los errores de permisos no se convierten silenciosamente en acceso de cliente',
    () async {
      final client = createLegacyClient(
        roleErrorCode: '42501',
      ); // Simula una política que impide consultar los roles.
      addTearDown(
        client.dispose,
      ); // Libera el cliente después de comprobar el rechazo.
      await expectLater(
        SupabaseProfileRepository(client).findById('current-user'),
        throwsA(isA<AppException>()),
      );
    },
  );

  test(
    'Los perfiles sin updated_at utilizan su fecha de creación y abren correctamente',
    () async {
      final client = createLegacyClient(
        missingUpdatedAt: true,
      ); // Reproduce un registro sin actualizaciones previas.
      addTearDown(client.dispose); // Libera el cliente del escenario.
      final profile = await SupabaseProfileRepository(
        client,
      ).findById('current-user');
      expect(
        profile?.updatedAt,
        profile?.createdAt,
      ); // Evita errores de conversión con fechas nulas.
    },
  );

  test(
    'Una consulta que no responde termina con un error recuperable dentro del plazo configurado',
    () async {
      final client = createLegacyClient(
        profileNeverResponds: true,
      ); // Reproduce una petición que permanece pendiente.
      addTearDown(
        client.dispose,
      ); // Libera los recursos aunque la petición no haya respondido.
      final repository = SupabaseProfileRepository(
        client,
        requestTimeout: const Duration(milliseconds: 30),
      ); // Acorta solo el plazo de la prueba.
      await expectLater(
        repository.findById('current-user'),
        throwsA(
          isA<AppException>().having(
            (error) => error.userMessage,
            'mensaje',
            contains('tardó demasiado'),
          ),
        ),
      );
    },
  );

  test(
    'Una cuenta recién autenticada sin perfil accede como cliente e ignora roles de sus metadatos',
    () async {
      final client = createLegacyClient(
        missingProfile: true,
      ); // Reproduce un perfil que no creó el disparador antiguo.
      addTearDown(client.dispose); // Libera la sesión de prueba al terminar.
      await client.auth.setInitialSession(
        jsonEncode({
          'access_token': 'test-access-token',
          'token_type':
              'bearer', // Carga una sesión local sin hacer peticiones de autenticación.
          'user': {
            'id': 'current-user',
            'email': 'client@example.com',
            'created_at': '2026-11-08T00:00:00Z',
            'user_metadata': {
              'full_name': 'Cliente nuevo',
              'role': 'admin',
              'roles': ['admin'],
            }, // Intenta inyectar permisos mediante datos editables.
          },
        }),
      );
      final repository = SupabaseProfileRepository(
        client,
      ); // Utiliza el repositorio real con esa sesión.
      final profile = await repository.findById(
        'current-user',
      ); // Recupera los datos propios de autenticación.
      expect(
        profile?.fullName,
        'Cliente nuevo',
      ); // Permite mostrar la bienvenida sin esperar un perfil inexistente.
      expect(profile?.roles, [
        UserRole.client,
      ]); // Ignora los permisos que llegaron en metadatos.
      expect(
        await repository.findById('another-user'),
        isNull,
      ); // Nunca fabrica un perfil para otra identidad.
    },
  );

  test(
    'Un perfil existente se carga como cliente cuando Supabase todavía no tiene user_roles',
    () async {
      final client =
          createLegacyClient(); // Reproduce el esquema anterior confirmado en el proyecto remoto.
      addTearDown(
        client.dispose,
      ); // Libera los recursos del cliente de Supabase.
      final profile = await SupabaseProfileRepository(
        client,
      ).findById('current-user');
      expect(
        profile?.fullName,
        'Cliente nuevo',
      ); // Conserva los datos existentes del perfil.
      expect(profile?.roles, [
        UserRole.client,
      ]); // Concede únicamente la navegación básica de cliente.
      expect(
        profile?.isAdmin,
        isFalse,
      ); // No convierte la ausencia de configuración en permisos elevados.
    },
  );

  testWidgets(
    'El inicio de sesión después del registro abre el dashboard aunque todavía falte la tabla de roles',
    (tester) async {
      final client = (await tester.runAsync(
        () async => createLegacyClient(),
      ))!; // Inicializa los recursos del SDK fuera del reloj simulado de Flutter.
      final auth =
          FakeAuthRepository(); // Empieza sin sesión para recorrer el acceso posterior al registro.
      addTearDown(
        () => tester.runAsync(client.dispose),
      ); // Libera los recursos del cliente fuera del reloj simulado de la interfaz.
      addTearDown(
        auth.events.close,
      ); // Libera las notificaciones de autenticación.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            commerceRepositoryProvider.overrideWithValue(
              FakeCommerceRepository(),
            ), // Conserva la prueba sin conexión al catálogo remoto.
            authRepositoryProvider.overrideWithValue(
              auth,
            ), // Mantiene una sesión autenticada controlada.
            profileRepositoryProvider.overrideWithValue(
              SupabaseProfileRepository(client),
            ), // Conserva el repositorio de producción en la prueba.
          ],
          child:
              const RiexportApp(), // Ejecuta el dashboard y su proveedor reales.
        ),
      );
      await tester
          .pumpAndSettle(); // Espera a que terminen las consultas y redirecciones.
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'client@example.com',
      ); // Ingresa el correo del cliente recién registrado.
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'password123',
      ); // Completa su contraseña de prueba.
      await tester.tap(
        find.widgetWithText(FilledButton, 'Iniciar sesión'),
      ); // Recorre el inicio de sesión real de la interfaz.
      await tester
          .pumpAndSettle(); // Espera la carga del perfil y el cambio al dashboard.
      expect(
        find.text('Bienvenido, Cliente nuevo'),
        findsOneWidget,
      ); // El registro ya puede continuar al dashboard.
      expect(
        find.text('Quiero convertirme en asociado exportador'),
        findsOneWidget,
      ); // Presenta el rol básico del usuario nuevo.
      expect(
        find.byType(CircularProgressIndicator),
        findsNothing,
      ); // No conserva la pantalla de carga.
      expect(
        find.textContaining('No fue posible cargar tu perfil'),
        findsNothing,
      ); // Evita el error provocado por la tabla ausente.
    },
  );
}
