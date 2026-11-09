import 'dart:typed_data'; // Representa documentos de prueba sin acceder al dispositivo.
import 'package:riexport_ue/features/exports/domain/coffee_exports_repository.dart'; // Sustituye los servicios de exportación en las pruebas.
import 'package:riexport_ue/features/exports/domain/export_models.dart'; // Construye cultivos, cotizaciones y cargas reproducibles.
import 'package:riexport_ue/features/commerce/domain/entities/commerce_models.dart'; // Reproduce el catálogo habilitado de la tienda.

/// Conserva datos y acciones del escenario sin crear cuentas, cargos ni envíos reales.
class FakeCoffeeExportsRepository implements CoffeeExportsRepository {
  final List<CoffeeCultivation> cropData =
      []; // Controla los cultivos visibles en la prueba.
  final List<CoffeeExportLot> lotData =
      []; // Controla los lotes elegibles y reservados.
  final List<CoffeeExportRequest> requestData =
      []; // Controla borradores y expedientes aceptados.
  final List<CoffeeShipment> shipmentData =
      []; // Controla el historial y seguimiento autorizado.
  final List<CoffeeShipment> jobData =
      []; // Controla cargas disponibles y asignadas al transportador.
  final List<Map<String, dynamic>> driverData =
      []; // Controla el directorio del personal.
  int submissions = 0; // Detecta envíos sin autorización o duplicados.
  bool? chargeAuthorization; // Registra la aceptación del importe exacto.
  bool?
  dataAuthorization; // Registra la autorización de datos de la exportación.
  String? lastDeliveryStatus; // Comprueba el cierre del seguimiento.
  bool? deliveryConfirmed; // Comprueba la confirmación explícita de entrega.
  String? takenId; // Identifica el envío tomado desde la interfaz.
  final List<FreightRate> rateData = [
    exportRate('rate', 'Popayán', 'Bogotá', 1200),
    exportRate('second-rate', 'Popayán', 'Cartagena', 2000),
  ]; // Permite probar cambios de destino y su cotización independiente.
  String?
  submittedRateId; // Verifica que la solicitud conserva la tarifa seleccionada.
  @override
  Future<List<CoffeeCultivation>> cultivations() async => cropData;
  @override
  Future<List<CoffeeExportLot>> lots() async => lotData;
  @override
  Future<void> saveCultivation(Map<String, dynamic> fields) async {}
  @override
  Future<void> saveLot(Map<String, dynamic> fields) async {}
  @override
  Future<void> deleteLot(String id) async {}
  @override
  Future<List<CoffeeExportRequest>> requests() async => requestData;
  @override
  Future<CoffeeExportRequest> request(String id) async =>
      requestData.firstWhere((item) => item.id == id);
  @override
  Future<CoffeeExportRequest> start(String lotId) async =>
      requestData.firstWhere((item) => item.lotId == lotId);
  @override
  Future<List<FreightRate>> exportRates() async => rateData;
  @override
  Future<ExportQuote> quote(String requestId, String rateId) async {
    final selected = rateData.firstWhere((rate) => rate.id == rateId);
    return ExportQuote(
      weight: 100,
      rate: selected.amount,
      currency: selected.currency,
      total: 100 * selected.amount,
      isReference: selected.isReference,
      freightRateId: selected.id,
      origin: selected.origin,
      destination: selected.destination,
      title: selected.title,
      description: selected.description,
    );
  }

  @override
  Future<void> attach(
    CoffeeExportRequest request,
    ExportDocumentKind kind,
    String name,
    Uint8List bytes,
  ) async {}
  @override
  Future<String> submit(
    CoffeeExportRequest request,
    ExportQuote quote, {
    required String origin,
    required String destination,
    required String recipient,
    required String phone,
    required bool authorizeCharge,
    required bool authorizeData,
  }) async {
    submissions++;
    chargeAuthorization = authorizeCharge;
    dataAuthorization = authorizeData;
    submittedRateId = quote.freightRateId;
    return 'export-conversation';
  }

  @override
  Future<void> review(String id, bool approve, String reason) async {}
  @override
  Future<void> openDocument(String path) async {}
  @override
  Future<List<CoffeeShipment>> shipments() async => shipmentData;
  @override
  Future<List<CoffeeShipment>> transportJobs() async => jobData;
  @override
  Future<void> take(String id) async {
    takenId = id;
  }

  @override
  Future<void> updateDelivery(
    String id,
    String status,
    String notes,
    String location,
    bool confirmed,
  ) async {
    lastDeliveryStatus = status;
    deliveryConfirmed = confirmed;
  }

  @override
  Future<List<Map<String, dynamic>>> transporters() async => driverData;
  @override
  Future<String> transportConversation(String driverId) async =>
      'driver-conversation';
  @override
  Future<String> exportConversation(String requestId) async =>
      'export-conversation';
  @override
  Future<String> requestPickup(
    String driverId,
    String shipmentId,
    String message,
  ) async => 'driver-conversation';
  @override
  Future<Map<String, dynamic>> seedTransporters() async => {
    'created': 5,
    'skipped': 0,
    'errors': [],
  };
}

CoffeeExportRequest exportDraft() => CoffeeExportRequest(
  id: 'request',
  number: 1,
  ownerId: 'current-user',
  lotId: 'lot',
  status: 'draft',
  freightRateId: 'rate',
  pickupAddress: 'Finca de prueba 1',
  deliveryAddress: 'Bodega de prueba 1',
  origin: 'Popayán, finca 1',
  destination: 'Bogotá, bodega 1',
  recipient: 'Destinatario de prueba',
  phone: '+573001234567',
  documents: [
    for (final kind in ExportDocumentKind.values)
      ExportDocument(kind.value, '${kind.value}.pdf', '${kind.value}.pdf'),
  ],
  snapshot: {
    'lot_code': 'LOTE-1',
    'lot_name': 'Café de prueba',
    'weight_kg': 100,
  },
); // Conserva los tres soportes necesarios para probar la autorización.
CoffeeShipment coffeeShipment(
  String id,
  String status, {
  String? driverId,
  bool canTake = false,
}) => CoffeeShipment(
  id: id,
  code: 'RIT-$id',
  origin: 'Popayán, finca 1',
  destination: 'Bogotá, bodega 1',
  status: status,
  lotCode: 'LOTE-$id',
  weight: 100,
  events: [],
  transporterId: driverId,
  canTake: canTake,
  deliveredAt: status == 'delivered' ? '2026-11-08T12:00:00Z' : null,
); // Genera cargas distintas sin información personal real.

FreightRate exportRate(
  String id,
  String origin,
  String destination,
  double amount, {
  bool active = true,
  bool enabled = true,
  String unit = 'kg',
}) => FreightRate(
  id: id,
  title: 'Flete de café $destination',
  origin: origin,
  destination: destination,
  amount: amount,
  currency: 'COP',
  unit: unit,
  description: 'Condiciones de prueba',
  isReference: true,
  isActive: active,
  allowsCoffeeExport: enabled,
); // Genera rutas controladas sin cotizaciones comerciales reales.
