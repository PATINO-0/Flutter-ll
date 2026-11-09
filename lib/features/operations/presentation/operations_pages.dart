import 'package:flutter/material.dart'; // Construye listas, formularios y seguimiento.
import 'package:flutter_riverpod/flutter_riverpod.dart'; // Comparte las operaciones autorizadas.
import '../../auth/presentation/providers/auth_providers.dart'; // Determina si se consulta una cuenta propia o se gestiona como personal.
import '../../auth/domain/entities/user_profile.dart'; // Mantiene tipada la selección de titulares comerciales.
import '../../commerce/presentation/providers/commerce_providers.dart'; // Consulta asociados disponibles para el trabajador.
import '../../commerce/presentation/widgets/commerce_widgets.dart'; // Comparte estados asíncronos y mensajes de error.
import '../data/operations_repository.dart'; // Consulta operaciones reales sin almacenar datos ficticios.

final operationsRepositoryProvider = Provider<OperationsRepository>(
  (ref) => OperationsRepository(ref.watch(supabaseClientProvider)),
); // Conserva los permisos de la sesión actual.
final shipmentsProvider = FutureProvider.autoDispose<List<Shipment>>((ref) {
  ref.watch(currentUserProfileProvider);
  return ref.watch(operationsRepositoryProvider).shipments();
}); // Actualiza los envíos cuando cambian los permisos.
final coffeeLotsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>(
      (ref) => ref.watch(operationsRepositoryProvider).coffeeLots(),
    ); // Mantiene la lista interna de café.

class ShipmentsPage extends ConsumerWidget {
  const ShipmentsPage({
    this.title = 'Mis envíos',
    this.exportsOnly = false,
    this.tracking = false,
    super.key,
  });
  final String title; // Conserva la sección escogida por el usuario.
  final bool
  exportsOnly; // Limita la vista de exportaciones sin cambiar las políticas de acceso.
  final bool
  tracking; // Prioriza los eventos y oculta la creación cuando solo se consulta seguimiento.
  @override
  Widget build(BuildContext context, WidgetRef ref) => CommerceSection(
    title: title,
    actions: [
      OutlinedButton(
        onPressed: () => ref.invalidate(shipmentsProvider),
        child: const Text('Actualizar'),
      ),
      if (!tracking)
        FilledButton(
          onPressed: () => _create(context, ref),
          child: const Text('Registrar operación'),
        ),
    ],
    children: [
      CommerceAsyncPanel(
        value: ref.watch(shipmentsProvider),
        onRetry: () => ref.invalidate(shipmentsProvider),
        builder: (List<Shipment> data) {
          final items = data
              .where((item) => !exportsOnly || item.type == 'export')
              .toList();
          return Column(
            children: [
              if (items.isEmpty)
                const Text(
                  'Todavía no hay operaciones registradas en esta sección.',
                ),
              for (final item in items)
                Card(
                  child: ExpansionTile(
                    title: Text(item.trackingCode),
                    subtitle: Text(
                      '${item.origin} → ${item.destination}\n${Shipment.statuses[item.status]}',
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          '${item.type == 'export' ? 'Exportación' : 'Importación'}: ${item.description}',
                        ),
                      ),
                      for (final event in item.events)
                        ListTile(
                          leading: const Icon(Icons.local_shipping_outlined),
                          title: Text(
                            Shipment.statuses[event['status']] ??
                                event['status'],
                          ),
                          subtitle: Text(
                            '${event['notes']}\n${DateTime.parse(event['created_at']).toLocal()}',
                          ),
                        ),
                      if (ref
                              .watch(currentUserProfileProvider)
                              .asData
                              ?.value
                              ?.canManageOperations ==
                          true)
                        TextButton(
                          onPressed: () => _status(context, ref, item),
                          child: const Text('Actualizar seguimiento'),
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

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final profile = ref.read(currentUserProfileProvider).asData?.value;
    if (profile == null) return;
    var owner = profile.id;
    var type = exportsOnly ? 'export' : 'import';
    final customers =
        <UserProfile>[]; // Solo el personal puede elegir a otro titular.
    if (profile.canManageOperations) {
      try {
        customers.addAll(
          await ref.read(commerceRepositoryProvider).listCustomers(),
        );
      } catch (error) {
        if (context.mounted) showCommerceError(context, error);
        return;
      }
    } // Conserva una salida recuperable si no se puede consultar al asociado.
    if (!context.mounted) return;
    final name = TextEditingController();
    final origin = TextEditingController();
    final destination = TextEditingController();
    final form = GlobalKey<FormState>();
    final choices = customers
        .where((user) => user.effectiveRole?.value == 'associate')
        .toList();
    if (profile.canManageOperations && choices.isNotEmpty) {
      owner = choices.first.id;
    }
    var busy = false;
    String? error;
    await showCommerceDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => PopScope(
          canPop: !busy,
          child: AlertDialog(
            title: const Text('Registrar operación'),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Form(
                  key: form,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (profile.canManageOperations)
                        DropdownButtonFormField<String>(
                          initialValue: owner,
                          items: [
                            DropdownMenuItem(
                              value: profile.id,
                              child: const Text('Mi cuenta'),
                            ),
                            ...choices.map(
                              (user) => DropdownMenuItem(
                                value: user.id,
                                child: Text(user.fullName),
                              ),
                            ),
                          ],
                          onChanged: busy ? null : (value) => owner = value!,
                          decoration: const InputDecoration(
                            labelText: 'Asociado titular',
                          ),
                        ),
                      DropdownButtonFormField<String>(
                        initialValue: type,
                        items: const [
                          DropdownMenuItem(
                            value: 'import',
                            child: Text('Importación'),
                          ),
                          DropdownMenuItem(
                            value: 'export',
                            child: Text('Exportación'),
                          ),
                        ],
                        onChanged: busy ? null : (value) => type = value!,
                        decoration: const InputDecoration(
                          labelText: 'Tipo de operación',
                        ),
                      ),
                      for (final field in [
                        (name, 'Descripción de la mercancía'),
                        (origin, 'Origen'),
                        (destination, 'Destino'),
                      ])
                        TextFormField(
                          controller: field.$1,
                          enabled: !busy,
                          decoration: InputDecoration(labelText: field.$2),
                          validator: (value) => (value?.trim().length ?? 0) < 3
                              ? 'Ingresa al menos 3 caracteres.'
                              : null,
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
                        setState(() => busy = true);
                        try {
                          await ref
                              .read(operationsRepositoryProvider)
                              .createShipment(
                                ownerId: owner,
                                type: type,
                                description: name.text,
                                origin: origin.text,
                                destination: destination.text,
                              );
                          if (context.mounted) {
                            ref.invalidate(shipmentsProvider);
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
                child: const Text('Registrar'),
              ),
            ],
          ),
        ),
      ),
    );
    name.dispose();
    origin.dispose();
    destination.dispose(); // Libera los campos después de cerrar el formulario.
  }

  Future<void> _status(
    BuildContext context,
    WidgetRef ref,
    Shipment item,
  ) async {
    final notes = TextEditingController();
    var status = 'in_transit';
    final confirmed = await showCommerceDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Actualizar seguimiento'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: status,
              items: Shipment.statuses.entries
                  .map(
                    (entry) => DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                  )
                  .toList(),
              onChanged: (value) => status = value!,
            ),
            TextField(
              controller: notes,
              maxLength: 2000,
              decoration: const InputDecoration(
                labelText: 'Descripción de la actualización',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    final text = notes.text;
    notes.dispose();
    if (confirmed != true) return;
    try {
      await ref
          .read(operationsRepositoryProvider)
          .updateStatus(item.id, status, text);
      ref.invalidate(shipmentsProvider);
    } catch (error) {
      if (context.mounted) showCommerceError(context, error);
    }
  }
}

class CoffeeLotsPage extends ConsumerWidget {
  const CoffeeLotsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => CommerceSection(
    title: 'Café',
    actions: [
      FilledButton(
        onPressed: () => _edit(context, ref),
        child: const Text('Registrar lote'),
      ),
      OutlinedButton(
        onPressed: () => ref.invalidate(coffeeLotsProvider),
        child: const Text('Actualizar'),
      ),
    ],
    children: [
      CommerceAsyncPanel(
        value: ref.watch(coffeeLotsProvider),
        onRetry: () => ref.invalidate(coffeeLotsProvider),
        builder: (List<Map<String, dynamic>> items) => Column(
          children: [
            if (items.isEmpty) const Text('Todavía no hay lotes registrados.'),
            for (final item in items)
              Card(
                child: ListTile(
                  title: Text(item['name']),
                  subtitle: Text(
                    '${item['origin']} · ${item['weight_kg']} kg\n${item['notes']}',
                  ),
                  trailing: Wrap(
                    children: [
                      IconButton(
                        tooltip: 'Editar lote',
                        onPressed: () => _edit(context, ref, item),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        tooltip: 'Eliminar lote',
                        onPressed: () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Eliminar lote'),
                              content: Text('¿Deseas retirar ${item['name']}?'),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(context).pop(false),
                                  child: const Text('Cancelar'),
                                ),
                                FilledButton(
                                  onPressed: () =>
                                      Navigator.of(context).pop(true),
                                  child: const Text('Eliminar'),
                                ),
                              ],
                            ),
                          );
                          if (confirmed == true) {
                            try {
                              await ref
                                  .read(operationsRepositoryProvider)
                                  .deleteCoffee(item['id']);
                              ref.invalidate(coffeeLotsProvider);
                            } catch (error) {
                              if (context.mounted) {
                                showCommerceError(context, error);
                              }
                            }
                          }
                        },
                        icon: const Icon(Icons.delete_outline),
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
  Future<void> _edit(
    BuildContext context,
    WidgetRef ref, [
    Map<String, dynamic>? item,
  ]) async {
    final name = TextEditingController(text: item?['name']);
    final origin = TextEditingController(text: item?['origin']);
    final weight = TextEditingController(
      text: item?['weight_kg']?.toString() ?? '',
    );
    final notes = TextEditingController(text: item?['notes']);
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
            title: const Text('Datos del lote de café'),
            content: SingleChildScrollView(
              child: Form(
                key: form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final field in [
                      (name, 'Nombre del lote'),
                      (origin, 'Origen'),
                    ])
                      TextFormField(
                        controller: field.$1,
                        enabled: !busy,
                        decoration: InputDecoration(labelText: field.$2),
                        validator: (value) => (value?.trim().length ?? 0) < 3
                            ? 'Ingresa al menos 3 caracteres.'
                            : null,
                      ),
                    TextFormField(
                      controller: weight,
                      enabled: !busy,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Peso en kilogramos',
                      ),
                      validator: (value) =>
                          (double.tryParse(value ?? '') ?? 0) <= 0
                          ? 'Ingresa un peso mayor que cero.'
                          : null,
                    ),
                    TextFormField(
                      controller: notes,
                      enabled: !busy,
                      maxLength: 2000,
                      decoration: const InputDecoration(
                        labelText: 'Observaciones',
                      ),
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
                              .read(operationsRepositoryProvider)
                              .saveCoffee({
                                if (item != null) 'id': item['id'],
                                'name': name.text.trim(),
                                'origin': origin.text.trim(),
                                'weight_kg': double.parse(weight.text),
                                'notes': notes.text.trim(),
                              });
                          if (context.mounted) {
                            ref.invalidate(coffeeLotsProvider);
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
                child: const Text('Guardar'),
              ),
            ],
          ),
        ),
      ),
    );
    for (final controller in [name, origin, weight, notes]) {
      controller.dispose();
    }
  }
}
