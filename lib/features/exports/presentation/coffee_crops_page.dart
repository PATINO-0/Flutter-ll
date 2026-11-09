import 'package:flutter/material.dart'; // Construye el inventario de cultivos y lotes.
import 'package:flutter_riverpod/flutter_riverpod.dart'; // Comparte consultas y permisos de la sesión.
import '../../auth/presentation/providers/auth_providers.dart'; // Distingue inventario propio de la gestión del personal.
import '../../commerce/presentation/providers/commerce_providers.dart'; // Permite al empleado seleccionar un asociado titular.
import '../../commerce/presentation/widgets/commerce_widgets.dart'; // Reutiliza estados y diálogos con ciclo de vida seguro.
import '../domain/export_models.dart'; // Representa cultivos y lotes reservados.
import 'export_providers.dart'; // Consulta y modifica el inventario mediante funciones protegidas.

/// El asociado consulta sus registros; el personal consulta el inventario de todos los titulares.
class CoffeeCropsPage extends ConsumerWidget {
  const CoffeeCropsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staff =
        ref
            .watch(currentUserProfileProvider)
            .asData
            ?.value
            ?.canManageOperations ==
        true;
    return CommerceSection(
      title: staff
          ? 'Cultivos y lotes de café'
          : 'Mis cultivos y lotes de café',
      actions: [
        FilledButton.icon(
          onPressed: () => _cultivation(context, ref),
          icon: const Icon(Icons.add),
          label: const Text('Registrar cultivo'),
        ),
        OutlinedButton.icon(
          onPressed: () => _lot(context, ref),
          icon: const Icon(Icons.inventory_2_outlined),
          label: const Text('Registrar lote'),
        ),
        OutlinedButton(
          onPressed: () {
            ref.invalidate(coffeeCultivationsProvider);
            ref.invalidate(coffeeExportLotsProvider);
          },
          child: const Text('Actualizar'),
        ),
      ],
      children: [
        const Text(
          'Cada lote pertenece a un cultivo y solo puede tener una exportación aprobada. Crea las solicitudes de envío desde Exportaciones.',
        ),
        const SizedBox(height: 16),
        Text('Cultivos', style: Theme.of(context).textTheme.titleLarge),
        CommerceAsyncPanel(
          value: ref.watch(coffeeCultivationsProvider),
          onRetry: () => ref.invalidate(coffeeCultivationsProvider),
          builder: (List<CoffeeCultivation> items) => Column(
            children: [
              if (items.isEmpty)
                const Text(
                  'Registra primero el cultivo, su finca, ubicación y variedad.',
                ),
              for (final crop in items)
                Card(
                  child: ListTile(
                    title: Text(crop.name),
                    subtitle: Text(
                      '${crop.farm} · ${crop.variety} · ${crop.hectares} ha\n${crop.location}',
                    ),
                    trailing: IconButton(
                      tooltip: 'Editar cultivo',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _cultivation(context, ref, crop),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text('Lotes de café', style: Theme.of(context).textTheme.titleLarge),
        CommerceAsyncPanel(
          value: ref.watch(coffeeExportLotsProvider),
          onRetry: () => ref.invalidate(coffeeExportLotsProvider),
          builder: (List<CoffeeExportLot> items) => Column(
            children: [
              if (items.isEmpty)
                const Text('Todavía no hay lotes registrados para exportar.'),
              for (final lot in items)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '${lot.code ?? 'Lote anterior sin código'} · ${lot.name}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          '${lot.weight} kg · Cosecha: ${lot.harvestDate ?? 'Pendiente de asignar'}\n${lot.origin}\n${lot.notes}',
                        ),
                        Text(switch (lot.reservationStatus) {
                          'approved' =>
                            'Exportación aprobada: este lote no puede volver a solicitarse.',
                          'pending' => 'Solicitud en revisión.',
                          'draft' =>
                            'Reservado en un borrador de Exportaciones.',
                          _ =>
                            lot.canRequest
                                ? 'Disponible para solicitar desde Exportaciones.'
                                : 'Asigna cultivo, propietario y código antes de exportar.',
                        }),
                        if (lot.reservationStatus == null)
                          Wrap(
                            children: [
                              TextButton(
                                onPressed: () => _lot(context, ref, lot),
                                child: const Text('Editar o asignar lote'),
                              ),
                              TextButton(
                                onPressed: () => _delete(context, ref, lot),
                                child: const Text('Eliminar lote'),
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

  String? _number(String? value, {double maximum = 10000000000}) {
    final number = double.tryParse((value ?? '').replaceAll(',', '.'));
    return number == null ||
            !number.isFinite ||
            number <= 0 ||
            number >= maximum
        ? 'Ingresa un número positivo válido.'
        : null;
  } // Valida pesos y áreas sin aceptar valores especiales.

  String? _text(String? value, int minimum) =>
      ((value?.trim().length ?? 0) < minimum)
      ? 'Completa este campo con al menos $minimum caracteres.'
      : null;

  Future<void> _cultivation(
    BuildContext context,
    WidgetRef ref, [
    CoffeeCultivation? crop,
  ]) async {
    final profile = ref.read(currentUserProfileProvider).asData?.value;
    if (profile == null) return;
    final customers = <DropdownMenuItem<String>>[
      DropdownMenuItem(value: profile.id, child: const Text('Mi cuenta')),
    ];
    if (profile.canManageOperations && crop == null) {
      try {
        for (final account
            in await ref.read(commerceRepositoryProvider).listCustomers()) {
          if (account.effectiveRole?.value == 'associate') {
            customers.add(
              DropdownMenuItem(
                value: account.id,
                child: Text(account.fullName),
              ),
            );
          }
        }
      } catch (error) {
        if (context.mounted) showCommerceError(context, error);
        return;
      }
    }
    if (!context.mounted) return;
    var owner = crop?.ownerId ?? profile.id;
    final name = TextEditingController(text: crop?.name);
    final farm = TextEditingController(text: crop?.farm);
    final location = TextEditingController(text: crop?.location);
    final variety = TextEditingController(text: crop?.variety);
    final hectares = TextEditingController(text: crop?.hectares.toString());
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
            title: Text(crop == null ? 'Registrar cultivo' : 'Editar cultivo'),
            content: SizedBox(
              width: 470,
              child: SingleChildScrollView(
                child: Form(
                  key: form,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (profile.canManageOperations && crop == null)
                        DropdownButtonFormField<String>(
                          initialValue: owner,
                          items: customers,
                          onChanged: busy ? null : (value) => owner = value!,
                          decoration: const InputDecoration(
                            labelText: 'Asociado titular',
                          ),
                        ),
                      for (final field in [
                        (name, 'Nombre del cultivo', 100),
                        (farm, 'Nombre de la finca', 150),
                        (location, 'Ubicación: municipio y dirección', 250),
                        (variety, 'Variedad del café', 100),
                      ])
                        TextFormField(
                          controller: field.$1,
                          enabled: !busy,
                          maxLength: field.$3,
                          decoration: InputDecoration(labelText: field.$2),
                          validator: (value) =>
                              _text(value, field.$1 == location ? 5 : 3),
                        ),
                      TextFormField(
                        controller: hectares,
                        enabled: !busy,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Área en hectáreas',
                        ),
                        validator: (value) =>
                            _number(value, maximum: 100000000),
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
                              .read(coffeeExportsRepositoryProvider)
                              .saveCultivation({
                                'target_id': crop?.id,
                                'target_owner': owner,
                                'cultivation_name': name.text.trim(),
                                'farm': farm.text.trim(),
                                'cultivation_location': location.text.trim(),
                                'coffee_variety': variety.text.trim(),
                                'hectares': double.parse(
                                  hectares.text.replaceAll(',', '.'),
                                ),
                              });
                          if (context.mounted) {
                            ref.invalidate(coffeeCultivationsProvider);
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
                child: Text(busy ? 'Guardando…' : 'Guardar cultivo'),
              ),
            ],
          ),
        ),
      ),
    );
    for (final controller in [name, farm, location, variety, hectares]) {
      controller.dispose();
    } // Libera los campos después de cerrar la animación del diálogo.
  }

  Future<void> _lot(
    BuildContext context,
    WidgetRef ref, [
    CoffeeExportLot? lot,
  ]) async {
    List<CoffeeCultivation> crops;
    try {
      crops = await ref.read(coffeeExportsRepositoryProvider).cultivations();
    } catch (error) {
      if (context.mounted) showCommerceError(context, error);
      return;
    }
    if (!context.mounted) return;
    if (crops.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Registra un cultivo antes de registrar su lote.'),
        ),
      );
      return;
    }
    var selected = crops.any((crop) => crop.id == lot?.cultivationId)
        ? lot!.cultivationId!
        : crops.first.id;
    final code = TextEditingController(text: lot?.code);
    final name = TextEditingController(text: lot?.name);
    final weight = TextEditingController(text: lot?.weight.toString());
    final harvest = TextEditingController(
      text:
          lot?.harvestDate ?? DateTime.now().toIso8601String().split('T').first,
    );
    final notes = TextEditingController(text: lot?.notes);
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
            title: Text(
              lot == null ? 'Registrar lote de café' : 'Editar lote de café',
            ),
            content: SizedBox(
              width: 470,
              child: SingleChildScrollView(
                child: Form(
                  key: form,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: selected,
                        items: crops
                            .map(
                              (crop) => DropdownMenuItem(
                                value: crop.id,
                                child: Text('${crop.name} · ${crop.farm}'),
                              ),
                            )
                            .toList(),
                        onChanged: busy ? null : (value) => selected = value!,
                        decoration: const InputDecoration(
                          labelText: 'Cultivo de origen',
                        ),
                      ),
                      TextFormField(
                        controller: code,
                        enabled: !busy,
                        maxLength: 50,
                        decoration: const InputDecoration(
                          labelText: 'Código único del lote',
                        ),
                        validator: (value) => _text(value, 2),
                      ),
                      TextFormField(
                        controller: name,
                        enabled: !busy,
                        maxLength: 100,
                        decoration: const InputDecoration(
                          labelText: 'Nombre o descripción del café',
                        ),
                        validator: (value) => _text(value, 3),
                      ),
                      TextFormField(
                        controller: weight,
                        enabled: !busy,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Peso total del lote en kg',
                        ),
                        validator: _number,
                      ),
                      TextFormField(
                        controller: harvest,
                        enabled: !busy,
                        decoration: const InputDecoration(
                          labelText: 'Fecha de cosecha (AAAA-MM-DD)',
                        ),
                        validator: (value) {
                          final date = DateTime.tryParse(value ?? '');
                          return date == null ||
                                  date.toIso8601String().split('T').first !=
                                      value ||
                                  date.isAfter(DateTime.now())
                              ? 'Ingresa una fecha de cosecha válida que no sea futura.'
                              : null;
                        },
                      ),
                      TextFormField(
                        controller: notes,
                        enabled: !busy,
                        minLines: 2,
                        maxLines: 4,
                        maxLength: 2000,
                        decoration: const InputDecoration(
                          labelText: 'Proceso, calidad y observaciones',
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
                        setState(() => busy = true);
                        try {
                          await ref
                              .read(coffeeExportsRepositoryProvider)
                              .saveLot({
                                'target_id': lot?.id,
                                'target_cultivation': selected,
                                'code': code.text.trim(),
                                'lot_name': name.text.trim(),
                                'weight': double.parse(
                                  weight.text.replaceAll(',', '.'),
                                ),
                                'harvest': harvest.text.trim(),
                                'lot_notes': notes.text.trim(),
                              });
                          if (context.mounted) {
                            ref.invalidate(coffeeExportLotsProvider);
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
                child: Text(busy ? 'Guardando…' : 'Guardar lote'),
              ),
            ],
          ),
        ),
      ),
    );
    for (final controller in [code, name, weight, harvest, notes]) {
      controller.dispose();
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    CoffeeExportLot lot,
  ) async {
    final accepted = await showCommerceDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar lote'),
        content: Text(
          '¿Deseas retirar ${lot.code ?? lot.name}? Un lote con historial debe conservarse.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (accepted != true || !context.mounted) return;
    try {
      await ref.read(coffeeExportsRepositoryProvider).deleteLot(lot.id);
      ref.invalidate(coffeeExportLotsProvider);
    } catch (error) {
      if (context.mounted) showCommerceError(context, error);
    }
  }
}
