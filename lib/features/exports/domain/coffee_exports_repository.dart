import 'dart:typed_data'; // Recibe documentos sin depender de rutas del sistema operativo.
import 'export_models.dart'; // Comparte los datos del flujo de café.
import '../../commerce/domain/entities/commerce_models.dart'; // Reutiliza las tarifas de la tienda.

/// Define las operaciones de asociados, revisores y transportadores.
abstract class CoffeeExportsRepository {
  Future<List<CoffeeCultivation>>
  cultivations(); // Consulta los cultivos permitidos por la sesión.
  Future<List<CoffeeExportLot>>
  lots(); // Consulta lotes y reservas de exportación.
  Future<void> saveCultivation(
    Map<String, dynamic> fields,
  ); // Guarda un cultivo propio o gestionado por el personal.
  Future<void> saveLot(
    Map<String, dynamic> fields,
  ); // Guarda un lote con cultivo y código.
  Future<void> deleteLot(
    String id,
  ); // Retira solamente lotes sin historial de exportación.
  Future<List<CoffeeExportRequest>>
  requests(); // Consulta solicitudes y exportaciones aceptadas.
  Future<CoffeeExportRequest> request(
    String id,
  ); // Recupera un expediente con sus soportes.
  Future<CoffeeExportRequest> start(
    String lotId,
  ); // Reserva el lote o recupera el borrador existente.
  Future<List<FreightRate>>
  exportRates(); // Consulta solamente las rutas activas para café.
  Future<ExportQuote> quote(
    String requestId,
    String rateId,
  ); // Calcula el costo según la ruta y tarifa elegidas.
  Future<void> attach(
    CoffeeExportRequest request,
    ExportDocumentKind kind,
    String name,
    Uint8List bytes,
  ); // Guarda un soporte privado e inmutable.
  Future<String> submit(
    CoffeeExportRequest request,
    ExportQuote quote, {
    required String origin,
    required String destination,
    required String recipient,
    required String phone,
    required bool authorizeCharge,
    required bool authorizeData,
  }); // Envía una solicitud con autorización del costo exacto.
  Future<void> review(
    String id,
    bool approve,
    String reason,
  ); // Acepta o devuelve el expediente.
  Future<void> openDocument(
    String path,
  ); // Abre un soporte durante un minuto para su titular o el personal.
  Future<List<CoffeeShipment>>
  shipments(); // Consulta el seguimiento y el historial propios o del personal.
  Future<List<CoffeeShipment>>
  transportJobs(); // Consulta cargas disponibles y asignadas al transportador.
  Future<void> take(
    String id,
  ); // Valida ruta, disponibilidad y exclusividad al tomar el envío.
  Future<void> updateDelivery(
    String id,
    String status,
    String notes,
    String location,
    bool confirmed,
  ); // Registra estados y confirma la entrega.
  Future<List<Map<String, dynamic>>>
  transporters(); // Presenta los transportadores y su carga activa al personal.
  Future<String> transportConversation(
    String driverId,
  ); // Abre el canal entre empleado y transportador.
  Future<String> exportConversation(
    String requestId,
  ); // Abre el canal alterno del expediente.
  Future<String> requestPickup(
    String driverId,
    String shipmentId,
    String message,
  ); // Solicita por chat que un transportador tome una carga.
  Future<Map<String, dynamic>>
  seedTransporters(); // Crea de forma controlada las cinco cuentas de prueba solicitadas.
}
