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
  Future<AssociationRequest> getRequest(
    String id,
  ); // Recupera un formulario y sus soportes.
  Future<AssociationRequest> startRequest(
    String ownerId,
  ); // Recupera un borrador o valida la apertura de otro intento.
  Future<void> attachDocument(
    AssociationRequest request,
    AgreementDocumentKind kind,
    String name,
    Uint8List bytes,
  ); // Carga y registra un soporte privado.
  Future<String> submitRequest(
    AssociationRequest request, {
    required String fullName,
    required String identityNumber,
    required String phone,
    required String address,
    required String business,
    required bool consent,
  }); // Confirma y notifica la solicitud.
  Future<void> reviewRequest(
    String id, {
    required bool approve,
    String reason = '',
  }); // Aprueba o devuelve el expediente y notifica al cliente.
  Future<List<Agreement>>
  listAgreements(); // Consulta convenios y documentos aceptados.
  Future<void> openDocument(
    String path,
  ); // Abre una descarga autorizada de corta duración.
  Future<List<SupportConversation>>
  listConversations(); // Carga las conversaciones y sus mensajes sin leer.
  Future<String> openConversation(
    String ownerId,
  ); // Abre el canal de atención de un cliente.
  Future<List<SupportMessage>> listMessages(
    String conversationId, {
    int limit = 100,
  }); // Recupera el tramo reciente del historial.
  Future<void> sendMessage(
    String conversationId,
    String body,
  ); // Envía un mensaje humano validado por el servidor.
  Future<void> markRead(
    String conversationId,
    String lastMessageId,
  ); // Actualiza las notificaciones vistas.
}
