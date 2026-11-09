import 'dart:convert'; // Comprueba el contenido enviado a las funciones administrativas.
import 'package:flutter_test/flutter_test.dart'; // Ejecuta regresiones sobre el repositorio real.
import 'package:http/http.dart'
    as http; // Representa respuestas y fallos de red controlados.
import 'package:http/testing.dart'; // Sustituye la red sin modificar usuarios reales.
import 'package:supabase_flutter/supabase_flutter.dart'; // Utiliza el mismo cliente que la aplicación.
import 'package:riexport_ue/core/errors/app_exception.dart'; // Verifica mensajes comprensibles para administración.
import 'package:riexport_ue/features/auth/domain/entities/user_role.dart'; // Comprueba la selección de varios roles.
import 'package:riexport_ue/features/administration/data/repositories/supabase_user_management_repository.dart'; // Ejecuta las operaciones de producción con transporte simulado.

/// Crea un cliente aislado con la respuesta HTTP del escenario.
SupabaseUserManagementRepository repositoryFor(
  Future<http.Response> Function(http.Request) handler,
) {
  final client = SupabaseClient(
    'https://test.supabase.co',
    'test-key',
    httpClient: MockClient(handler),
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
  addTearDown(
    client.dispose,
  ); // Libera los recursos de autenticación de cada caso.
  return SupabaseUserManagementRepository(client);
}

/// Mantiene iguales los datos ficticios mientras cambia la respuesta del servidor.
Future<void> updateUser(SupabaseUserManagementRepository repository) =>
    repository.updateUser(
      userId: '00000000-0000-0000-0000-000000000002',
      fullName: 'Nombre de prueba',
      email: 'user@example.com',
      roles: [UserRole.client, UserRole.worker, UserRole.transporter],
    );

void main() {
  test(
    'La edición envía nombre, correo y todos los roles a manage-user',
    () async {
      final repository = repositoryFor((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/functions/v1/manage-user');
        final body = jsonDecode(request.body) as Map;
        expect(body['action'], 'update');
        expect(body['roles'], ['client', 'worker', 'transporter']);
        expect(body['fullName'], 'Nombre de prueba');
        expect(body['email'], 'user@example.com');
        return http.Response(
          '{"id":"updated"}',
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      await updateUser(repository);
    },
  );

  test(
    'Una función de edición sin desplegar explica que falta configurar el servicio',
    () async {
      final repository = repositoryFor(
        (_) async => http.Response(
          '{"code":"NOT_FOUND","message":"Requested function was not found"}',
          404,
          headers: {'content-type': 'application/json'},
        ),
      );
      await expectLater(
        updateUser(repository),
        throwsA(
          isA<AppException>().having(
            (error) => error.userMessage,
            'mensaje',
            contains('no está configurado'),
          ),
        ),
      );
    },
  );

  test(
    'Una función de creación sin desplegar conserva el mismo diagnóstico',
    () async {
      final repository = repositoryFor(
        (_) async => http.Response(
          '{"code":"NOT_FOUND","message":"Requested function was not found"}',
          404,
          headers: {'content-type': 'application/json'},
        ),
      );
      await expectLater(
        repository.createUser(
          fullName: 'Nombre de prueba',
          email: 'user@example.com',
          password: 'test-password',
          roles: [UserRole.worker],
        ),
        throwsA(
          isA<AppException>().having(
            (error) => error.userMessage,
            'mensaje',
            contains('no está configurado'),
          ),
        ),
      );
    },
  );

  test(
    'El rechazo de permisos conserva el mensaje específico del servidor',
    () async {
      final repository = repositoryFor(
        (_) async => http.Response(
          jsonEncode({
            'error': 'Debe permanecer al menos un administrador activo.',
          }),
          409,
          headers: {'content-type': 'application/json'},
        ),
      );
      await expectLater(
        updateUser(repository),
        throwsA(
          isA<AppException>().having(
            (error) => error.userMessage,
            'mensaje',
            'Debe permanecer al menos un administrador activo.',
          ),
        ),
      );
    },
  );

  test(
    'Un bloqueo de red o CORS informa del servicio inaccesible sin confirmar cambios',
    () async {
      final repository = repositoryFor(
        (_) async => throw http.ClientException('Failed to fetch'),
      );
      await expectLater(
        updateUser(repository),
        throwsA(
          isA<AppException>().having(
            (error) => error.userMessage,
            'mensaje',
            contains('No se pudo contactar al servicio de administración'),
          ),
        ),
      );
    },
  );
}
