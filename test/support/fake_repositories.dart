import 'dart:async'; // Simula cambios de sesión sin acceder a la red.
import 'dart:typed_data'; // Representa documentos de prueba sin acceder al dispositivo.
import 'package:riexport_ue/features/commerce/domain/entities/commerce_models.dart'; // Simula los datos del nuevo flujo comercial.
import 'package:riexport_ue/features/commerce/domain/repositories/commerce_repository.dart'; // Sustituye las consultas reales del catálogo y la atención.

import 'package:riexport_ue/core/errors/app_exception.dart'; // Permite reproducir errores controlados.
import 'package:riexport_ue/features/administration/domain/repositories/user_management_repository.dart'; // Simula las acciones administrativas.
import 'package:riexport_ue/features/auth/domain/entities/auth_session_event.dart'; // Representa los cambios de autenticación.
import 'package:riexport_ue/features/auth/domain/entities/user_profile.dart'; // Define los perfiles de prueba.
import 'package:riexport_ue/features/auth/domain/entities/user_role.dart'; // Define los permisos probados.
import 'package:riexport_ue/features/auth/domain/repositories/auth_repository.dart'; // Sustituye la autenticación real.
import 'package:riexport_ue/features/auth/domain/repositories/profile_repository.dart'; // Sustituye la consulta de perfiles.

/// Reproduce el contrato de autenticación sin crear cuentas reales.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({
    this.authenticated = false,
    this.requiresConfirmation = true,
  });

  bool authenticated; // Controla si existe una sesión en el escenario.
  final bool
  requiresConfirmation; // Simula la configuración de confirmación por correo.
  int signUpCalls =
      0; // Detecta envíos duplicados o formularios inválidos enviados.
  AppException?
  signUpError; // Permite simular un fallo recuperable del registro.
  final events =
      StreamController<
        AuthSessionEvent
      >.broadcast(); // Notifica cambios al router.

  @override
  String? get currentUserId => authenticated ? 'current-user' : null;

  @override
  String? get currentUserEmail => authenticated ? 'person@example.com' : null;

  @override
  bool get hasSession => authenticated;

  @override
  Stream<AuthSessionEvent> get authStateChanges => events.stream;

  @override
  Future<bool> signUp({
    required String fullName,
    required String email,
    required String password,
  }) async {
    signUpCalls++; // Registra únicamente el número de solicitudes.
    await Future<void>.delayed(
      Duration.zero,
    ); // Reproduce la respuesta asíncrona del servidor.
    if (signUpError != null) {
      throw signUpError!; // Conserva el mismo contrato de errores del repositorio real.
    }
    if (!requiresConfirmation) {
      await signIn(
        email: email,
        password: password,
      ); // Simula el acceso automático.
    }
    return requiresConfirmation; // Indica si se necesita confirmar el correo.
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    authenticated = true; // Activa la sesión del escenario.
    events.add(
      const AuthSessionEvent(isAuthenticated: true, userId: 'current-user'),
    ); // Actualiza la navegación.
  }

  @override
  Future<void> signOut() async {
    authenticated = false; // Retira la sesión del escenario.
    events.add(
      const AuthSessionEvent(isAuthenticated: false),
    ); // Devuelve la navegación al acceso público.
  }
}

/// Devuelve el perfil configurado para probar cada responsabilidad.
class FakeProfileRepository implements ProfileRepository {
  FakeProfileRepository(this.profile);

  UserProfile?
  profile; // Permite simular también un perfil inexistente o un cambio de roles.

  @override
  Future<UserProfile?> findById(String userId) async => profile;
}

/// Registra los cambios solicitados por la interfaz administrativa.
class FakeUserManagementRepository implements UserManagementRepository {
  FakeUserManagementRepository(this.users);

  final List<UserProfile> users; // Contiene las cuentas visibles del escenario.
  String? updatedUserId; // Identifica la cuenta que recibió el último cambio.
  List<UserRole>?
  updatedRoles; // Conserva la selección enviada al servidor simulado.
  int createdUsers = 0; // Cuenta las creaciones solicitadas desde el panel.
  List<UserRole>?
  createdRoles; // Conserva los roles seleccionados durante la creación.
  String? updatedName; // Comprueba la edición de los datos personales.
  String? updatedEmail; // Comprueba la edición del correo de acceso.
  String? deactivatedUserId; // Identifica la cuenta cuyo acceso se retiró.
  @override
  Future<void> updateUser({
    required String userId,
    required String fullName,
    required String email,
    required List<UserRole> roles,
  }) async {
    updatedName = fullName;
    updatedEmail = email;
    await updateRoles(userId: userId, roles: roles);
  } // Conserva las comprobaciones previas de edición de roles.

  @override
  Future<void> deactivateUser(String userId) async {
    deactivatedUserId = userId;
  } // No modifica cuentas reales durante las pruebas.

  @override
  Future<List<UserProfile>> listUsers({required int page}) async =>
      page == 0 ? users : [];

  @override
  Future<void> updateRoles({
    required String userId,
    required List<UserRole> roles,
  }) async {
    updatedUserId = userId; // Permite comprobar el destino de la modificación.
    updatedRoles =
        roles; // Permite comprobar la asignación y retirada de roles.
  }

  @override
  Future<void> createUser({
    required String fullName,
    required String email,
    required String password,
    required List<UserRole> roles,
  }) async {
    createdUsers++; // Registra la solicitud sin almacenar la contraseña.
    createdRoles =
        roles; // Permite verificar la selección de responsabilidades.
  }
}

/// Proporciona datos controlados para recorrer catálogo, solicitud y chat sin Supabase.
class FakeCommerceRepository implements CommerceRepository {
  final List<FreightRate> rates =
      []; // Mantiene tarifas ilustrativas configurables por cada prueba.
  final List<SupportConversation> conversations =
      []; // Mantiene notificaciones propias del escenario.
  final List<SupportMessage> messages =
      []; // Mantiene un historial sin datos reales.
  final List<AssociationRequest> requests =
      []; // Conserva los expedientes creados por la prueba.
  final List<Agreement> agreements =
      []; // Conserva convenios simulados del escenario.
  int submittedCount = 0; // Comprueba que el formulario se envía una sola vez.
  bool? submittedConsent; // Comprueba que la aceptación se entrega al servidor.
  bool? reviewedApproval; // Comprueba la decisión elegida por el trabajador.
  String? reviewedReason; // Comprueba las correcciones comunicadas al cliente.
  @override
  Future<List<FreightRate>> listRates() async => rates;
  @override
  Future<void> saveRate(Map<String, dynamic> data) async {}
  @override
  Future<List<UserProfile>> listCustomers() async => [];
  @override
  Future<List<AssociationRequest>> listRequests() async => requests;
  @override
  Future<AssociationRequest> getRequest(String id) async =>
      requests.firstWhere((item) => item.id == id);
  @override
  Future<AssociationRequest> startRequest(String ownerId) async =>
      requests.first;
  @override
  Future<void> attachDocument(
    AssociationRequest request,
    AgreementDocumentKind kind,
    String name,
    Uint8List bytes,
  ) async {}
  @override
  Future<String> submitRequest(
    AssociationRequest request, {
    required String fullName,
    required String identityNumber,
    required String phone,
    required String address,
    required String business,
    required bool consent,
  }) async {
    submittedCount++;
    submittedConsent = consent;
    return 'conversation';
  }

  @override
  Future<void> reviewRequest(
    String id, {
    required bool approve,
    String reason = '',
  }) async {
    reviewedApproval = approve;
    reviewedReason = reason;
  }

  @override
  Future<List<Agreement>> listAgreements() async => agreements;
  @override
  Future<void> openDocument(String path) async {}
  @override
  Future<List<SupportConversation>> listConversations() async => conversations;
  @override
  Future<String> openConversation(String ownerId) async => 'conversation';
  @override
  Future<List<SupportMessage>> listMessages(
    String conversationId, {
    int limit = 100,
  }) async => messages;
  @override
  Future<void> sendMessage(String conversationId, String body) async {}
  @override
  Future<void> markRead(String conversationId, String lastMessageId) async {}
}

/// Construye perfiles reproducibles para pruebas de permisos e interfaz.
UserProfile buildProfile(List<UserRole> roles, {String id = 'current-user'}) {
  return UserProfile(
    id: id, // Relaciona el perfil con la sesión simulada.
    fullName: 'Persona de prueba', // Evita utilizar datos personales reales.
    email:
        'person@example.com', // Proporciona un correo reservado para pruebas.
    createdAt: DateTime.utc(
      2026,
      11,
      8,
    ), // Mantiene estable la fecha de creación.
    updatedAt: DateTime.utc(
      2026,
      11,
      8,
    ), // Mantiene estable la fecha de actualización.
    roles: roles, // Controla el escenario de autorización.
  );
}
