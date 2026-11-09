import 'dart:async'; // Evita esperas indefinidas en las operaciones comerciales.
import 'dart:typed_data'; // Representa documentos seleccionados en móvil, escritorio y web.
import 'package:supabase_flutter/supabase_flutter.dart'; // Utiliza la sesión actual y las políticas del servidor.
import 'package:url_launcher/url_launcher.dart'; // Abre documentos autorizados con el visor del dispositivo.
import '../../../../core/errors/app_exception.dart'; // Traduce fallos técnicos a mensajes de interfaz.
import '../../../auth/domain/entities/user_profile.dart'; // Convierte las cuentas comerciales de la API.
import '../../domain/entities/commerce_models.dart'; // Comparte los datos del flujo comercial.
import '../../domain/repositories/commerce_repository.dart'; // Implementa el contrato del módulo.

/// Delega las decisiones y los permisos en funciones transaccionales de Supabase.
class SupabaseCommerceRepository implements CommerceRepository {
  const SupabaseCommerceRepository(this._client);
  final SupabaseClient _client; // Nunca contiene una clave administrativa.
  static const _requestSelect =
      '*,documents:request_documents(*)'; // Consulta los soportes respetando las políticas de acceso.

  /// Traduce errores sin sustituir permisos rechazados por permisos locales.
  Future<T> _run<T>(Future<T> Function() action) async {
    try {
      return await action().timeout(const Duration(seconds: 30));
    } on AppException {
      rethrow;
    } on PostgrestException catch (error) {
      if (['P0001', '22023'].contains(error.code)) {
        throw AppException(error.message);
      }
      if (error.code == '42501') {
        throw const AppException(
          'No tienes permiso para realizar esta operación. Actualiza tus datos de acceso.',
        ); // Evita mostrar mensajes internos de las políticas de PostgreSQL.
      }
      if (error.code == '23514') {
        throw const AppException(
          'Revisa los valores ingresados; alguno supera los límites permitidos.',
        ); // Traduce las restricciones de tablas al español.
      }
      if (['PGRST205', 'PGRST202', '42P01', '42883'].contains(error.code)) {
        throw const AppException(
          'Este servicio todavía no está disponible. Contacta al administrador.',
        );
      }
      throw const AppException(
        'No fue posible completar la operación. Actualiza e intenta nuevamente.',
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

  @override
  Future<List<FreightRate>> listRates() => _run(() async {
    final rows = await _client
        .from('freight_rates')
        .select()
        .order(
          'title',
        ); // Obtiene tarifas activas o todas si la sesión tiene administración.
    return rows.map(FreightRate.fromMap).toList();
  });
  @override
  Future<void> saveRate(Map<String, dynamic> data) => _run(() async {
    await _client.from('freight_rates').upsert({
      ...data,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }); // Las políticas permiten modificar precios solo al administrador.
  });
  @override
  Future<List<UserProfile>> listCustomers() => _run(() async {
    final rows = await _client.rpc(
      'list_customers',
    ); // El servidor verifica el rol del trabajador y oculta cuentas internas.
    return (rows as List)
        .map((row) => UserProfile.fromMap(Map<String, dynamic>.from(row)))
        .toList();
  });
  @override
  Future<List<AssociationRequest>> listRequests() => _run(() async {
    final rows = await _client
        .from('association_requests')
        .select(_requestSelect)
        .neq('status', 'draft')
        .order(
          'created_at',
          ascending: false,
        ); // Conserva los intentos anteriores sin mostrar borradores en la bandeja.
    return rows.map(AssociationRequest.fromMap).toList();
  });
  @override
  Future<AssociationRequest> getRequest(String id) => _run(() async {
    final row = await _client
        .from('association_requests')
        .select(_requestSelect)
        .eq('id', id)
        .single(); // Consulta únicamente el expediente permitido por las políticas.
    return AssociationRequest.fromMap(row);
  });
  @override
  Future<AssociationRequest> startRequest(String ownerId) => _run(() async {
    final id = await _client.rpc(
      'start_association_request',
      params: {'target_owner': ownerId},
    ); // El servidor aplica la exclusión de pendientes y el plazo de 30 días.
    return getRequest(id as String);
  });

  /// Identifica el tipo real del archivo antes de enviarlo, sin confiar únicamente en su extensión.
  static String documentType(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > 10 * 1024 * 1024) {
      throw const AppException(
        'El archivo debe tener contenido y pesar como máximo 10 MB.',
      );
    }
    if (bytes.length >= 5 && String.fromCharCodes(bytes.take(5)) == '%PDF-') {
      return 'pdf'; // Reconoce la cabecera de un documento PDF.
    }
    if (bytes.length >= 3 &&
        bytes[0] == 255 &&
        bytes[1] == 216 &&
        bytes[2] == 255) {
      return 'jpg'; // Reconoce una imagen JPEG.
    }
    const png = [
      137,
      80,
      78,
      71,
      13,
      10,
      26,
      10,
    ]; // Define la firma completa de un archivo PNG.
    if (bytes.length >= 8 &&
        List.generate(
          8,
          (index) => bytes[index] == png[index],
        ).every((same) => same)) {
      return 'png';
    }
    throw const AppException(
      'Selecciona un documento PDF o una imagen JPG o PNG válida.',
    );
  }

  @override
  Future<void> attachDocument(
    AssociationRequest request,
    AgreementDocumentKind kind,
    String name,
    Uint8List bytes,
  ) => _run(() async {
    final extension = documentType(
      bytes,
    ); // Valida tamaño y cabecera antes de usar la conexión.
    final mime = extension == 'pdf'
        ? 'application/pdf'
        : extension == 'png'
        ? 'image/png'
        : 'image/jpeg'; // Declara el formato que también restringe el depósito.
    final path =
        '${request.ownerId}/${request.id}/${kind.value}_${DateTime.now().microsecondsSinceEpoch}.$extension'; // Crea un objeto nuevo para no sobrescribir documentos previos.
    await _client.storage
        .from('agreement-documents')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: mime,
            cacheControl: '0',
            upsert: false,
          ),
        ); // Carga el documento en un depósito privado.
    await _client.rpc(
      'attach_request_document',
      params: {
        'target_request': request.id,
        'document_kind': kind.value,
        'object_path': path,
        'file_name': name,
      },
    ); // Registra solamente archivos existentes del borrador autorizado.
  });
  @override
  Future<String> submitRequest(
    AssociationRequest request, {
    required String fullName,
    required String identityNumber,
    required String phone,
    required String address,
    required String business,
    required bool consent,
  }) => _run(() async {
    final id = await _client.rpc(
      'submit_association_request',
      params: {
        'target_request': request.id,
        'applicant_name': fullName.trim(),
        'applicant_identity': identityNumber.trim(),
        'applicant_phone': phone.trim(),
        'applicant_address': address.trim(),
        'applicant_business': business.trim(),
        'accepted_data_processing': consent,
      },
    ); // Guarda la solicitud y el aviso del chat en una sola transacción.
    return id as String;
  });
  @override
  Future<void> reviewRequest(
    String id, {
    required bool approve,
    String reason = '',
  }) => _run(() async {
    await _client.rpc(
      'review_association_request',
      params: {
        'target_request': id,
        'approve': approve,
        'reason': reason.trim(),
      },
    ); // El servidor resuelve una sola vez y aplica la promoción al aprobar.
  });
  @override
  Future<List<Agreement>> listAgreements() => _run(() async {
    final rows = await _client
        .from('agreements')
        .select(
          '*,request:association_requests!agreements_request_id_fkey($_requestSelect)',
        )
        .order(
          'created_at',
          ascending: false,
        ); // Conserva los documentos originales del expediente aprobado.
    return rows.map(Agreement.fromMap).toList();
  });
  @override
  Future<void> openDocument(String path) => _run(() async {
    final url = await _client.storage
        .from('agreement-documents')
        .createSignedUrl(
          path,
          60,
        ); // Comprueba el acceso actual y limita la descarga a un minuto.
    if (!await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    )) {
      throw const AppException(
        'No fue posible abrir el documento en este dispositivo.',
      );
    }
  });
  @override
  Future<List<SupportConversation>> listConversations() => _run(() async {
    final rows = await _client.rpc(
      'list_conversations',
    ); // Devuelve solo chats propios o los autorizados al personal.
    return (rows as List)
        .map(
          (row) => SupportConversation.fromMap(Map<String, dynamic>.from(row)),
        )
        .toList();
  });
  @override
  Future<String> openConversation(String ownerId) => _run(() async {
    return await _client.rpc(
          'open_support_conversation',
          params: {'target_owner': ownerId},
        )
        as String; // Impide abrir conversaciones de otros clientes sin ser trabajador.
  });
  @override
  Future<List<SupportMessage>> listMessages(
    String conversationId, {
    int limit = 100,
  }) => _run(() async {
    final rows = await _client
        .from('chat_messages')
        .select()
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .limit(
          limit,
        ); // Consulta el tramo reciente y permite ampliar el historial.
    return rows
        .map(SupportMessage.fromMap)
        .toList()
        .reversed
        .toList(); // Presenta el tramo de más antiguo a más reciente.
  });
  @override
  Future<void> sendMessage(String conversationId, String body) =>
      _run(() async {
        await _client.rpc(
          'send_chat_message',
          params: {
            'target_conversation': conversationId,
            'message_body': body.trim(),
          },
        ); // No permite al cliente escribir avisos de sistema.
      });
  @override
  Future<void> markRead(String conversationId, String lastMessageId) =>
      _run(() async {
        await _client.rpc(
          'mark_conversation_read',
          params: {
            'target_conversation': conversationId,
            'last_message': lastMessageId,
          },
        ); // No marca como leídos mensajes posteriores al tramo consultado.
      });
}
