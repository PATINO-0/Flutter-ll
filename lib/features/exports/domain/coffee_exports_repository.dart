import 'dart:typed_data'; // Recibe documentos sin depender de rutas del sistema operativo.
import 'export_models.dart'; // Comparte los datos del flujo de café.
import '../../commerce/domain/entities/commerce_models.dart'; // Reutiliza las tarifas de la tienda.

/// Define las operaciones de asociados, revisores y transportadores.
abstract class CoffeeExportsRepository {
  Future<List<CoffeeCultivation>>
  cultivations(); // Consulta los cultivos permitidos por la sesión.
  Future<List<CoffeeExportLot>>
  lots(); // Consulta lotes y reservas de exportación.
  /// Guarda el cultivo solo cuando la sesión pertenece a su asociado titular o a administración.
  Future<void> saveCultivation(
    Map<String, dynamic> fields,
  ); // Guarda un cultivo propio o gestionado por el personal.
  /// Guarda el lote con su cultivo y respeta las reservas de exportación existentes.
  Future<void> saveLot(
    Map<String, dynamic> fields,
  ); // Guarda un lote con cultivo y código.
  /// Retira únicamente un lote editable que no deba conservarse por su historial.
  Future<void> deleteLot(
    String id,
  ); // Retira solamente lotes sin historial de exportación.
  Future<List<CoffeeExportRequest>>
  requests(); // Consulta solicitudes y exportaciones aceptadas.
  /// Consulta el expediente de exportación con las relaciones autorizadas para la sesión.
  Future<CoffeeExportRequest> request(
    String id,
  ); // Recupera un expediente con sus soportes.
  /// Reserva un lote editable o recupera el borrador para corregir su solicitud.
  Future<CoffeeExportRequest> start(
    String lotId,
  ); // Reserva el lote o recupera el borrador existente.
  Future<List<FreightRate>>
  exportRates(); // Consulta solamente las rutas activas para café.
  /// Obtiene el costo del servidor para el peso del lote y una tarifa habilitada.
  Future<ExportQuote> quote(
    String requestId,
    String rateId,
  ); // Calcula el costo según la ruta y tarifa elegidas.
  /// Guarda un soporte nuevo sin sobrescribir el documento histórico del intento anterior.
  Future<void> attach(
    CoffeeExportRequest request,
    ExportDocumentKind kind,
    String name,
    Uint8List bytes,
  ); // Guarda un soporte privado e inmutable.
  /// Confirma la autorización exacta de ruta, documentos y costo al solicitar una exportación.
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
  /// Solicita al servidor aceptar o rechazar el envío y conservar su decisión en el expediente.
  Future<void> review(
    String id,
    bool approve,
    String reason,
  ); // Acepta o devuelve el expediente.
  /// Solicita un enlace privado de un minuto y lo abre en el visor autorizado del dispositivo.
  Future<void> openDocument(
    String path,
  ); // Abre un soporte durante un minuto para su titular o el personal.
  Future<List<CoffeeShipment>>
  shipments(); // Consulta el seguimiento y el historial propios o del personal.
  Future<List<CoffeeShipment>>
  transportJobs(); // Consulta cargas disponibles y asignadas al transportador.
  /// Valida la compatibilidad y asignación exclusiva antes de asumir una carga.
  Future<void> take(
    String id,
  ); // Valida ruta, disponibilidad y exclusividad al tomar el envío.
  /// Registra estado, anotación y ubicación y exige confirmación para finalizar la entrega.
  Future<void> updateDelivery(
    String id,
    String status,
    String notes,
    String location,
    bool confirmed,
  ); // Registra estados y confirma la entrega.
  Future<List<Map<String, dynamic>>>
  transporters(); // Presenta los transportadores y su carga activa al personal.
  /// Abre el canal de coordinación del transportador con el personal.
  Future<String> transportConversation(
    String driverId,
  ); // Abre el canal entre empleado y transportador.
  /// Abre el canal operativo asociado al expediente de exportación.
  Future<String> exportConversation(
    String requestId,
  ); // Abre el canal alterno del expediente.
  /// Comunica por chat la carga que el trabajador solicita al transportador tomar.
  Future<String> requestPickup(
    String driverId,
    String shipmentId,
    String message,
  ); // Solicita por chat que un transportador tome una carga.
  Future<Map<String, dynamic>>
  seedTransporters(); // Crea de forma controlada las cinco cuentas de prueba solicitadas.
}
