import 'dart:async'; // Limita la espera de las consultas del perfil.

import 'package:supabase_flutter/supabase_flutter.dart'; // Consulta el perfil con los permisos de la sesión actual.

import '../../../../core/errors/app_exception.dart'; // Reutiliza las entidades o servicios de app_exception.
import '../../domain/entities/user_profile.dart'; // Reutiliza las entidades o servicios de user_profile.
import '../../domain/entities/user_role.dart'; // Define el acceso básico de las cuentas nuevas.
import '../../domain/repositories/profile_repository.dart'; // Reutiliza las entidades o servicios de profile_repository.

/// Carga los datos personales sin depender de una relación de tablas todavía no desplegada.
class SupabaseProfileRepository implements ProfileRepository {
  const SupabaseProfileRepository(
    this._client, {
    this.requestTimeout = const Duration(
      seconds: 10,
    ), // Impide mantener indefinidamente el indicador de carga.
  });

  final SupabaseClient
  _client; // Conserva la identidad utilizada para aplicar las políticas de Supabase.
  final Duration
  requestTimeout; // Limita la carga completa del perfil y sus permisos.

  /// Carga el perfil solicitado y sus permisos actuales con un límite de espera.
  @override
  Future<UserProfile?> findById(String userId) async {
    try {
      return await _loadProfile(userId).timeout(
        requestTimeout,
      ); // Acota tanto la consulta del perfil como la de roles.
    } on TimeoutException {
      throw const AppException(
        'La conexión tardó demasiado. Verifica tu conexión e intenta nuevamente.',
      );
    } on PostgrestException catch (error) {
      if (error.code == '42501') {
        throw const AppException(
          'No fue posible consultar tu perfil. Contacta al administrador para revisar tu acceso.',
        );
      }
      throw const AppException(
        'No fue posible cargar la información de tu perfil. Intenta nuevamente.',
      );
    } catch (_) {
      throw const AppException(
        'No fue posible cargar la información de tu perfil.',
      );
    }
  }

  /// Consulta primero el perfil para que la ausencia de roles no descarte los datos personales.
  Future<UserProfile?> _loadProfile(String userId) async {
    if (_client.auth.currentUser?.id == userId) {
      try {
        await _client.rpc(
          'refresh_my_agreement_status',
        ); // Persiste un vencimiento y retira asociación antes de consultar los roles propios.
      } on PostgrestException catch (error) {
        if (!['PGRST202', '42883'].contains(error.code)) {
          rethrow; // Mantiene compatibilidad durante el despliegue de la nueva migración.
        }
      }
    }
    final data = await _client
        .from(
          'profiles',
        ) // Utiliza la tabla que ya existe en el proyecto remoto.
        .select() // Incluye el estado de acceso sin exigir columnas de una migración todavía no aplicada.
        .eq('id', userId) // Limita la consulta al perfil solicitado.
        .maybeSingle(); // Representa un perfil pendiente de creación mediante un valor nulo.

    if (data == null) {
      return _profileFromSession(
        userId,
      ); // Permite abrir el panel propio antes de que exista su perfil.
    }
    final roles = await _loadRoles(
      userId,
    ); // Consulta los permisos mediante una petición independiente.
    return UserProfile.fromMap({
      ...data,
      'roles': roles,
    }); // Combina datos personales y permisos sin modificar el servidor.
  }

  /// Conserva los roles del servidor y solo aplica cliente cuando todavía no existe su tabla.
  Future<List<Map<String, dynamic>>> _loadRoles(String userId) async {
    try {
      return await _client
          .from('user_roles')
          .select('role')
          .eq(
            'user_id',
            userId,
          ); // Respeta las políticas de acceso a los permisos.
    } on PostgrestException catch (error) {
      if (error.code == 'PGRST205' || error.code == '42P01') {
        return [
          {'role': UserRole.client.value},
        ]; // Mantiene únicamente la navegación de cliente durante la configuración inicial.
      }
      rethrow; // No interpreta errores de permisos o conexión como una asignación de roles válida.
    }
  }

  /// Recupera datos de la sesión únicamente para el titular que acaba de autenticarse.
  UserProfile? _profileFromSession(String userId) {
    final user = _client
        .auth
        .currentUser; // Obtiene la identidad autenticada por Supabase.
    if (user == null || user.id != userId) {
      return null; // Nunca fabrica perfiles de otras cuentas.
    }
    final name = user
        .userMetadata?['full_name']; // Lee solamente el nombre de los metadatos, nunca permisos.
    final createdAt = DateTime.parse(
      user.createdAt,
    ); // Conserva la fecha real de creación de la cuenta.
    return UserProfile(
      id: user.id, // Mantiene el identificador de la sesión actual.
      fullName: name is String && name.trim().isNotEmpty
          ? name.trim()
          : 'Usuario', // Presenta un nombre válido mientras se crea el perfil.
      email: user.email ?? '', // Conserva el correo de la cuenta autenticada.
      createdAt: createdAt, // Evita inventar una nueva fecha para el usuario.
      updatedAt:
          DateTime.tryParse(user.updatedAt ?? '') ??
          createdAt, // Admite cuentas sin una actualización previa.
      roles: const [
        UserRole.client,
      ], // No concede administración ni utiliza roles enviados en metadatos.
    );
  }
}
