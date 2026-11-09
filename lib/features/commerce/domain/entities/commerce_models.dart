/// Describe una tarifa del catálogo y distingue los ejemplos de los precios comerciales.
class FreightRate {
  const FreightRate({
    required this.id,
    required this.title,
    required this.origin,
    required this.destination,
    required this.amount,
    required this.currency,
    required this.unit,
    required this.description,
    required this.isReference,
    required this.isActive,
  });
  final String id; // Identifica la tarifa que puede editar el administrador.
  final String title; // Describe el servicio de importación.
  final String origin; // Identifica el punto de origen.
  final String destination; // Identifica el destino del transporte.
  final double amount; // Conserva el importe por unidad.
  final String currency; // Expresa la moneda de la tarifa.
  final String unit; // Expresa si el importe corresponde a kilogramo o volumen.
  final String description; // Explica las condiciones del servicio.
  final bool
  isReference; // Señala los valores ilustrativos que no son cotizaciones.
  final bool isActive; // Permite retirar una tarifa de la tienda.
  factory FreightRate.fromMap(Map<String, dynamic> map) => FreightRate(
    id: map['id'],
    title: map['title'],
    origin: map['origin'],
    destination: map['destination'],
    amount: (map['amount'] as num).toDouble(),
    currency: map['currency'],
    unit: map['unit'],
    description: map['description'],
    isReference: map['is_reference'],
    isActive: map['is_active'],
  );
}

/// Define los tres soportes exigidos para tramitar el convenio.
enum AgreementDocumentKind {
  identity(
    'identity',
    'Documento de identidad',
    'Copia legible de la cédula o documento de identidad.',
  ),
  agreementLetter(
    'agreement_letter',
    'Carta de solicitud de convenio',
    'Carta firmada que describa la intención de vincularse como asociado exportador.',
  ),
  taxCertificate(
    'tax_certificate',
    'Certificado tributario',
    'RUT o certificado tributario equivalente vigente.',
  );

  const AgreementDocumentKind(this.value, this.label, this.instructions);
  final String value; // Identificador que valida el servidor.
  final String label; // Nombre del soporte en la interfaz.
  final String instructions; // Explica al cliente qué documento debe aportar.
}

/// Representa la referencia privada de un documento, sin conservar una URL pública.
class RequestDocument {
  const RequestDocument({
    required this.kind,
    required this.path,
    required this.name,
  });
  final String kind; // Identifica cuál de los tres soportes fue adjuntado.
  final String path; // Conserva la ruta protegida por políticas de Storage.
  final String name; // Presenta el nombre original al usuario autorizado.
  factory RequestDocument.fromMap(Map<String, dynamic> map) => RequestDocument(
    kind: map['kind'],
    path: map['storage_path'],
    name: map['original_name'],
  );
}

/// Conserva los datos y el resultado de un intento de vinculación comercial.
class AssociationRequest {
  const AssociationRequest({
    required this.id,
    required this.ownerId,
    required this.status,
    required this.fullName,
    required this.identityNumber,
    required this.phone,
    required this.address,
    required this.businessDescription,
    required this.documents,
    this.submittedAt,
    this.rejectionReason,
  });
  final String id; // Relaciona el formulario con sus documentos y mensajes.
  final String ownerId; // Identifica al cliente titular del expediente.
  final String status; // Distingue borrador, revisión, aprobación y rechazo.
  final String fullName; // Conserva el nombre declarado en la solicitud.
  final String identityNumber; // Conserva la identificación del solicitante.
  final String phone; // Conserva el número de contacto.
  final String address; // Conserva la dirección declarada.
  final String
  businessDescription; // Describe la actividad y la necesidad comercial.
  final List<RequestDocument>
  documents; // Contiene los soportes que el servidor permite consultar.
  final DateTime?
  submittedAt; // Permite informar del plazo antes de solicitar un nuevo convenio.
  final String?
  rejectionReason; // Presenta las correcciones solicitadas por el trabajador.
  bool get isDraft =>
      status ==
      'draft'; // Permite editar únicamente solicitudes todavía no enviadas.
  String get statusLabel => switch (status) {
    'draft' => 'Borrador',
    'pending' => 'En revisión',
    'approved' => 'Aprobada',
    'rejected' => 'Rechazada',
    _ => 'Estado desconocido',
  };
  factory AssociationRequest.fromMap(Map<String, dynamic> map) =>
      AssociationRequest(
        id: map['id'],
        ownerId: map['owner_id'],
        status: map['status'],
        fullName: map['full_name'],
        identityNumber: map['identity_number'],
        phone: map['phone'],
        address: map['address'],
        businessDescription: map['business_description'],
        submittedAt: DateTime.tryParse(map['submitted_at'] ?? ''),
        rejectionReason: map['rejection_reason'],
        documents: (map['documents'] as List? ?? [])
            .map(
              (item) =>
                  RequestDocument.fromMap(Map<String, dynamic>.from(item)),
            )
            .toList(),
      );
}

/// Presenta un convenio aprobado junto al expediente original que conserva sus soportes.
class Agreement {
  const Agreement({
    required this.id,
    required this.number,
    required this.request,
    required this.createdAt,
  });
  final String id; // Identifica el convenio persistido.
  final int number; // Presenta un consecutivo comercial legible.
  final AssociationRequest
  request; // Conserva el vínculo con documentos y datos del cliente.
  final DateTime createdAt; // Registra la formalización del convenio.
  factory Agreement.fromMap(Map<String, dynamic> map) => Agreement(
    id: map['id'],
    number: map['agreement_number'],
    request: AssociationRequest.fromMap(
      Map<String, dynamic>.from(map['request']),
    ),
    createdAt: DateTime.parse(map['created_at']),
  );
}

/// Representa una conversación de atención y sus notificaciones pendientes de lectura.
class SupportConversation {
  const SupportConversation({
    required this.id,
    required this.clientId,
    required this.clientName,
    required this.unreadCount,
  });
  final String id; // Identifica el chat al que se enviarán mensajes.
  final String clientId; // Identifica al titular de la conversación.
  final String clientName; // Permite al trabajador reconocer cada solicitud.
  final int unreadCount; // Muestra las respuestas y solicitudes nuevas.
  factory SupportConversation.fromMap(Map<String, dynamic> map) =>
      SupportConversation(
        id: map['id'],
        clientId: map['client_id'],
        clientName: map['client_name'],
        unreadCount: (map['unread_count'] as num).toInt(),
      );
}

/// Distingue las respuestas humanas de las notificaciones que genera el flujo de convenios.
class SupportMessage {
  const SupportMessage({
    required this.id,
    required this.senderId,
    required this.body,
    required this.kind,
    required this.createdAt,
    this.requestId,
  });
  final String id; // Permite registrar hasta qué mensaje se leyó el chat.
  final String
  senderId; // Identifica si el mensaje pertenece al usuario actual.
  final String body; // Contiene la consulta, respuesta o aviso de la solicitud.
  final String
  kind; // Señala los mensajes de sistema que no puede fabricar un cliente.
  final DateTime createdAt; // Ordena la conversación cronológicamente.
  final String?
  requestId; // Permite abrir el expediente mencionado por una notificación.
  factory SupportMessage.fromMap(Map<String, dynamic> map) => SupportMessage(
    id: map['id'],
    senderId: map['sender_id'],
    body: map['body'],
    kind: map['kind'],
    createdAt: DateTime.parse(map['created_at']),
    requestId: map['request_id'],
  );
}
