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
    this.allowsCoffeeExport = false,
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
  final bool allowsCoffeeExport; // Habilita esta ruta para solicitudes de café.
  /// Habilita la selección únicamente para rutas activas de café cotizadas por kilogramo.
  bool get isCoffeeExportAvailable =>
      isActive &&
      allowsCoffeeExport &&
      unit.trim().toLowerCase() ==
          'kg'; // Excluye servicios por volumen y rutas desactivadas.
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
    allowsCoffeeExport: map['allows_coffee_export'] == true,
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
    this.agreementId,
    this.agreementStatus,
    this.agreementExpiresAt,
    this.agreementClosureReason,
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
  final String?
  agreementId; // Abre las acciones sobre la propuesta o convenio vinculado.
  final String?
  agreementStatus; // Distingue revisión documental de aceptación comercial.
  final DateTime?
  agreementExpiresAt; // Presenta la vigencia ofrecida al titular.
  final String?
  agreementClosureReason; // Conserva el motivo de revocación o rechazo.
  /// Indica si el expediente conserva permisos de edición antes de ser enviado.
  bool get isDraft =>
      status ==
      'draft'; // Permite editar únicamente solicitudes todavía no enviadas.
  /// Traduce el estado persistido a una etiqueta comprensible para el usuario.
  String get statusLabel => switch (status) {
    'draft' => 'Borrador',
    'pending' => 'En revisión',
    'approved' => 'Aprobada',
    'rejected' => 'Rechazada',
    _ => 'Estado desconocido',
  };
  factory AssociationRequest.fromMap(Map<String, dynamic> map) {
    final relation = map['agreement'];
    final agreement = relation is Map
        ? relation
        : relation is List && relation.isNotEmpty
        ? relation.first as Map
        : const {};
    return AssociationRequest(
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
      agreementId: agreement['id'],
      agreementStatus: agreement['status'],
      agreementExpiresAt: DateTime.tryParse(agreement['expires_at'] ?? ''),
      agreementClosureReason: agreement['closure_reason'],
      documents: (map['documents'] as List? ?? [])
          .map(
            (item) => RequestDocument.fromMap(Map<String, dynamic>.from(item)),
          )
          .toList(),
    );
  }
}

/// Presenta un convenio aprobado junto al expediente original que conserva sus soportes.
class Agreement {
  const Agreement({
    required this.id,
    required this.number,
    required this.request,
    required this.createdAt,
    this.status = 'active',
    this.expiresAt,
    this.closureReason,
  });
  final String id; // Identifica el convenio persistido.
  final int number; // Presenta un consecutivo comercial legible.
  final AssociationRequest
  request; // Conserva el vínculo con documentos y datos del cliente.
  final DateTime createdAt; // Registra la formalización del convenio.
  final String status; // Conserva el estado de aceptación o cierre.
  final DateTime?
  expiresAt; // Una fecha nula corresponde a un convenio histórico sin vencimiento registrado.
  final String?
  closureReason; // Explica la revocación, vencimiento o rechazo de la propuesta.
  /// Aplica el vencimiento visible aunque todavía no se haya persistido la siguiente sincronización.
  String get effectiveStatus => effectiveAgreementStatus(status, expiresAt);

  /// Bloquea nuevas propuestas mientras exista una vinculación vigente o pendiente de aceptación.
  bool get isOpen =>
      ['active', 'awaiting_acceptance'].contains(effectiveStatus);

  /// Traduce el estado persistido a una etiqueta comprensible para el usuario.
  String get statusLabel =>
      agreementStatusLabels[effectiveStatus] ?? effectiveStatus;
  factory Agreement.fromMap(Map<String, dynamic> map) => Agreement(
    id: map['id'],
    number: map['agreement_number'],
    request: AssociationRequest.fromMap(
      Map<String, dynamic>.from(map['request']),
    ),
    createdAt: DateTime.parse(map['created_at']),
    status: map['status'] ?? 'active',
    expiresAt: DateTime.tryParse(map['expires_at'] ?? ''),
    closureReason: map['closure_reason'],
  );
}

/// Mantiene legibles los estados del convenio en clientes, solicitudes y archivo.
const agreementStatusLabels = {
  'awaiting_acceptance': 'Pendiente de aceptación del titular',
  'active': 'Activo',
  'revoked': 'Revocado',
  'expired': 'Vencido',
  'declined': 'Rechazado por el titular',
};

/// La fecha visible no depende de que el siguiente sondeo haya persistido el vencimiento.
String effectiveAgreementStatus(String status, DateTime? expiration) =>
    ['active', 'awaiting_acceptance'].contains(status) &&
        expiration != null &&
        !expiration.isAfter(DateTime.now())
    ? 'expired'
    : status;

/// Representa una conversación de atención y sus notificaciones pendientes de lectura.
class SupportConversation {
  const SupportConversation({
    required this.id,
    required this.clientId,
    required this.clientName,
    required this.unreadCount,
    this.channel =
        'support', // Conserva la compatibilidad con conversaciones anteriores al flujo de envíos.
    this.exportRequestId,
  });
  final String id; // Identifica el chat al que se enviarán mensajes.
  final String clientId; // Identifica al titular de la conversación.
  final String clientName; // Permite al trabajador reconocer cada solicitud.
  final int unreadCount; // Muestra las respuestas y solicitudes nuevas.
  final String
  channel; // Separa atención general, expedientes de exportación y coordinación de transporte.
  final String?
  exportRequestId; // Identifica la exportación a la que corresponde el chat alterno.
  factory SupportConversation.fromMap(Map<String, dynamic> map) =>
      SupportConversation(
        id: map['id'],
        clientId: map['client_id'],
        clientName: map['client_name'],
        unreadCount: (map['unread_count'] as num).toInt(),
        channel: map['channel'] ?? 'support',
        exportRequestId: map['export_request_id'],
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
    this.exportRequestId,
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
  final String?
  exportRequestId; // Evita confundir una exportación con una solicitud de convenio.
  factory SupportMessage.fromMap(Map<String, dynamic> map) => SupportMessage(
    id: map['id'],
    senderId: map['sender_id'],
    body: map['body'],
    kind: map['kind'],
    createdAt: DateTime.parse(map['created_at']),
    requestId: map['request_id'],
    exportRequestId: map['export_request_id'],
  );
}
