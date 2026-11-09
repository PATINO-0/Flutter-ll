import 'dart:typed_data'; // Recibe archivos sin depender de rutas locales de cada plataforma.
import '../../../auth/domain/entities/user_profile.dart'; // Identifica a los clientes gestionados por el personal.
import '../entities/commerce_models.dart'; // Comparte las entidades del flujo comercial.

/// Define el catálogo, los convenios y la atención sin exponer detalles de Supabase a las pantallas.
abstract class CommerceRepository {
  Future<List<FreightRate>> listRates(); // Consulta el catálogo de fletes.
  Future<void> saveRate(
    Map<String, dynamic> data,
  ); // Actualiza precios con permisos administrativos.
  Future<List<UserProfile>>
  listCustomers(); // Consulta clientes y asociados para el personal.
  Future<List<AssociationRequest>>
  listRequests(); // Consulta solamente expedientes autorizados.
  /// Consulta el expediente autorizado junto con documentos y estado del convenio.
  Future<AssociationRequest> getRequest(
    String id,
  ); // Recupera un formulario y sus soportes.
  /// Abre o recupera un borrador después de verificar que no haya otra vinculación abierta.
  Future<AssociationRequest> startRequest(
    String ownerId,
  ); // Recupera un borrador o valida la apertura de otro intento.
  /// Carga un soporte privado y registra solamente una referencia válida del borrador.
  Future<void> attachDocument(
    AssociationRequest request,
    AgreementDocumentKind kind,
    String name,
    Uint8List bytes,
  ); // Carga y registra un soporte privado.
  /// Remite el expediente y registra consentimiento, vigencia propuesta y notificación.
  Future<String> submitRequest(
    AssociationRequest request, {
    required String fullName,
    required String identityNumber,
    required String phone,
    required String address,
    required String business,
    required bool consent,
    DateTime?
    validUntil, // Permite al personal fijar la vigencia de la propuesta.
  }); // Confirma y notifica la solicitud.
  /// Aprueba la documentación o devuelve correcciones sin suplantar la aceptación del titular.
  Future<void> reviewRequest(
    String id, {
    required bool approve,
    String reason = '',
    DateTime? validUntil,
  }); // Aprueba o devuelve el expediente y notifica al cliente.
  Future<List<Agreement>>
  listAgreements(); // Consulta convenios y documentos aceptados.
  /// Registra la aceptación o rechazo únicamente desde la sesión del titular.
  Future<void> respondToAgreement(
    String id, {
    required bool accept,
    required bool acceptedTerms,
    String reason = '',
  }); // Exige la respuesta expresa del titular.
  /// Cierra el convenio con motivo, conserva su historial y notifica al titular.
  Future<void> revokeAgreement(
    String id,
    String reason,
  ); // Conserva el expediente y notifica el motivo de cierre.
  /// Solicita un enlace privado de un minuto y lo abre en el visor autorizado del dispositivo.
  Future<void> openDocument(
    String path,
  ); // Abre una descarga autorizada de corta duración.
  Future<List<SupportConversation>>
  listConversations(); // Carga las conversaciones y sus mensajes sin leer.
  /// Abre el canal de atención propio o el de un cliente autorizado para el personal.
  Future<String> openConversation(
    String ownerId,
  ); // Abre el canal de atención de un cliente.
  /// Recupera el tramo solicitado del historial respetando el acceso a la conversación.
  Future<List<SupportMessage>> listMessages(
    String conversationId, {
    int limit = 100,
  }); // Recupera el tramo reciente del historial.
  /// Envía texto humano al canal autorizado sin permitir fabricar notificaciones del sistema.
  Future<void> sendMessage(
    String conversationId,
    String body,
  ); // Envía un mensaje humano validado por el servidor.
  /// Confirma el último mensaje consultado y actualiza el contador de la conversación.
  Future<void> markRead(
    String conversationId,
    String lastMessageId,
  ); // Actualiza las notificaciones vistas.
}
