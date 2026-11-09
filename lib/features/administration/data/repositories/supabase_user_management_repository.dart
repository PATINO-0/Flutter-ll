import 'package:supabase_flutter/supabase_flutter.dart'; // Ejecuta consultas autenticadas al servidor.

import '../../../../core/errors/app_exception.dart'; // Expone errores comprensibles a la interfaz.
import '../../../auth/domain/entities/user_profile.dart'; // Convierte los perfiles recibidos.
import '../../../auth/domain/entities/user_role.dart'; // Serializa los roles permitidos.
import '../../domain/repositories/user_management_repository.dart'; // Implementa el contrato del módulo.

/// Delega las operaciones privilegiadas a las funciones seguras de Supabase.
class SupabaseUserManagementRepository implements UserManagementRepository {
  const SupabaseUserManagementRepository(this._client);

  final SupabaseClient
  _client; // Utiliza la sesión actual, nunca una clave administrativa.
  static const pageSize = 20; // Limita los perfiles cargados en cada consulta.

  /// Actualiza identidad y roles mediante el servicio administrativo sin cambiar la sesión solicitante.
  @override
  Future<void> updateUser({
    required String userId,
    required String fullName,
    required String email,
    required List<UserRole> roles,
  }) => _manageUser({
    'action': 'update',
    'userId': userId,
    'fullName': fullName.trim(),
    'email': email.trim().toLowerCase(),
    'roles': roles.map((role) => role.value).toList(),
  }); // Mantiene sincronizados Supabase Auth y el perfil.

  /// Retira el acceso y conserva los documentos e historial de la cuenta.
  @override
  Future<void> deactivateUser(String userId) =>
      _manageUser({'action': 'deactivate', 'userId': userId}); // Revoca el acceso mediante una función exclusivamente administrativa.

  /// Envía una operación administrativa y distingue rechazos del servidor de fallos de transporte.
  Future<void> _manageUser(Map<String, dynamic> body) async {
    try {
      await _client.functions.invoke('manage-user', body: body);
    } on FunctionException catch (error) {
      throw AppException(
        _functionMessage(error),
      ); // Distingue una función ausente de un rechazo de permisos o datos.
    } catch (_) {
      throw const AppException(
        'No se pudo contactar al servicio de administración. Verifica la conexión y que su configuración esté completa.',
      );
    }
  }

  @override
  Future<List<UserProfile>> listUsers({required int page}) async {
    try {
      final data = await _client.rpc(
        'list_users',
        params: {
          'page_offset':
              page * pageSize, // Consulta la posición de la página solicitada.
          'page_size': pageSize, // Mantiene acotado el volumen de datos.
        },
      );
      return (data as List)
          .map(
            (row) => UserProfile.fromMap(Map<String, dynamic>.from(row as Map)),
          )
          .toList();
    } on PostgrestException catch (error) {
      throw AppException(
        _databaseMessage(error),
      ); // Traduce las restricciones del servidor.
    } catch (_) {
      throw const AppException(
        'No fue posible cargar los usuarios. Verifica tu conexión.',
      );
    }
  }

  /// Sustituye la selección de roles preservando las restricciones administrativas del servidor.
  @override
  Future<void> updateRoles({
    required String userId,
    required List<UserRole> roles,
  }) async {
    try {
      await _client.rpc(
        'set_user_roles',
        params: {
          'target_user_id': userId, // Identifica la cuenta que se modificará.
          'new_roles': roles
              .map((role) => role.value)
              .toList(), // Envía únicamente identificadores válidos.
        },
      );
    } on PostgrestException catch (error) {
      throw AppException(
        _databaseMessage(error),
      ); // Conserva los avisos de permisos y del último administrador.
    } catch (_) {
      throw const AppException(
        'No fue posible guardar los roles. Intenta nuevamente.',
      );
    }
  }

  /// Solicita la creación de una cuenta y sus roles sin sustituir la sesión del administrador.
  @override
  Future<void> createUser({
    required String fullName,
    required String email,
    required String password,
    required List<UserRole> roles,
  }) async {
    try {
      await _client.functions.invoke(
        'create-user',
        body: {
          'fullName': fullName.trim(), // Normaliza el nombre del perfil.
          'email': email
              .trim()
              .toLowerCase(), // Normaliza el identificador de acceso.
          'password':
              password, // Envía la contraseña solo al servicio de creación.
          'roles': roles
              .map((role) => role.value)
              .toList(), // Solicita los permisos elegidos.
        },
      );
    } on FunctionException catch (error) {
      throw AppException(
        _functionMessage(error),
      ); // Mantiene el mismo diagnóstico para crear, editar y retirar acceso.
    } catch (_) {
      throw const AppException(
        'No se pudo contactar al servicio de administración. Verifica la conexión y que su configuración esté completa.',
      );
    }
  }

  /// Conserva los mensajes del servidor y traduce los fallos del servicio que antes se mostraban como un error genérico.
  String _functionMessage(FunctionException error) {
    final details = error.details;
    if (details is Map && details['error'] is String) {
      return details['error']
          as String; // Conserva, por ejemplo, la protección del último administrador.
    }
    if (error.status == 0) {
      return 'No se pudo contactar al servicio de administración. Verifica la conexión y que su configuración esté completa.'; // El navegador no permite distinguir un bloqueo de CORS de otros fallos de transporte.
    }
    if (error.status == 404) {
      return 'El servicio de administración de usuarios no está configurado. Completa su instalación e intenta nuevamente.';
    }
    if (error.status == 401) {
      return 'Tu sesión no es válida. Vuelve a iniciar sesión.';
    }
    if (error.status == 403) {
      return 'Necesitas permisos de administrador para realizar esta acción.';
    }
    return 'El servicio de administración no está disponible. Intenta nuevamente.';
  }

  /// Traduce códigos conocidos sin mostrar detalles internos de la base de datos.
  String _databaseMessage(PostgrestException error) {
    switch (error.code) {
      case '42501':
        return 'Necesitas el rol de administrador para realizar esta acción.';
      case '23514':
        return 'Debe permanecer al menos un administrador en Ritech.';
      case '22023':
        return 'La selección contiene un rol no permitido.';
      case 'P0002':
        return 'El usuario ya no está disponible. Actualiza la lista.';
      default:
        return 'No fue posible completar la operación. Intenta nuevamente.';
    }
  }
}
