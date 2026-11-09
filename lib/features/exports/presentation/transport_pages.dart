import 'dart:async'; // Renueva los envíos disponibles mientras el transportador mantiene abierta su lista.
import 'package:flutter/material.dart'; // Construye la toma de cargas y el seguimiento.
import 'package:flutter_riverpod/flutter_riverpod.dart'; // Comparte el estado del transportador y sus consultas.
import '../../auth/presentation/providers/auth_providers.dart'; // Identifica la cuenta a la que pertenecen las asignaciones.
import '../../commerce/presentation/pages/support_chat_page.dart'; // Abre la coordinación con el empleado y los avisos del envío.
import '../../commerce/presentation/providers/commerce_providers.dart'; // Actualiza las notificaciones del chat.
import '../../commerce/presentation/widgets/commerce_widgets.dart'; // Reutiliza recuperación y diálogos seguros.
import '../domain/export_models.dart'; // Conserva estados y rutas del transporte de café.
import 'export_providers.dart'; // Delega exclusividad, compatibilidad y entrega en el servidor.

/// El transportador toma una ruta y solo puede añadir lotes con los mismos extremos antes de salir.
class TransportJobsPage extends ConsumerStatefulWidget {
  const TransportJobsPage({super.key});
  @override
  ConsumerState<TransportJobsPage> createState() => _TransportJobsPageState();
}

class _TransportJobsPageState extends ConsumerState<TransportJobsPage> {
  Timer? _timer; // Detecta cargas tomadas por otros transportadores.
  bool _busy = false; // Impide duplicar una solicitud de toma.
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_busy) ref.invalidate(transportJobsProvider);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _refresh() {
    ref.invalidate(transportJobsProvider);
    ref.invalidate(coffeeShipmentsProvider);
    ref.invalidate(conversationsProvider);
  }

  Future<void> _take(CoffeeShipment shipment) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(coffeeExportsRepositoryProvider).take(shipment.id);
      if (mounted) {
        _refresh();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Tomaste el envío. Ahora eres responsable de su seguimiento.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        showCommerceError(context, error);
        _refresh();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authRepositoryProvider).currentUserId;
    return CommerceSection(
      title: 'Envíos del transportador',
      actions: [
        OutlinedButton(
          onPressed: _refresh,
          child: const Text('Actualizar cargas'),
        ),
      ],
      children: [
        const Text(
          'Toma el envío solicitado por el empleado. Puedes agrupar varios lotes únicamente cuando salen de la misma recogida y van al mismo destino, antes de iniciar la ruta.',
        ),
        CommerceAsyncPanel(
          value: ref.watch(transportJobsProvider),
          onRetry: _refresh,
          builder: (List<CoffeeShipment> items) {
            final assigned = items
                .where((item) => item.transporterId == user && item.isActive)
                .toList();
            final available = items
                .where((item) => item.transporterId == null)
                .toList();
            final completed = items
                .where(
                  (item) =>
                      item.transporterId == user && item.status == 'delivered',
                )
                .toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),
                Text(
                  'Mis envíos activos',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (assigned.isEmpty)
                  const Text(
                    'No tienes cargas asignadas. Selecciona un envío disponible.',
                  ),
                for (final item in assigned) _card(context, item, true),
                const SizedBox(height: 20),
                Text(
                  'Disponibles para tomar',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (available.isEmpty)
                  const Text('No hay cargas pendientes de transportador.'),
                for (final item in available) _card(context, item, false),
                if (completed.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(
                    'Entregas confirmadas',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  for (final item in completed) _card(context, item, false),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _card(
    BuildContext context,
    CoffeeShipment item,
    bool assigned,
  ) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${item.code} · ${item.lotCode}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(
            '${item.weight} kg\nRecogida: ${item.origin}\nDestino: ${item.destination}\nEstado: ${coffeeDeliveryStatuses[item.status] ?? item.status}',
          ),
          if (item.location != null) Text('Ubicación actual: ${item.location}'),
          if (assigned)
            Text('Destinatario: ${item.recipient}\nContacto: ${item.phone}'),
          Wrap(
            spacing: 12,
            children: [
              if (item.transporterId == null)
                FilledButton(
                  onPressed: _busy || !item.canTake ? null : () => _take(item),
                  child: Text(
                    item.canTake
                        ? 'Tomar este envío'
                        : 'No compatible con mi carga actual',
                  ),
                ),
              if (assigned)
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          await showDeliveryUpdate(context, ref, item);
                          if (mounted) _refresh();
                        },
                  child: const Text('Actualizar estado y ubicación'),
                ),
              if (item.transporterId != null && item.conversationId != null)
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => SupportChatPage(
                        conversationId: item.conversationId!,
                        title: 'Envíos · ${item.code}',
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.chat_outlined),
                  label: const Text('Chat del envío'),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

/// Recoge la anotación de cada estado y exige confirmación explícita para registrar la entrega.
Future<void> showDeliveryUpdate(
  BuildContext context,
  WidgetRef ref,
  CoffeeShipment item,
) async {
  final allowed = switch (item.status) {
    'accepted' => ['received'],
    'received' => ['in_transit'],
    'in_transit' => ['in_transit', 'delivered'],
    _ => <String>[],
  };
  if (allowed.isEmpty) return;
  var status = allowed.first;
  var confirmed = false;
  var busy = false;
  String? error;
  final notes = TextEditingController();
  final location = TextEditingController(text: item.location);
  final form = GlobalKey<FormState>();
  await showCommerceDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => PopScope(
        canPop: !busy,
        child: AlertDialog(
          title: Text('Seguimiento · ${item.code}'),
          content: SizedBox(
            width: 470,
            child: SingleChildScrollView(
              child: Form(
                key: form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: status,
                      items: allowed
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(coffeeDeliveryStatuses[value]!),
                            ),
                          )
                          .toList(),
                      onChanged: busy
                          ? null
                          : (value) => setState(() => status = value!),
                      decoration: const InputDecoration(
                        labelText: 'Estado del envío',
                      ),
                    ),
                    TextFormField(
                      controller: notes,
                      enabled: !busy,
                      minLines: 2,
                      maxLines: 5,
                      maxLength: 2000,
                      decoration: const InputDecoration(
                        labelText: 'Anotación para el asociado y el empleado',
                      ),
                      validator: (value) => (value?.trim().length ?? 0) < 3
                          ? 'Escribe una anotación de al menos 3 caracteres.'
                          : null,
                    ),
                    if (status == 'in_transit')
                      TextFormField(
                        controller: location,
                        enabled: !busy,
                        maxLength: 250,
                        decoration: const InputDecoration(
                          labelText:
                              'Ubicación actual: ciudad, vía o punto de referencia',
                        ),
                        validator: (value) => (value?.trim().length ?? 0) < 3
                            ? 'Indica dónde se encuentra el envío.'
                            : null,
                      ),
                    if (status == 'delivered')
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: confirmed,
                        onChanged: busy
                            ? null
                            : (value) =>
                                  setState(() => confirmed = value == true),
                        title: const Text(
                          'Confirmo que entregué el lote al destinatario en el destino acordado.',
                        ),
                      ),
                    if (error != null) Text(error!),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (!form.currentState!.validate()) return;
                      if (status == 'delivered' && !confirmed) {
                        setState(
                          () => error =
                              'Confirma la entrega antes de finalizar el envío.',
                        );
                        return;
                      }
                      setState(() => busy = true);
                      try {
                        await ref
                            .read(coffeeExportsRepositoryProvider)
                            .updateDelivery(
                              item.id,
                              status,
                              notes.text,
                              location.text,
                              confirmed,
                            );
                        if (context.mounted) {
                          ref.invalidate(transportJobsProvider);
                          ref.invalidate(coffeeShipmentsProvider);
                          ref.invalidate(conversationsProvider);
                          Navigator.of(context).pop();
                        }
                      } catch (problem) {
                        if (context.mounted) {
                          setState(() => error = problem.toString());
                        }
                      } finally {
                        if (context.mounted) setState(() => busy = false);
                      }
                    },
              child: Text(busy ? 'Guardando…' : 'Registrar actualización'),
            ),
          ],
        ),
      ),
    ),
  );
  notes.dispose();
  location.dispose();
}

/// El empleado coordina por chat qué carga debe tomar cada transportador; la toma siempre la confirma el transportador.
class TransporterDirectoryPage extends ConsumerStatefulWidget {
  const TransporterDirectoryPage({super.key});
  @override
  ConsumerState<TransporterDirectoryPage> createState() =>
      _TransporterDirectoryPageState();
}

class _TransporterDirectoryPageState
    extends ConsumerState<TransporterDirectoryPage> {
  bool _seeding =
      false; // Impide solicitar dos veces la creación de las cuentas de prueba.
  Future<void> _seed() async {
    if (_seeding) return;
    setState(() => _seeding = true);
    try {
      final result = await ref
          .read(coffeeExportsRepositoryProvider)
          .seedTransporters();
      if (mounted) {
        ref.invalidate(transportersProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Cuentas creadas: ${result['created']}. Existentes sin cambios: ${result['skipped']}. ${result['errors'] is List && (result['errors'] as List).isNotEmpty ? 'Revisa las cuentas que no pudieron prepararse: ${(result['errors'] as List).join('; ')}' : ''}',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) showCommerceError(context, error);
    } finally {
      if (mounted) setState(() => _seeding = false);
    }
  }

  Future<void> _chat(String driver, String name) async {
    try {
      final id = await ref
          .read(coffeeExportsRepositoryProvider)
          .transportConversation(driver);
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SupportChatPage(
              conversationId: id,
              title: 'Transporte · $name',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) showCommerceError(context, error);
    }
  }

  Future<void> _pickup(String driver, String name) async {
    List<CoffeeShipment> shipments;
    try {
      shipments = await ref.read(coffeeExportsRepositoryProvider).shipments();
    } catch (error) {
      if (mounted) showCommerceError(context, error);
      return;
    }
    if (!mounted) return;
    final available = shipments
        .where(
          (item) => item.status == 'accepted' && item.transporterId == null,
        )
        .toList();
    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay envíos aceptados pendientes de transportador.'),
        ),
      );
      return;
    }
    var selected = available.first.id;
    final notes = TextEditingController(
      text: 'Hola, por favor toma este envío de café.',
    );
    final form = GlobalKey<FormState>();
    var busy = false;
    String? error;
    await showCommerceDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => PopScope(
          canPop: !busy,
          child: AlertDialog(
            title: Text('Solicitar recogida a $name'),
            content: SizedBox(
              width: 470,
              child: Form(
                key: form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: selected,
                      isExpanded: true,
                      items: available
                          .map(
                            (item) => DropdownMenuItem(
                              value: item.id,
                              child: Text(
                                '${item.code} · ${item.lotCode}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: busy ? null : (value) => selected = value!,
                      decoration: const InputDecoration(
                        labelText: 'Envío aceptado',
                      ),
                    ),
                    TextFormField(
                      controller: notes,
                      enabled: !busy,
                      minLines: 2,
                      maxLines: 4,
                      maxLength: 2000,
                      decoration: const InputDecoration(
                        labelText: 'Indicación para el transportador',
                      ),
                      validator: (value) => (value?.trim().length ?? 0) < 3
                          ? 'Escribe una indicación para el transportador.'
                          : null,
                    ),
                    if (error != null) Text(error!),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : () => Navigator.of(context).pop(),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        if (!form.currentState!.validate()) return;
                        setState(() => busy = true);
                        try {
                          await ref
                              .read(coffeeExportsRepositoryProvider)
                              .requestPickup(driver, selected, notes.text);
                          if (context.mounted) {
                            ref.invalidate(conversationsProvider);
                            Navigator.of(context).pop();
                          }
                        } catch (problem) {
                          if (context.mounted) {
                            setState(() => error = problem.toString());
                          }
                        } finally {
                          if (context.mounted) setState(() => busy = false);
                        }
                      },
                child: const Text('Enviar al chat de Envíos'),
              ),
            ],
          ),
        ),
      ),
    );
    notes.dispose();
  }

  @override
  Widget build(BuildContext context) => CommerceSection(
    title: 'Transportadores',
    actions: [
      OutlinedButton(
        onPressed: () => ref.invalidate(transportersProvider),
        child: const Text('Actualizar'),
      ),
      if (ref.watch(currentUserProfileProvider).asData?.value?.isAdmin == true)
        FilledButton(
          onPressed: _seeding ? null : _seed,
          child: Text(
            _seeding
                ? 'Preparando cuentas…'
                : 'Crear cinco transportadores de prueba',
          ),
        ),
    ],
    children: [
      const Text(
        'Coordina por chat la recogida de cada envío. El transportador debe tomarlo desde su cuenta y confirmar sus estados y la entrega.',
      ),
      CommerceAsyncPanel(
        value: ref.watch(transportersProvider),
        onRetry: () => ref.invalidate(transportersProvider),
        builder: (List<Map<String, dynamic>> items) => Column(
          children: [
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No hay transportadores activos registrados.'),
              ),
            for (final driver in items)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        driver['full_name'],
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        '${driver['email']}\nCargas activas: ${driver['active_shipments']}',
                      ),
                      Wrap(
                        spacing: 12,
                        children: [
                          OutlinedButton(
                            onPressed: () =>
                                _chat(driver['id'], driver['full_name']),
                            child: const Text('Chat con transportador'),
                          ),
                          FilledButton(
                            onPressed: () =>
                                _pickup(driver['id'], driver['full_name']),
                            child: const Text('Solicitar recogida'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    ],
  );
}
