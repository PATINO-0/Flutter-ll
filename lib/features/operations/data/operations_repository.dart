import 'dart:async'; // Acota la duración de las consultas operativas.
import 'package:supabase_flutter/supabase_flutter.dart'; // Respeta la sesión y las políticas por propietario.
import '../../../core/errors/app_exception.dart'; // Presenta mensajes comprensibles al usuario.

/// Describe una operación real y su seguimiento visible en la aplicación.
class Shipment {
  const Shipment(
    this.id,
    this.trackingCode,
    this.type,
    this.description,
    this.origin,
    this.destination,
    this.status,
    this.events,
  );
  final String id; // Identifica la operación en las funciones del servidor.
  final String trackingCode; // Permite al asociado reconocer su envío.
  final String type; // Distingue importaciones y exportaciones.
  final String description; // Describe la mercancía o la operación.
  final String origin; // Presenta el origen registrado.
  final String destination; // Presenta el destino registrado.
  final String status; // Conserva el estado vigente del envío.
  final List<Map<String, dynamic>>
  events; // Conserva el historial autorizado de seguimiento.
  static const statuses = {
    'pending': 'Pendiente',
    'in_transit': 'En tránsito',
    'customs': 'En aduana',
    'delivered': 'Entregado',
    'cancelled': 'Cancelado',
  }; // Traduce los estados utilizados por PostgreSQL.
  factory Shipment.fromMap(Map<String, dynamic> row) => Shipment(
    row['id'],
    row['tracking_code'],
    row['operation_type'],
    row['description'],
    row['origin'],
    row['destination'],
    row['status'],
    (row['events'] as List)
        .map((event) => Map<String, dynamic>.from(event))
        .toList()
      ..sort((a, b) => (a['created_at'] as String).compareTo(b['created_at'])),
  );
}

/// Implementa las operaciones ya habilitadas por un convenio aprobado.
class OperationsRepository {
  const OperationsRepository(this._client);
  final SupabaseClient _client; // Utiliza los permisos del usuario autenticado.
  Future<T> _run<T>(Future<T> Function() operation) async {
    try {
      return await operation().timeout(const Duration(seconds: 20));
    } on PostgrestException catch (error) {
      throw AppException(
        error.code == '22023'
            ? error.message
            : 'No fue posible consultar o guardar la operación.',
      );
    } catch (_) {
      throw const AppException(
        'No fue posible completar la operación. Verifica tu conexión.',
      );
    }
  }

  Future<List<Shipment>> shipments() => _run(() async {
    final rows = await _client
        .from('shipments')
        .select('*,events:shipment_events(*)')
        .order('created_at', ascending: false);
    return rows.map(Shipment.fromMap).toList();
  }); // Los asociados solo reciben sus propias operaciones.
  Future<void> createShipment({
    required String ownerId,
    required String type,
    required String description,
    required String origin,
    required String destination,
  }) => _run(() async {
    await _client.rpc(
      'create_shipment',
      params: {
        'target_owner': ownerId,
        'shipment_type': type,
        'shipment_description': description.trim(),
        'shipment_origin': origin.trim(),
        'shipment_destination': destination.trim(),
      },
    );
  }); // El servidor exige una vinculación aprobada.
  Future<void> updateStatus(String id, String status, String notes) =>
      _run(() async {
        await _client.rpc(
          'update_shipment_status',
          params: {
            'target_shipment': id,
            'new_status': status,
            'event_notes': notes.trim(),
          },
        );
      }); // Registra cada transición en el historial.
  Future<List<Map<String, dynamic>>> coffeeLots() => _run(
    () async => await _client.from('coffee_lots').select().order('name'),
  ); // Reserva los lotes al personal.
  Future<void> saveCoffee(Map<String, dynamic> data) => _run(() async {
    await _client.from('coffee_lots').upsert({
      ...data,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }); // Permite crear y corregir los lotes internos.
  Future<void> deleteCoffee(String id) => _run(() async {
    await _client.from('coffee_lots').delete().eq('id', id);
  }); // Permite retirar un lote del módulo interno.
}
