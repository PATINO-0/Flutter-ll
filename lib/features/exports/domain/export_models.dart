/// Describe un cultivo de café y su titular comercial.
class CoffeeCultivation {
  const CoffeeCultivation({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.farm,
    required this.location,
    required this.variety,
    required this.hectares,
  });
  final String id; // Identifica el cultivo al que pertenecerán los lotes.
  final String ownerId; // Mantiene la pertenencia del cultivo al asociado.
  final String name; // Identifica comercialmente el cultivo.
  final String farm; // Conserva el nombre de la finca.
  final String location; // Conserva el municipio y la ubicación de origen.
  final String variety; // Identifica la variedad de café registrada.
  final double hectares; // Conserva el área declarada del cultivo.
  factory CoffeeCultivation.fromMap(Map<String, dynamic> row) =>
      CoffeeCultivation(
        id: row['id'],
        ownerId: row['owner_id'],
        name: row['name'],
        farm: row['farm_name'],
        location: row['location'],
        variety: row['variety'],
        hectares: (row['area_hectares'] as num).toDouble(),
      );
}

/// Representa un lote y la reserva que impide exportarlo dos veces.
class CoffeeExportLot {
  const CoffeeExportLot({
    required this.id,
    required this.name,
    required this.origin,
    required this.weight,
    required this.notes,
    this.ownerId,
    this.cultivationId,
    this.code,
    this.harvestDate,
    this.reservationStatus,
  });
  final String id; // Identifica el lote en solicitudes y documentos.
  final String?
  ownerId; // Los registros históricos sin titular requieren asignación del personal.
  final String? cultivationId; // Vincula el lote con su cultivo.
  final String? code; // Identifica el lote dentro del inventario del asociado.
  final String name; // Describe el café preparado para exportar.
  final String origin; // Conserva el origen registrado del cultivo.
  final double weight; // Determina el costo cotizado por el servidor.
  final String? harvestDate; // Conserva la fecha de cosecha declarada.
  final String notes; // Conserva información de proceso y calidad.
  final String?
  reservationStatus; // Señala un borrador, revisión o aprobación que reserva el lote.
  bool get canRequest =>
      ownerId != null &&
      cultivationId != null &&
      code != null &&
      (reservationStatus == null ||
          reservationStatus ==
              'draft'); // Un rechazo permite un nuevo intento del mismo lote.
  factory CoffeeExportLot.fromMap(Map<String, dynamic> row) {
    String? reservation;
    for (final entry in row['exports'] as List? ?? const []) {
      if (entry['status'] != 'rejected') {
        reservation = entry['status'];
        break;
      }
    } // La base de datos garantiza como máximo una reserva efectiva.
    return CoffeeExportLot(
      id: row['id'],
      ownerId: row['owner_id'],
      cultivationId: row['cultivation_id'],
      code: row['lot_code'],
      name: row['name'],
      origin: row['origin'],
      weight: (row['weight_kg'] as num).toDouble(),
      harvestDate: row['harvest_date'],
      notes: row['notes'] ?? '',
      reservationStatus: reservation,
    );
  }
}

/// Define los tres soportes que debe revisar el empleado para aceptar la exportación.
enum ExportDocumentKind {
  invoice(
    'commercial_invoice',
    'Factura comercial',
    'Factura del café correspondiente al lote y destinatario de la solicitud.',
  ),
  packingList(
    'packing_list',
    'Lista de empaque',
    'Relación de bultos o empaques, código del lote y peso total.',
  ),
  quality(
    'quality_record',
    'Ficha de calidad y trazabilidad',
    'Información de variedad, cosecha, proceso y calidad del café.',
  );

  const ExportDocumentKind(this.value, this.label, this.instructions);
  final String value; // Identificador validado por PostgreSQL.
  final String label; // Nombre del soporte en la interfaz.
  final String
  instructions; // Explica qué información debe aportar el asociado.
}

/// Conserva un archivo privado sin publicar su dirección de descarga.
class ExportDocument {
  const ExportDocument(this.kind, this.path, this.name);
  final String kind; // Distingue factura, empaque y calidad.
  final String path; // Identifica el archivo dentro del depósito privado.
  final String name; // Conserva el nombre original del documento.
  factory ExportDocument.fromMap(Map<String, dynamic> row) =>
      ExportDocument(row['kind'], row['storage_path'], row['original_name']);
}

/// Normaliza las relaciones uno a uno que la API devuelve como objeto o lista.
Map<String, dynamic> exportRelation(dynamic value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  if (value is List && value.isNotEmpty && value.first is Map) {
    return Map<String, dynamic>.from(value.first);
  }
  return {}; // Mantiene válidos los borradores que todavía no tienen envío ni cargo.
}

/// Conserva una solicitud y los valores autorizados al enviarla.
class CoffeeExportRequest {
  const CoffeeExportRequest({
    required this.id,
    required this.number,
    required this.ownerId,
    required this.lotId,
    required this.status,
    required this.origin,
    required this.destination,
    required this.recipient,
    required this.phone,
    required this.documents,
    required this.snapshot,
    this.total,
    this.currency,
    this.rejectionReason,
    this.conversationId,
    this.shipmentId,
    this.trackingCode,
    this.shipmentStatus,
    this.chargeStatus,
    this.freightRateId,
    this.tariffSnapshot = const {},
    this.pickupAddress = '',
    this.deliveryAddress = '',
  });
  final String id; // Vincula expediente, chat y envío aprobado.
  final int number; // Presenta un consecutivo legible para atención.
  final String ownerId; // Identifica al titular de la exportación.
  final String lotId; // Conserva el único lote que se pretende exportar.
  final String status; // Distingue borrador, revisión, aprobación y devolución.
  final String origin; // Conserva la recogida completa que revisó el empleado.
  final String destination; // Conserva el destino completo para agrupar cargas.
  final String recipient; // Identifica al destinatario de la entrega.
  final String phone; // Conserva su contacto operativo.
  final List<ExportDocument> documents; // Conserva los soportes del intento.
  final Map<String, dynamic>
  snapshot; // Mantiene los datos del lote como estaban al autorizar la exportación.
  final double? total; // Conserva el cargo aprobado por el asociado.
  final String? currency; // Evita interpretar una autorización en otra moneda.
  final String? freightRateId; // Recupera la selección del intento anterior.
  final Map<String, dynamic>
  tariffSnapshot; // Conserva la ruta y sus condiciones al enviar.
  final String
  pickupAddress; // Separa la dirección concreta del origen del catálogo.
  final String
  deliveryAddress; // Separa la dirección de entrega del destino habilitado.
  final String?
  rejectionReason; // Explica las correcciones necesarias para volver a solicitar.
  final String? conversationId; // Abre el chat alterno de envíos.
  final String?
  shipmentId; // Solo existe después de la aprobación del personal.
  final String? trackingCode; // Permite reconocer el envío asignado.
  final String? shipmentStatus; // Presenta el estado del envío aceptado.
  final String?
  chargeStatus; // Presenta el cargo como autorizado, no como un pago bancario ejecutado.
  String get label => 'EXP-${number.toString().padLeft(6, '0')}';
  String get statusLabel => switch (status) {
    'draft' => 'Borrador',
    'pending' => 'En revisión',
    'approved' => 'Aceptada',
    'rejected' => 'Rechazada',
    _ => status,
  };
  factory CoffeeExportRequest.fromMap(Map<String, dynamic> row) {
    final lot = exportRelation(row['lot']);
    final shipment = exportRelation(row['shipment']);
    final conversation = exportRelation(row['conversation']);
    final charge = exportRelation(row['charge']);
    return CoffeeExportRequest(
      id: row['id'],
      number: row['request_number'],
      ownerId: row['owner_id'],
      lotId: row['lot_id'],
      status: row['status'],
      origin: row['origin'],
      destination: row['destination'],
      recipient: row['recipient_name'],
      phone: row['recipient_phone'],
      documents: (row['documents'] as List? ?? [])
          .map(
            (item) => ExportDocument.fromMap(Map<String, dynamic>.from(item)),
          )
          .toList(),
      snapshot: row['lot_snapshot'] is Map
          ? Map<String, dynamic>.from(row['lot_snapshot'])
          : {
              'lot_code': lot['lot_code'],
              'lot_name': lot['name'],
              'weight_kg': lot['weight_kg'],
            },
      total: (row['total_cost'] as num?)?.toDouble(),
      currency: row['currency'],
      freightRateId: row['freight_rate_id'],
      tariffSnapshot: exportRelation(row['tariff_snapshot']),
      pickupAddress: row['pickup_address'] ?? row['origin'] ?? '',
      deliveryAddress: row['delivery_address'] ?? row['destination'] ?? '',
      rejectionReason: row['rejection_reason'],
      conversationId: conversation['id'],
      shipmentId: shipment['id'],
      trackingCode: shipment['tracking_code'],
      shipmentStatus: shipment['status'],
      chargeStatus: charge['status'],
    );
  }
}

/// Representa una cotización calculada con datos de la base de datos.
class ExportQuote {
  const ExportQuote({
    required this.weight,
    required this.rate,
    required this.currency,
    required this.total,
    required this.isReference,
    required this.freightRateId,
    required this.origin,
    required this.destination,
    required this.title,
    required this.description,
  });
  final double weight; // Conserva el peso real del lote reservado.
  final double rate; // Conserva el precio por kilogramo usado en la cotización.
  final String currency; // Conserva la moneda que el usuario autoriza.
  final double total; // Conserva el resultado redondeado del servidor.
  final bool isReference; // Identifica la tarifa ilustrativa inicial.
  final String freightRateId; // Identifica la tarifa que se autoriza.
  final String origin; // Conserva el origen confirmado por el servidor.
  final String destination; // Conserva el destino confirmado por el servidor.
  final String title; // Identifica el servicio seleccionado en la tienda.
  final String description; // Presenta las condiciones de la cotización.
  factory ExportQuote.fromMap(Map<String, dynamic> row) => ExportQuote(
    weight: (row['weight_kg'] as num).toDouble(),
    rate: (row['rate_per_kg'] as num).toDouble(),
    currency: row['currency'],
    total: (row['total_cost'] as num).toDouble(),
    isReference: row['is_reference'],
    freightRateId: row['freight_rate_id'],
    origin: row['origin'],
    destination: row['destination'],
    title: row['title'],
    description: row['description'],
  );
}

/// Comparte estados entre el historial de entregas, el seguimiento y el espacio del transportador.
const coffeeDeliveryStatuses = {
  'accepted': 'Aceptado',
  'received': 'Recibido',
  'in_transit': 'En camino',
  'delivered': 'Terminado · Entregado',
};

class CoffeeShipment {
  const CoffeeShipment({
    required this.id,
    required this.code,
    required this.origin,
    required this.destination,
    required this.status,
    required this.lotCode,
    required this.weight,
    required this.events,
    this.transporterId,
    this.location,
    this.deliveredAt,
    this.requestId,
    this.conversationId,
    this.canTake = false,
    this.recipient = '',
    this.phone = '',
  });
  final String id; // Identifica la carga que puede tomar el transportador.
  final String code; // Conserva el número de seguimiento.
  final String origin; // Define el punto completo de recogida.
  final String destination; // Define la entrega completa acordada.
  final String status; // Distingue envíos activos de entregas terminadas.
  final String lotCode; // Identifica el lote transportado.
  final double
  weight; // Informa de la carga sin exponer su autorización de cobro al transportador.
  final List<Map<String, dynamic>>
  events; // Conserva el historial de ubicaciones y estados.
  final String? transporterId; // Identifica al único responsable de la carga.
  final String? location; // Presenta la última ubicación declarada.
  final String? deliveredAt; // Conserva la confirmación de llegada al destino.
  final String? requestId; // Abre el expediente para el asociado y el empleado.
  final String?
  conversationId; // Abre el chat de ese envío para sus participantes.
  final bool
  canTake; // Refleja compatibilidad consultada en servidor; la toma vuelve a validarla.
  final String recipient; // Solo se entrega al transportador que tomó la carga.
  final String phone; // Solo se entrega al transportador asignado.
  bool get isActive =>
      const ['accepted', 'received', 'in_transit'].contains(status);
  factory CoffeeShipment.fromMap(Map<String, dynamic> row) {
    final request = exportRelation(row['request']);
    final snapshot = exportRelation(request['lot_snapshot']);
    final conversation = exportRelation(request['conversation']);
    return CoffeeShipment(
      id: row['id'],
      code: row['tracking_code'],
      origin: row['origin'],
      destination: row['destination'],
      status: row['status'],
      lotCode: row['lot_code'] ?? snapshot['lot_code'] ?? 'Lote histórico',
      weight: ((row['weight_kg'] ?? request['weight_kg'] ?? 0) as num)
          .toDouble(),
      events:
          (row['events'] as List? ?? [])
              .map((item) => Map<String, dynamic>.from(item))
              .toList()
            ..sort(
              (a, b) => (a['created_at'] as String).compareTo(b['created_at']),
            ),
      transporterId: row['transporter_id'],
      location: row['current_location'],
      deliveredAt: row['delivered_at'],
      requestId: row['export_request_id'],
      conversationId: row['conversation_id'] ?? conversation['id'],
      canTake: row['can_take'] ?? false,
      recipient: row['recipient_name'] ?? '',
      phone: row['recipient_phone'] ?? '',
    );
  }
}
