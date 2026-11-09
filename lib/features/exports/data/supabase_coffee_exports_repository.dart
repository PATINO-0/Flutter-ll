import 'dart:async'; // Acota la espera de consultas y cargas de soportes.
import 'dart:typed_data'; // Representa archivos seleccionados en cualquier plataforma.
import 'package:supabase_flutter/supabase_flutter.dart'; // Utiliza la identidad del usuario para aplicar las políticas.
import 'package:url_launcher/url_launcher.dart'; // Abre documentos con el visor del dispositivo.
import '../../../core/errors/app_exception.dart'; // Presenta errores comprensibles y traducidos.
import '../../commerce/data/repositories/supabase_commerce_repository.dart'; // Reutiliza la validación de cabeceras y tamaño de archivos.
import '../domain/coffee_exports_repository.dart'; // Implementa el contrato del flujo de exportación.
import '../domain/export_models.dart'; // Convierte los resultados de la API en datos de dominio.
import '../../commerce/domain/entities/commerce_models.dart'; // Utiliza las mismas tarifas visibles en la tienda.

/// Invoca los servicios protegidos de cultivos, lotes, tarifas, exportaciones y transportadores.
class SupabaseCoffeeExportsRepository implements CoffeeExportsRepository {
  const SupabaseCoffeeExportsRepository(this._client);
  final SupabaseClient _client; // No contiene credenciales administrativas.
  static const _requestFields =
      '*,documents:export_documents(*),lot:coffee_lots(*),conversation:conversations(id),shipment:shipments(id,tracking_code,status),charge:export_charges(status)'; // Recupera únicamente relaciones protegidas por las políticas del expediente.
  Future<T> _run<T>(Future<T> Function() operation) async {
    try {
      return await operation().timeout(const Duration(seconds: 30));
    } on AppException {
      rethrow;
    } on PostgrestException catch (error) {
      if (['22023', 'P0001'].contains(error.code)) {
        throw AppException(error.message);
      }
      if (error.code == '23505') {
        throw const AppException(
          'El código del lote ya existe o el lote ya tiene una exportación reservada. Actualiza la lista.',
        );
      }
      if (error.code == '42501') {
        throw const AppException(
          'No tienes permiso para realizar esta operación. Actualiza tus datos de acceso.',
        );
      }
      if (['PGRST205', 'PGRST202', '42883'].contains(error.code)) {
        throw const AppException(
          'El servicio de exportación de café todavía no está configurado. Contacta al administrador.',
        );
      }
      throw const AppException(
        'No fue posible completar la operación. Revisa los datos e intenta nuevamente.',
      );
    } on FunctionException catch (error) {
      final details = error.details;
      throw AppException(
        details is Map && details['error'] is String
            ? details['error']
            : 'No fue posible preparar los transportadores.',
      );
    } on TimeoutException {
      throw const AppException(
        'La conexión tardó demasiado. Intenta nuevamente.',
      );
    } catch (_) {
      throw const AppException(
        'No fue posible completar la operación. Verifica tu conexión.',
      );
    }
  }

  /// Consulta cultivos autorizados y los datos del titular necesarios para supervisión.
  @override
  Future<List<CoffeeCultivation>> cultivations() => _run(() async {
    final rows = await _client.rpc('list_coffee_cultivations');
    return (rows as List)
        .map((row) => CoffeeCultivation.fromMap(Map<String, dynamic>.from(row)))
        .toList();
  });

  /// Consulta lotes con titular, cultivo y reservas de exportación.
  @override
  Future<List<CoffeeExportLot>> lots() => _run(() async {
    final rows = await _client.rpc('list_coffee_lots');
    return (rows as List)
        .map((row) => CoffeeExportLot.fromMap(Map<String, dynamic>.from(row)))
        .toList();
  });

  /// Guarda el cultivo solo cuando la sesión pertenece a su asociado titular o a administración.
  @override
  Future<void> saveCultivation(Map<String, dynamic> fields) => _run(() async {
    await _client.rpc('save_coffee_cultivation', params: fields);
  });

  /// Guarda el lote con su cultivo y respeta las reservas de exportación existentes.
  @override
  Future<void> saveLot(Map<String, dynamic> fields) => _run(() async {
    await _client.rpc('save_coffee_export_lot', params: fields);
  });

  /// Retira únicamente un lote editable que no deba conservarse por su historial.
  @override
  Future<void> deleteLot(String id) => _run(() async {
    await _client.rpc('delete_coffee_export_lot', params: {'target_lot': id});
  });

  /// Consulta las solicitudes de exportación y su archivo documental autorizado.
  @override
  Future<List<CoffeeExportRequest>> requests() => _run(() async {
    final rows = await _client
        .from('export_requests')
        .select(_requestFields)
        .order('created_at', ascending: false);
    return rows.map(CoffeeExportRequest.fromMap).toList();
  });

  /// Consulta el expediente de exportación con las relaciones autorizadas para la sesión.
  @override
  Future<CoffeeExportRequest> request(String id) => _run(() async {
    final row = await _client
        .from('export_requests')
        .select(_requestFields)
        .eq('id', id)
        .single();
    return CoffeeExportRequest.fromMap(row);
  });

  /// Reserva un lote editable o recupera el borrador para corregir su solicitud.
  @override
  Future<CoffeeExportRequest> start(String lotId) => _run(() async {
    final id = await _client.rpc(
      'start_coffee_export',
      params: {'target_lot': lotId},
    );
    return request(id as String);
  });

  /// Selecciona exclusivamente tarifas activas por kilogramo habilitadas para café.
  @override
  Future<List<FreightRate>> exportRates() => _run(() async {
    final rows = await _client
        .from('freight_rates')
        .select()
        .eq('is_active', true)
        .eq('allows_coffee_export', true)
        .order('origin')
        .order('destination');
    return rows
        .map(FreightRate.fromMap)
        .where((rate) => rate.isCoffeeExportAvailable)
        .toList();
  }); // No ofrece servicios desactivados ni unidades por volumen.
  /// Obtiene el costo del servidor para el peso del lote y una tarifa habilitada.
  @override
  Future<ExportQuote> quote(String requestId, String rateId) => _run(() async {
    final row = await _client.rpc(
      'quote_coffee_export',
      params: {'target_request': requestId, 'target_rate': rateId},
    );
    return ExportQuote.fromMap(Map<String, dynamic>.from(row));
  });

  /// Guarda un soporte nuevo sin sobrescribir el documento histórico del intento anterior.
  @override
  Future<void> attach(
    CoffeeExportRequest request,
    ExportDocumentKind kind,
    String name,
    Uint8List bytes,
  ) => _run(() async {
    final extension = SupabaseCommerceRepository.documentType(
      bytes,
    ); // Rechaza archivos falsos o que superen los 10 MB.
    final path =
        '${request.ownerId}/${request.id}/${kind.value}_${DateTime.now().microsecondsSinceEpoch}.$extension';
    final mime = extension == 'pdf'
        ? 'application/pdf'
        : extension == 'png'
        ? 'image/png'
        : 'image/jpeg';
    await _client.storage
        .from('export-documents')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: mime,
            cacheControl: '0',
            upsert: false,
          ),
        ); // Nunca sobrescribe soportes anteriores.
    await _client.rpc(
      'attach_export_document',
      params: {
        'target_request': request.id,
        'document_kind': kind.value,
        'object_path': path,
        'file_name': name,
      },
    );
  });

  /// Confirma la autorización exacta de ruta, documentos y costo al solicitar una exportación.
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
  }) => _run(() async {
    return await _client.rpc(
          'submit_coffee_export',
          params: {
            'target_request': request.id,
            'target_rate': quote.freightRateId,
            'pickup_location': origin.trim(),
            'delivery_destination': destination.trim(),
            'recipient': recipient.trim(),
            'contact_phone': phone.trim(),
            'expected_total': quote.total,
            'expected_currency': quote.currency,
            'expected_rate': quote.rate,
            'expected_origin': quote.origin,
            'expected_destination': quote.destination,
            'accept_charge': authorizeCharge,
            'accept_data_processing': authorizeData,
          },
        )
        as String; // El servidor recalcula el costo y rechaza una cotización desactualizada.
  });

  /// Solicita al servidor aceptar o rechazar el envío y conservar su decisión en el expediente.
  @override
  Future<void> review(String id, bool approve, String reason) => _run(() async {
    await _client.rpc(
      'review_coffee_export',
      params: {
        'target_request': id,
        'approve': approve,
        'reason': reason.trim(),
      },
    );
  });

  /// Solicita un enlace privado de un minuto y lo abre en el visor autorizado del dispositivo.
  @override
  Future<void> openDocument(String path) => _run(() async {
    final url = await _client.storage
        .from('export-documents')
        .createSignedUrl(path, 60);
    if (!await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    )) {
      throw const AppException('No fue posible abrir el documento.');
    }
  });

  /// Consulta cargas de café aceptadas para seguimiento o historial de entregas.
  @override
  Future<List<CoffeeShipment>> shipments() => _run(() async {
    final rows = await _client
        .from('shipments')
        .select(
          '*,events:shipment_events(*),request:export_requests!shipments_export_request_id_fkey(*,conversation:conversations(id))',
        )
        .eq('operation_type', 'export')
        .not('export_request_id', 'is', null)
        .order('created_at', ascending: false);
    return rows
        .map(CoffeeShipment.fromMap)
        .toList(); // Los asociados solo reciben sus exportaciones de café aprobadas.
  });

  /// Consulta únicamente cargas disponibles o asignadas que puede ver el transportador.
  @override
  Future<List<CoffeeShipment>> transportJobs() => _run(() async {
    final rows = await _client.rpc('list_transport_shipments');
    return (rows as List)
        .map((row) => CoffeeShipment.fromMap(Map<String, dynamic>.from(row)))
        .toList();
  });

  /// Valida la compatibilidad y asignación exclusiva antes de asumir una carga.
  @override
  Future<void> take(String id) => _run(() async {
    await _client.rpc('take_coffee_shipment', params: {'target_shipment': id});
  });

  /// Registra estado, anotación y ubicación y exige confirmación para finalizar la entrega.
  @override
  Future<void> updateDelivery(
    String id,
    String status,
    String notes,
    String location,
    bool confirmed,
  ) => _run(() async {
    await _client.rpc(
      'update_coffee_delivery',
      params: {
        'target_shipment': id,
        'new_status': status,
        'update_notes': notes.trim(),
        'new_location': location.trim(),
        'confirm_delivery': confirmed,
      },
    );
  });

  /// Recupera el directorio operativo y las cargas activas para el personal autorizado.
  @override
  Future<List<Map<String, dynamic>>> transporters() => _run(() async {
    final rows = await _client.rpc('list_transporters');
    return (rows as List).map((row) => Map<String, dynamic>.from(row)).toList();
  });

  /// Abre el canal de coordinación del transportador con el personal.
  @override
  Future<String> transportConversation(String driverId) => _run(
    () async =>
        await _client.rpc(
              'open_transport_conversation',
              params: {'target_driver': driverId},
            )
            as String,
  );

  /// Abre el canal operativo asociado al expediente de exportación.
  @override
  Future<String> exportConversation(String requestId) => _run(
    () async =>
        await _client.rpc(
              'open_export_conversation',
              params: {'target_request': requestId},
            )
            as String,
  );

  /// Comunica por chat la carga que el trabajador solicita al transportador tomar.
  @override
  Future<String> requestPickup(
    String driverId,
    String shipmentId,
    String message,
  ) => _run(
    () async =>
        await _client.rpc(
              'request_transport_pickup',
              params: {
                'target_driver': driverId,
                'target_shipment': shipmentId,
                'message_body': message.trim(),
              },
            )
            as String,
  );

  /// Prepara cuentas de prueba sin restablecer contraseñas de usuarios existentes.
  @override
  Future<Map<String, dynamic>> seedTransporters() => _run(() async {
    final response = await _client.functions.invoke('seed-transporters');
    return Map<String, dynamic>.from(response.data as Map);
  });
}
