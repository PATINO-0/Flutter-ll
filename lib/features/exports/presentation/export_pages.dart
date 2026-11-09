import 'dart:async'; // Renueva únicamente las listas visibles sin reconstruir el dashboard.
import 'package:flutter/material.dart'; // Presenta solicitudes, expedientes y entregas.
import 'package:flutter_riverpod/flutter_riverpod.dart'; // Comparte las consultas del flujo de exportación.
import '../../auth/presentation/providers/auth_providers.dart'; // Identifica quién puede revisar solicitudes o modificar tarifas.
import '../../commerce/presentation/pages/support_chat_page.dart'; // Abre el chat correspondiente a cada exportación.
import '../../commerce/presentation/providers/commerce_providers.dart'; // Actualiza notificaciones después de resolver un expediente.
import '../../commerce/presentation/widgets/commerce_widgets.dart'; // Reutiliza estados y confirmaciones.
import '../domain/export_models.dart'; // Describe solicitudes y envíos exclusivamente de café.
import 'export_providers.dart'; // Delega cambios de estado y autorización en el servidor.
import 'export_request_form_page.dart'; // Crea y corrige solicitudes solamente desde Exportaciones.
import '../../commerce/presentation/pages/store_page.dart'; // Administra tarifas y rutas en una sola tienda.
import 'transport_pages.dart'; // Conserva la posibilidad de revisión operativa para administración.

/// Conserva las solicitudes y el archivo documental de las exportaciones aceptadas.
class CoffeeExportsPage extends ConsumerStatefulWidget {
  const CoffeeExportsPage({super.key});
  @override
  ConsumerState<CoffeeExportsPage> createState() => _CoffeeExportsPageState();
}

/// Conserva el filtro de archivo y actualiza solicitudes visibles sin cerrar formularios.
class _CoffeeExportsPageState extends ConsumerState<CoffeeExportsPage> {
  Timer?
  _refreshTimer; // Conserva la actualización de solicitudes sin depender del sondeo del perfil.
  /// Prepara las consultas y recursos locales al abrir la pantalla.
  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (ModalRoute.of(context)?.isCurrent == true &&
          !ref.read(coffeeExportRequestsProvider).isLoading) {
        ref.invalidate(coffeeExportRequestsProvider);
      } // Espera la consulta anterior y deja intactos los formularios abiertos encima de esta sección.
    });
  }

  /// Libera los controladores, suscripciones o temporizadores que conserva esta instancia.
  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  bool _archive =
      false; // Separa solicitudes en curso del archivo de expedientes aceptados.
  /// Ofrece exclusivamente lotes propios elegibles y abre el formulario de exportación.
  Future<void> _newRequest() async {
    List<CoffeeExportLot> lots;
    try {
      lots = await ref.read(coffeeExportsRepositoryProvider).lots();
    } catch (error) {
      if (mounted) showCommerceError(context, error);
      return;
    }
    if (!mounted) return;
    final owner = ref
        .read(authRepositoryProvider)
        .currentUserId; // El cargo solo puede autorizarlo el titular del lote.
    final available = lots
        .where((lot) => lot.canRequest && lot.ownerId == owner)
        .toList();
    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Registra en Café un cultivo y un lote que no tenga otra solicitud pendiente o exportación aprobada.',
          ),
        ),
      );
      return;
    }
    var selected = available.first.id;
    final confirmed = await showCommerceDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Seleccionar lote a exportar'),
        content: DropdownButtonFormField<String>(
          initialValue: selected,
          isExpanded: true,
          items: available
              .map(
                (lot) => DropdownMenuItem(
                  value: lot.id,
                  child: Text(
                    '${lot.code} · ${lot.weight} kg · ${lot.name}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: (value) => selected = value!,
          decoration: const InputDecoration(
            labelText: 'Lote de café registrado',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ExportRequestFormPage(lotId: selected),
        ),
      );
      if (mounted) _refresh();
    }
  }

  /// Renueva los datos de esta sección conservando el estado local de su pantalla.
  void _refresh() {
    ref.invalidate(coffeeExportRequestsProvider);
    ref.invalidate(coffeeExportLotsProvider);
    ref.invalidate(coffeeShipmentsProvider);
  }

  /// Construye la interfaz y observa únicamente los datos que necesita esta vista.
  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentUserProfileProvider).asData?.value;
    return CommerceSection(
      title: 'Exportaciones de café',
      actions: [
        if (profile?.effectiveRole?.value == 'associate' ||
            profile?.isAdmin == true)
          FilledButton.icon(
            onPressed: _newRequest,
            icon: const Icon(Icons.add),
            label: const Text('Solicitar exportación'),
          ),
        OutlinedButton(onPressed: _refresh, child: const Text('Actualizar')),
        if (profile?.isAdmin == true)
          OutlinedButton(
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => const StorePage())),
            child: const Text('Configurar tarifas y destinos'),
          ),
      ],
      children: [
        const Text(
          'Solicita desde aquí la exportación de un lote registrado. Los expedientes aceptados conservan sus datos, documentos y cargo autorizado.',
        ),
        const SizedBox(height: 12),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Solicitudes')),
            ButtonSegment(value: true, label: Text('Exportaciones aceptadas')),
          ],
          selected: {_archive},
          onSelectionChanged: (selected) =>
              setState(() => _archive = selected.first),
        ),
        CommerceAsyncPanel(
          value: ref.watch(coffeeExportRequestsProvider),
          onRetry: _refresh,
          builder: (List<CoffeeExportRequest> data) {
            final items = data
                .where(
                  (request) => _archive
                      ? request.status == 'approved'
                      : request.status != 'approved',
                )
                .toList();
            return Column(
              children: [
                if (items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Todavía no hay registros en esta sección.'),
                  ),
                for (final item in items)
                  Card(
                    child: ListTile(
                      title: Text(
                        '${item.label} · Lote ${item.snapshot['lot_code'] ?? ''}',
                      ),
                      subtitle: Text(
                        '${item.statusLabel}\n${item.destination.isEmpty ? 'Destino pendiente' : item.destination}${item.total == null ? '' : '\n${item.currency} ${item.total!.toStringAsFixed(2)}'}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              CoffeeExportDetailPage(requestId: item.id),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Presenta los documentos del lote, su autorización y la revisión del empleado.
class CoffeeExportDetailPage extends ConsumerStatefulWidget {
  const CoffeeExportDetailPage({required this.requestId, super.key});
  final String
  requestId; // Conserva el expediente abierto desde la lista o su chat.
  @override
  ConsumerState<CoffeeExportDetailPage> createState() =>
      _CoffeeExportDetailPageState();
}

/// Gestiona aceptación o rechazo de una exportación con motivo y actualización de sus módulos.
class _CoffeeExportDetailPageState
    extends ConsumerState<CoffeeExportDetailPage> {
  bool _busy = false;

  /// Confirma la decisión del personal y exige explicar las correcciones cuando se rechaza.
  Future<void> _review(bool approve) async {
    final reason = TextEditingController();
    final form = GlobalKey<FormState>();
    final confirmed = await showCommerceDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          approve ? 'Aceptar exportación de café' : 'Rechazar exportación',
        ),
        content: approve
            ? const Text(
                'Se archivarán los documentos, se registrará el cargo autorizado y el lote quedará reservado definitivamente. El envío estará disponible para transporte.',
              )
            : Form(
                key: form,
                child: TextFormField(
                  controller: reason,
                  minLines: 3,
                  maxLines: 5,
                  maxLength: 2000,
                  decoration: const InputDecoration(
                    labelText: 'Motivo y correcciones requeridas',
                  ),
                  validator: (value) => (value?.trim().length ?? 0) < 5
                      ? 'Explica el rechazo con al menos 5 caracteres.'
                      : null,
                ),
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (approve || form.currentState!.validate()) {
                Navigator.of(context).pop(true);
              }
            },
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    final explanation = reason.text;
    reason.dispose();
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(coffeeExportsRepositoryProvider)
          .review(widget.requestId, approve, explanation);
      if (mounted) {
        ref.invalidate(coffeeExportRequestProvider(widget.requestId));
        ref.invalidate(coffeeExportRequestsProvider);
        ref.invalidate(coffeeExportLotsProvider);
        ref.invalidate(coffeeShipmentsProvider);
        ref.invalidate(transportJobsProvider);
        ref.invalidate(conversationsProvider);
      }
    } catch (error) {
      if (mounted) showCommerceError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Construye la interfaz y observa únicamente los datos que necesita esta vista.
  @override
  Widget build(BuildContext context) {
    final staff =
        ref
            .watch(currentUserProfileProvider)
            .asData
            ?.value
            ?.canManageOperations ==
        true;
    return Scaffold(
      appBar: AppBar(title: const Text('Expediente de exportación')),
      body: CommerceAsyncPanel(
        value: ref.watch(coffeeExportRequestProvider(widget.requestId)),
        onRetry: () =>
            ref.invalidate(coffeeExportRequestProvider(widget.requestId)),
        builder: (CoffeeExportRequest item) => CommerceSection(
          title: '${item.label} · ${item.statusLabel}',
          actions: [
            if ((item.status == 'draft' || item.status == 'rejected') &&
                item.ownerId == ref.read(authRepositoryProvider).currentUserId)
              FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ExportRequestFormPage(lotId: item.lotId),
                  ),
                ),
                child: Text(
                  item.status == 'draft'
                      ? 'Continuar solicitud'
                      : 'Corregir y volver a solicitar',
                ),
              ),
            if (item.conversationId != null)
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SupportChatPage(
                      conversationId: item.conversationId!,
                      title: 'Envíos · ${item.label}',
                    ),
                  ),
                ),
                icon: const Icon(Icons.chat_outlined),
                label: const Text('Chat de Envíos'),
              ),
          ],
          children: [
            Text(
              'Lote: ${item.snapshot['lot_code'] ?? ''}\nCafé: ${item.snapshot['lot_name'] ?? ''}\nCultivo: ${item.snapshot['cultivation_name'] ?? 'Registrado'}\nFinca: ${item.snapshot['farm_name'] ?? ''}\nVariedad: ${item.snapshot['variety'] ?? ''}\nPeso: ${item.snapshot['weight_kg'] ?? ''} kg',
            ),
            const SizedBox(height: 12),
            Text(
              'Recogida: ${item.origin}\nDestino: ${item.destination}\nDestinatario: ${item.recipient}\nContacto: ${item.phone}',
            ),
            if (item.tariffSnapshot.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Tarifa autorizada: ${item.tariffSnapshot['title']}\nRuta: ${item.tariffSnapshot['origin']} → ${item.tariffSnapshot['destination']}\n${item.tariffSnapshot['currency']} ${item.tariffSnapshot['rate_per_kg']}/kg\nCondiciones: ${item.tariffSnapshot['description']}',
                ),
              ), // Presenta los valores históricos, no los precios actuales de la tienda.
            if (item.total != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Cargo autorizado: ${item.currency} ${item.total!.toStringAsFixed(2)}${item.chargeStatus == null ? ' · Pendiente de revisión' : ' · Registrado en Ritech'}',
                ),
              ),
            if (item.trackingCode != null)
              Text(
                'Envío: ${item.trackingCode}\nEstado: ${coffeeDeliveryStatuses[item.shipmentStatus] ?? item.shipmentStatus}',
              ),
            if (item.rejectionReason != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Correcciones solicitadas: ${item.rejectionReason}',
                ),
              ),
            const SizedBox(height: 16),
            Text(
              'Documentos de la exportación',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            for (final document in item.documents)
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(document.name),
                trailing: IconButton(
                  tooltip: 'Abrir documento privado',
                  icon: const Icon(Icons.open_in_new),
                  onPressed: () async {
                    try {
                      await ref
                          .read(coffeeExportsRepositoryProvider)
                          .openDocument(document.path);
                    } catch (error) {
                      if (context.mounted) showCommerceError(context, error);
                    }
                  },
                ),
              ),
            if (staff && item.status == 'pending')
              Wrap(
                spacing: 12,
                children: [
                  FilledButton(
                    onPressed: _busy ? null : () => _review(true),
                    child: const Text('Aceptar envío'),
                  ),
                  OutlinedButton(
                    onPressed: _busy ? null : () => _review(false),
                    child: const Text('Rechazar con correcciones'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Mis envíos contiene solo entregas realizadas; Seguimiento contiene únicamente cargas activas.
class CoffeeShipmentHistoryPage extends ConsumerStatefulWidget {
  const CoffeeShipmentHistoryPage({this.tracking = false, super.key});
  final bool tracking;
  @override
  ConsumerState<CoffeeShipmentHistoryPage> createState() =>
      _CoffeeShipmentHistoryPageState();
}

/// Actualiza estados manteniendo la expansión del envío correcto cuando llegan otros registros.
class _CoffeeShipmentHistoryPageState
    extends ConsumerState<CoffeeShipmentHistoryPage> {
  Timer?
  _refreshTimer; // Actualiza entregas y ubicaciones conservando las tarjetas desplegadas.
  /// Selecciona seguimiento activo o historial de entregas sin duplicar el componente.
  bool get tracking => widget.tracking;

  /// Prepara las consultas y recursos locales al abrir la pantalla.
  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (ModalRoute.of(context)?.isCurrent == true &&
          !ref.read(coffeeShipmentsProvider).isLoading) {
        ref.invalidate(coffeeShipmentsProvider);
      }
    });
  }

  /// Libera los controladores, suscripciones o temporizadores que conserva esta instancia.
  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  /// Construye la interfaz y observa únicamente los datos que necesita esta vista.
  @override
  Widget build(BuildContext context) => CommerceSection(
    title: tracking
        ? 'Seguimiento de exportaciones activas'
        : 'Mis envíos realizados',
    actions: [
      OutlinedButton(
        onPressed: () => ref.invalidate(coffeeShipmentsProvider),
        child: const Text('Actualizar'),
      ),
    ],
    children: [
      Text(
        tracking
            ? 'Consulta los estados y ubicaciones de los lotes que todavía no han sido entregados.'
            : 'Aquí se conservan los lotes entregados y el destino al que llegaron. Las solicitudes nuevas se crean desde Exportaciones.',
      ),
      CommerceAsyncPanel(
        value: ref.watch(coffeeShipmentsProvider),
        onRetry: () => ref.invalidate(coffeeShipmentsProvider),
        builder: (List<CoffeeShipment> data) {
          final items = data
              .where(
                (shipment) => tracking
                    ? shipment.isActive
                    : shipment.status == 'delivered',
              )
              .toList();
          return Column(
            children: [
              if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    tracking
                        ? 'No hay exportaciones activas.'
                        : 'Todavía no hay envíos entregados.',
                  ),
                ),
              for (final item in items)
                Card(
                  key: ValueKey(
                    item.id,
                  ), // Conserva la expansión del envío correcto al llegar otros registros.
                  child: ExpansionTile(
                    title: Text('${item.code} · ${item.lotCode}'),
                    subtitle: Text(
                      '${coffeeDeliveryStatuses[item.status] ?? item.status}\n${item.origin} → ${item.destination}${item.location == null ? '' : '\nUbicación: ${item.location}'}${item.deliveredAt == null ? '' : '\nEntregado: ${DateTime.parse(item.deliveredAt!).toLocal()}'}',
                    ),
                    children: [
                      for (final event in item.events)
                        ListTile(
                          title: Text(
                            coffeeDeliveryStatuses[event['status']] ??
                                event['status'],
                          ),
                          subtitle: Text(
                            '${event['notes']}${event['location'] == null ? '' : '\nUbicación: ${event['location']}'}\n${DateTime.parse(event['created_at']).toLocal()}',
                          ),
                        ),
                      if (item.requestId != null)
                        TextButton(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => CoffeeExportDetailPage(
                                requestId: item.requestId!,
                              ),
                            ),
                          ),
                          child: const Text(
                            'Ver lote y documentos de exportación',
                          ),
                        ),
                      if (tracking &&
                          ref
                                  .watch(currentUserProfileProvider)
                                  .asData
                                  ?.value
                                  ?.isAdmin ==
                              true)
                        TextButton(
                          onPressed: () =>
                              showDeliveryUpdate(context, ref, item),
                          child: const Text(
                            'Actualizar seguimiento como administrador',
                          ),
                        ),
                      if (item.conversationId != null)
                        TextButton(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => SupportChatPage(
                                conversationId: item.conversationId!,
                                title: 'Envíos · ${item.code}',
                              ),
                            ),
                          ),
                          child: const Text('Abrir chat del envío'),
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    ],
  );
}
